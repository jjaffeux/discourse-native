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

class _HeldSearchApi extends FakeDiscourseApi {
  _HeldSearchApi({
    required this.completion,
    required this.heldOffset,
    required super.chatSearchPagesByKey,
  });

  final Completer<void> completion;
  final int heldOffset;

  @override
  Future<ChatSearchPage> searchChatMessages({
    required String siteUrl,
    required String apiKey,
    required String query,
    int? channelId,
    ChatSearchSort sort = ChatSearchSort.relevance,
    int offset = 0,
    int limit = ChatSearchPage.defaultPageSize,
    bool excludeThreads = false,
    String? clientId,
  }) async {
    final page = await super.searchChatMessages(
      siteUrl: siteUrl,
      apiKey: apiKey,
      query: query,
      channelId: channelId,
      sort: sort,
      offset: offset,
      limit: limit,
      excludeThreads: excludeThreads,
      clientId: clientId,
    );
    if (offset == heldOffset) await completion.future;
    return page;
  }
}

void expectCanonicalMessage(ChatMessage? actual, ChatMessage? expected) {
  if (expected == null) {
    expect(actual, isNull);
    return;
  }
  expect(actual, isNotNull);
  expect(actual!.cooked, expected.cooked);
  expect(actual.raw, expected.raw);
  expect(actual.edited, expected.edited);
  expect(actual.deletedAt, expected.deletedAt);
  expect(actual.pinned, expected.pinned);
  expect(
    actual.reactions.map(
      (reaction) => (reaction.emoji, reaction.count, reaction.reacted),
    ),
    expected.reactions.map(
      (reaction) => (reaction.emoji, reaction.count, reaction.reacted),
    ),
  );
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

    test(
      'pagination advances past rejected records in a decoded page',
      () async {
        Map<String, dynamic> row(int id) => {
          'id': id,
          'chat_channel_id': 9,
          'channel': {'id': 9},
        };
        final api = FakeDiscourseApi(
          chatSearchPagesByKey: {
            FakeDiscourseApi.chatSearchKey('needle'): ChatSearchPage.fromJson({
              'messages': [row(1), const <String, dynamic>{}],
              'meta': const {'has_more': true},
            }, site),
            FakeDiscourseApi.chatSearchKey(
              'needle',
              offset: 2,
            ): ChatSearchPage.fromJson({
              'messages': [
                const <String, dynamic>{},
                {...row(2), 'chat_channel_id': 10},
              ],
              'meta': const {'has_more': true},
            }, site),
            FakeDiscourseApi.chatSearchKey(
              'needle',
              offset: 4,
            ): ChatSearchPage.fromJson({
              'messages': [row(3)],
            }, site),
          },
        );
        final search = ChatSearchController(
          api: api,
          requests: FakePluginRequestHost(credentials: credentials),
          store: store,
          debounceDuration: Duration.zero,
        );
        addTearDown(search.dispose);
        search.setGlobalQuery(site, 'needle');
        await drain();
        expect(search.globalState(site).nextOffset, 2);
        search.loadMore(site);
        await drain();
        expect(search.globalState(site).nextOffset, 4);
        expect(search.globalState(site).hits.map((hit) => hit.id), [1]);
        search.loadMore(site);
        await drain();
        expect(api.chatSearchesRequested.map((request) => request.offset), [
          0,
          2,
          4,
        ]);
        expect(search.globalState(site).hits.map((hit) => hit.id), [1, 3]);
        expect(search.globalState(site).hasMore, isFalse);
      },
    );

    for (final heldOffset in [0, 2]) {
      for (final mutation in ['edit', 'delete', 'reaction', 'pin', 'remove']) {
        test(
          'late search at offset $heldOffset preserves canonical $mutation',
          () async {
            final gate = Completer<void>();
            addTearDown(() {
              if (!gate.isCompleted) gate.complete();
            });
            final old = hit(2);
            final api = _HeldSearchApi(
              completion: gate,
              heldOffset: heldOffset,
              chatSearchPagesByKey: {
                FakeDiscourseApi.chatSearchKey('needle'): ChatSearchPage(
                  hits: heldOffset == 0 ? [old, hit(3)] : [hit(1), old],
                  hasMore: heldOffset != 0,
                ),
                FakeDiscourseApi.chatSearchKey('needle', offset: 2):
                    ChatSearchPage(hits: [old, hit(3)], hasMore: true),
                FakeDiscourseApi.chatSearchKey('needle', offset: 4):
                    ChatSearchPage(hits: [hit(4)]),
              },
            );
            final search = ChatSearchController(
              api: api,
              requests: FakePluginRequestHost(credentials: credentials),
              store: store,
              debounceDuration: Duration.zero,
            );
            addTearDown(search.dispose);
            store.put(site, old.message);
            search.setGlobalQuery(site, 'needle');
            await drain();
            if (heldOffset != 0) {
              expect(search.globalState(site).hits.map((hit) => hit.id), [
                1,
                2,
              ]);
              search.loadMore(site);
              await drain();
              expect(search.globalState(site).loadingMore, isTrue);
            }
            expect(api.chatSearchesRequested.last.offset, heldOffset);
            final updated = switch (mutation) {
              'edit' => ChatMessage(
                id: old.id,
                channelId: old.message.channelId,
                cooked: '<p>edited while searching</p>',
                raw: 'edited while searching',
                edited: true,
                author: old.message.author,
              ),
              'delete' => old.message.withDeletedAt(DateTime.utc(2026, 10, 24)),
              'reaction' => old.message.withReactions(const [
                ChatReaction(emoji: 'heart', count: 1, reacted: true),
              ]),
              'pin' => old.message.withPinned(true),
              'remove' => null,
              _ => throw StateError(mutation),
            };
            if (updated == null) {
              store.remove<ChatMessage>(site, old.id);
            } else {
              store.put(site, updated);
            }
            final ref = store.ref<ChatMessage>(site, old.id);
            var changes = 0;
            ref.addListener(() => changes++);
            expect(store.read<ChatMessage>(site, 3), isNull);
            gate.complete();
            await drain();

            expectCanonicalMessage(
              store.read<ChatMessage>(site, old.id),
              updated,
            );
            expectCanonicalMessage(ref.value, updated);
            expect(changes, 0);
            final state = search.globalState(site);
            expect(state.phase, ChatSearchPhase.results);
            expect(
              state.hits.map((hit) => hit.id),
              heldOffset == 0 ? [2, 3] : [1, 2, 3],
            );
            expect(state.hits.last.message.cooked, '<p>message 3</p>');
            expect(state.hits.last.excerpt, 'message 3');
            expect(state.loadingMore, isFalse);
            expect(state.nextOffset, heldOffset + 2);
            if (heldOffset != 0) {
              search.loadMore(site);
              await drain();
              expect(
                api.chatSearchesRequested.map((request) => request.offset),
                [0, 2, 4],
              );
              expect(search.globalState(site).hits.map((hit) => hit.id), [
                1,
                2,
                3,
                4,
              ]);
              expect(search.globalState(site).hasMore, isFalse);
              expectCanonicalMessage(
                store.read<ChatMessage>(site, old.id),
                updated,
              );
            }
          },
        );
      }
    }

    for (final heldOffset in [0, 1]) {
      for (final retirement in ['invalidate', 'forget', 'dispose', 'clear']) {
        test('$retirement retires held search at offset $heldOffset', () async {
          final gate = Completer<void>();
          addTearDown(() {
            if (!gate.isCompleted) gate.complete();
          });
          final old = hit(2);
          final api = _HeldSearchApi(
            completion: gate,
            heldOffset: heldOffset,
            chatSearchPagesByKey: {
              FakeDiscourseApi.chatSearchKey('needle'): ChatSearchPage(
                hits: heldOffset == 0 ? [old, hit(3)] : [hit(1)],
                hasMore: heldOffset != 0,
              ),
              FakeDiscourseApi.chatSearchKey('needle', offset: 1):
                  ChatSearchPage(hits: [old, hit(3)]),
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
          store.put(site, old.message);
          final resultRef = search.globalRef(site);
          var publications = 0;
          resultRef.addListener(() => publications++);
          search.setGlobalQuery(site, 'needle');
          await drain();
          if (heldOffset != 0) {
            search.loadMore(site);
            await drain();
          }
          expect(api.chatSearchesRequested.last.offset, heldOffset);
          final updated = old.message.withPinned(true);
          store.put(site, updated);
          final messageRef = store.ref<ChatMessage>(site, 2);
          var messageChanges = 0;
          messageRef.addListener(() => messageChanges++);
          switch (retirement) {
            case 'invalidate':
              lifecycle.invalidate(site);
            case 'forget':
              search.forget(site);
            case 'dispose':
              search.dispose();
            case 'clear':
              search.setGlobalQuery(site, '');
          }
          final retiredState = search.globalState(site);
          publications = 0;
          gate.complete();
          await drain();

          expect(search.globalState(site), retiredState);
          expect(publications, 0);
          expect(messageChanges, 0);
          expectCanonicalMessage(store.read<ChatMessage>(site, 2), updated);
          expectCanonicalMessage(messageRef.value, updated);
          expect(store.read<ChatMessage>(site, 3), isNull);
          expect(
            search.globalState(site).hits.map((hit) => hit.id),
            retirement == 'invalidate' && heldOffset != 0 ? [1] : isEmpty,
          );
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
