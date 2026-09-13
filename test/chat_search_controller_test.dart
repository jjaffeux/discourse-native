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

class CountingCredentials extends FakeApiCredentialReader {
  int reads = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    reads++;
    return super.apiKeyFor(siteUrl);
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
    testWidgets('rejects overlong retries and sort changes', (tester) async {
      final credentials = CountingCredentials()..keys[site] = 'key';
      final api = FakeDiscourseApi();
      final search = ChatSearchController(
        api: api,
        requests: FakePluginRequestHost(credentials: credentials),
        store: store,
      );
      addTearDown(search.dispose);
      final query = 'x' * (ChatSearchController.maximumQueryLength + 1);
      final phases = <ChatSearchPhase>[];
      search.setGlobalQuery(site, query);
      search.globalRef(site).addListener(() {
        phases.add(search.globalState(site).phase);
      });
      await search.retryGlobal(site);
      search.setGlobalSort(site, ChatSearchSort.latest);
      await tester.pump(const Duration(seconds: 1));
      expect(credentials.reads, 0);
      expect(api.chatSearchesRequested, isEmpty);
      expect(phases, everyElement(ChatSearchPhase.failed));
      expect(
        search.globalState(site).error,
        'Search terms must be at most 2048 characters.',
      );
      expect(search.globalState(site).sort, ChatSearchSort.latest);
    });

    for (final phase in [ChatSearchPhase.waiting, ChatSearchPhase.loading]) {
      for (final action in [
        'replace',
        'clear',
        'forget',
        'invalidate',
        if (phase == ChatSearchPhase.waiting) 'retry',
      ]) {
        testWidgets('$action during $phase notification', (tester) async {
          final credentials = CountingCredentials()..keys[site] = 'key';
          final api = FakeDiscourseApi();
          final search = ChatSearchController(
            api: api,
            requests: FakePluginRequestHost(
              credentials: credentials,
              lifecycle: lifecycle,
            ),
            store: store,
          );
          addTearDown(search.dispose);
          void setQuery(String query) {
            search.setGlobalQuery(site, query);
          }

          var changed = false;
          void listener() {
            final currentPhase = search.globalState(site).phase;
            if (changed || currentPhase != phase) return;
            changed = true;
            switch (action) {
              case 'replace':
                setQuery('new');
              case 'clear':
                setQuery('');
              case 'forget':
                search.forget(site);
              case 'invalidate':
                lifecycle.invalidate(site);
              case 'retry':
                unawaited(search.retryGlobal(site));
            }
          }

          search.globalRef(site).addListener(listener);
          setQuery('old');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          expect(changed, isTrue);
          final expected = action == 'replace'
              ? ['new']
              : action == 'retry'
              ? ['old']
              : <String>[];
          expect(
            api.chatSearchesRequested.map((request) => request.query),
            expected,
          );
          expect(credentials.reads, expected.length);
          if (action == 'replace' || action == 'clear' || action == 'forget') {
            expect(
              search.globalState(site).query,
              action == 'replace' ? 'new' : '',
            );
          }
        });
      }
    }

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

    test(
      'retry and sort restart pagination and retain the state ref',
      () async {
        final api = FakeDiscourseApi(
          chatSearchPagesByKey: {
            for (final sort in ChatSearchSort.values)
              FakeDiscourseApi.chatSearchKey('needle', sort: sort):
                  ChatSearchPage(hits: [hit(1)], hasMore: true),
            FakeDiscourseApi.chatSearchKey('needle', offset: 1): ChatSearchPage(
              hits: [hit(2)],
              hasMore: true,
            ),
          },
        );
        final search = ChatSearchController(
          api: api,
          requests: FakePluginRequestHost(credentials: credentials),
          store: store,
          debounceDuration: Duration.zero,
        );
        addTearDown(search.dispose);
        final ref = search.globalRef(site);
        search.setGlobalQuery(site, 'needle');
        await drain();
        search.loadMore(site);
        await drain();
        expect(ref.value.nextOffset, 2);
        await search.retryGlobal(site);
        expect(ref.value.nextOffset, 1);
        expect(ref.value.hits.map((hit) => hit.id), [1]);
        search.loadMore(site);
        await drain();
        search.setGlobalSort(site, ChatSearchSort.latest);
        await drain();
        expect(ref.value.nextOffset, 1);
        expect(api.chatSearchesRequested.last.offset, 0);
        expect(api.chatSearchesRequested.last.sort, ChatSearchSort.latest);
        expect(identical(ref, search.globalRef(site)), isTrue);
        expect(ref.value, search.globalState(site));
      },
    );

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
}
