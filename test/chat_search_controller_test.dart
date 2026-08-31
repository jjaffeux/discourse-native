import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_search_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const site = 'https://meta.discourse.org';

ChatSearchHit hit(int id, {int channelId = 9}) => ChatSearchHit(
  message: ChatMessage(
    id: id,
    channelId: channelId,
    cooked: '<p>message $id</p>',
    author: const ChatMessageAuthor(id: 2, username: 'sam'),
    createdAt: DateTime.utc(2026, 8, 25, 10),
  ),
  channel: ChatChannel(
    id: channelId,
    title: 'Bugs',
    kind: ChatChannelKind.category,
  ),
  excerpt: 'message $id',
);

Future<void> drain() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeApiCredentialReader credentials;
  late Store store;
  late SiteLifecycle lifecycle;

  setUp(() {
    credentials = FakeApiCredentialReader()..keys[site] = 'key';
    store = Store();
    lifecycle = SiteLifecycle();
  });

  group('global search', () {
    test('stores results and appends unique pages', () async {
      final api = FakeDiscourseApi(
        chatSearchPagesByKey: {
          FakeDiscourseApi.chatSearchKey('needle'): ChatSearchPage(
            hits: [hit(1), hit(2)],
            hasMore: true,
          ),
          FakeDiscourseApi.chatSearchKey('needle', offset: 2): ChatSearchPage(
            hits: [hit(2), hit(3)],
            hasMore: true,
          ),
          FakeDiscourseApi.chatSearchKey('needle', offset: 4): ChatSearchPage(
            hits: [hit(4)],
          ),
        },
      );
      final search = ChatSearchController(
        api: api,
        requests: FakePluginRequestHost(
          credentials: credentials,
          lifecycle: lifecycle,
        ),
        store: store,
        debounceDuration: Duration.zero,
      );
      addTearDown(search.dispose);

      search.setGlobalQuery(site, 'needle');
      await drain();
      expect(search.globalState(site).hits.map((entry) => entry.id), [1, 2]);
      expect(store.read<ChatMessage>(site, 1), isNotNull);

      search.loadMore(site);
      await drain();
      expect(search.globalState(site).hits.map((entry) => entry.id), [1, 2, 3]);
      expect(api.chatSearchesRequested.last.offset, 2);

      search.loadMore(site);
      await drain();
      expect(search.globalState(site).hits.map((entry) => entry.id), [
        1,
        2,
        3,
        4,
      ]);
      expect(api.chatSearchesRequested.last.offset, 4);
    });

    test('a newer query owns the answer', () async {
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        chatSearchGate: gate,
        chatSearchPagesByKey: {
          FakeDiscourseApi.chatSearchKey('old'): ChatSearchPage(hits: [hit(1)]),
          FakeDiscourseApi.chatSearchKey('new'): ChatSearchPage(hits: [hit(2)]),
        },
      );
      final search = ChatSearchController(
        api: api,
        requests: FakePluginRequestHost(
          credentials: credentials,
          lifecycle: lifecycle,
        ),
        store: store,
        debounceDuration: Duration.zero,
      );
      addTearDown(search.dispose);

      search.setGlobalQuery(site, 'old');
      await drain();
      search.setGlobalQuery(site, 'new');
      await drain();
      expect(api.chatSearchesRequested, hasLength(2));
      gate.complete();
      await drain();

      expect(search.globalState(site).query, 'new');
      expect(search.globalState(site).hits.single.id, 2);
      expect(store.read<ChatMessage>(site, 1), isNull);
    });
  });

  group('channel search', () {
    test('uses latest, excludes replies, and cycles results', () async {
      final api = FakeDiscourseApi(
        chatSearchPagesByKey: {
          FakeDiscourseApi.chatSearchKey(
            'needle',
            channelId: 9,
            sort: ChatSearchSort.latest,
          ): ChatSearchPage(
            hits: [hit(2), hit(1)],
          ),
        },
      );
      final search = ChatSearchController(
        api: api,
        requests: FakePluginRequestHost(
          credentials: credentials,
          lifecycle: lifecycle,
        ),
        store: store,
        debounceDuration: Duration.zero,
      );
      addTearDown(search.dispose);

      search.openScoped(site, 9);
      search.setScopedQuery(site, 9, 'needle');
      await drain();

      final request = api.chatSearchesRequested.single;
      expect(request.channelId, 9);
      expect(request.sort, ChatSearchSort.latest);
      expect(request.excludeThreads, isTrue);
      expect(search.scopedState(site, 9).selectedHit?.id, 2);

      search.selectPrevious(site, 9);
      expect(search.scopedState(site, 9).selectedHit?.id, 1);
      search.selectPrevious(site, 9);
      expect(search.scopedState(site, 9).selectedHit?.id, 2);
      search.selectNext(site, 9);
      expect(search.scopedState(site, 9).selectedHit?.id, 1);
    });

    test('closing rejects its late response', () async {
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        chatSearchGate: gate,
        chatSearchPagesByKey: {
          FakeDiscourseApi.chatSearchKey(
            'needle',
            channelId: 9,
            sort: ChatSearchSort.latest,
          ): ChatSearchPage(
            hits: [hit(1)],
          ),
        },
      );
      final search = ChatSearchController(
        api: api,
        requests: FakePluginRequestHost(
          credentials: credentials,
          lifecycle: lifecycle,
        ),
        store: store,
        debounceDuration: Duration.zero,
      );
      addTearDown(search.dispose);

      search.openScoped(site, 9);
      search.setScopedQuery(site, 9, 'needle');
      await drain();
      search.closeScoped(site, 9);
      gate.complete();
      await drain();

      expect(search.scopedState(site, 9), const ScopedChatSearchState());
      expect(store.read<ChatMessage>(site, 1), isNull);
    });
  });
}
