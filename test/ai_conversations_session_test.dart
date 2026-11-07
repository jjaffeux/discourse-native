import 'dart:async';

import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_conversations_service.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_conversations_session.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://forum.example';
const _first = AiConversation(id: 1, title: 'First', slug: 'first');
const _second = AiConversation(id: 2, title: 'Second', slug: 'second');
const _fresh = AiConversation(id: 9, title: 'Fresh', slug: 'fresh');

void main() {
  test(
    'a refresh supersedes paging and published rows are immutable snapshots',
    () async {
      final source = _Source();
      final requests = PluginTestRequestHost();
      final session = AiConversationsSession(
        account: requests.capture(_site),
        load: source.load,
        open: (_) {},
      );
      addTearDown(session.dispose);
      final first = session.refresh();
      source.requests.last.result.complete(
        _page([_first], page: 0, more: true),
      );
      await first;
      final held = session.state;
      final more = session.loadMore();
      await session.loadMore();
      expect(source.requests.map((request) => request.page), [0, 1]);
      final refresh = session.refresh();
      source.requests.last.result.complete(_page([_fresh], page: 0));
      await refresh;
      source.requests[1].result.complete(_page([_second], page: 1));
      await more;
      expect(session.state.conversations, [_fresh]);
      expect(session.state.page, 0);
      expect(held.conversations, [_first]);
      expect(session.state.conversations.clear, throwsUnsupportedError);
    },
  );

  test(
    'retirement clears rows, denies stale selections, and observes late errors',
    () async {
      final source = _Source();
      final requests = PluginTestRequestHost();
      final opened = <AiConversation>[];
      final session = AiConversationsSession(
        account: requests.capture(_site),
        load: source.load,
        open: opened.add,
      );
      addTearDown(session.dispose);
      final first = session.refresh();
      source.requests.last.result.complete(
        _page([_first], page: 0, more: true),
      );
      await first;
      session.open(_first);
      expect(opened, [_first]);
      final more = session.loadMore();
      requests.forget(_site);
      expect(session.state.conversations, isEmpty);
      expect(session.state.loading, isFalse);
      expect(session.state.unavailable, isTrue);
      session.open(_first);
      await session.refresh();
      await session.loadMore();
      expect(source.requests, hasLength(2));
      expect(opened, [_first]);
      source.requests.last.result.completeError(StateError('late response'));
      await more;
      expect(session.state.conversations, isEmpty);
      expect(session.state.page, -1);
    },
  );

  test(
    'a failed page retries its own cursor and keeps held row identities',
    () async {
      final source = _Source();
      final requests = PluginTestRequestHost();
      final session = AiConversationsSession(
        account: requests.capture(_site),
        load: source.load,
        open: (_) {},
      );
      addTearDown(session.dispose);
      final first = session.refresh();
      source.requests.last.result.complete(
        _page([_first], page: 0, more: true),
      );
      await first;
      final more = session.loadMore();
      source.requests.last.result.completeError(StateError('offline'));
      await more;
      expect(session.state.error, isTrue);
      expect(session.state.conversations, [_first]);
      final retry = session.retry();
      expect(source.requests.map((request) => request.page), [0, 1, 1]);
      source.requests.last.result.complete(_page([_first, _second], page: 1));
      await retry;
      expect(session.state.conversations, [_first, _second]);
      expect(session.state.conversations.first, same(_first));
      expect(session.state.hasMore, isFalse);
    },
  );
}

AiConversationPage _page(
  List<AiConversation> rows, {
  required int page,
  bool more = false,
}) => AiConversationPage(conversations: rows, page: page, hasMore: more);

final class _Source {
  final requests = <({int page, Completer<AiConversationPage?> result})>[];
  Future<AiConversationPage?> load(int page) {
    final result = Completer<AiConversationPage?>();
    requests.add((page: page, result: result));
    return result.future;
  }
}
