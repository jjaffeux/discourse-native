import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/draft_list_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _siteUrl = 'https://one.example';
const _instance = DiscourseInstance(
  url: _siteUrl,
  title: 'One',
  user: DiscourseUser(username: 'reader'),
);
const _draft = UserDraft(key: 'new_topic', sequence: 4, data: null);

final class _RecordingDraftsApi implements DraftsApi {
  final List<String> loads = [];
  final List<(String, String)> deletions = [];

  @override
  Future<UserDraftPage> userDrafts({
    required String siteUrl,
    required String apiKey,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async {
    loads.add(siteUrl);
    return const UserDraftPage(drafts: [], rawItemCount: 0);
  }

  @override
  Future<void> deleteUserDraft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    required int sequence,
    String? clientId,
  }) async {
    deletions.add((siteUrl, draftKey));
  }
}

final class _GatedDraftsApi implements DraftsApi {
  final List<Completer<List<UserDraft>>> pages = [];
  final List<int> offsets = [];
  final List<(String, String)> deletions = [];

  @override
  Future<UserDraftPage> userDrafts({
    required String siteUrl,
    required String apiKey,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async {
    final page = Completer<List<UserDraft>>();
    pages.add(page);
    offsets.add(offset);
    final drafts = await page.future;
    return UserDraftPage(drafts: drafts, rawItemCount: drafts.length);
  }

  @override
  Future<void> deleteUserDraft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    required int sequence,
    String? clientId,
  }) async {
    deletions.add((siteUrl, draftKey));
  }
}

final class _ReadyApiKeys implements SiteApiKeyReader {
  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'api-key';
}

final class _GatedApiKeys implements SiteApiKeyReader {
  _GatedApiKeys([List<Completer<String?>>? results])
    : results = results ?? [Completer<String?>()];

  final List<Completer<String?>> results;
  final List<String> sites = [];

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    sites.add(siteUrl);
    return results[sites.length - 1].future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('server page boundaries', () {
    test('invalid raw rows do not hide subsequent valid drafts', () async {
      final offsets = <int>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          final offset = int.parse(request.url.queryParameters['offset']!);
          offsets.add(offset);
          return http.Response(
            jsonEncode({
              'drafts': offset == 0
                  ? [
                      null,
                      false,
                      'not a draft',
                      <String, Object?>{},
                      {'draft_key': ''},
                      for (var index = 5; index < 30; index++)
                        {'draft_key': 'topic_$index', 'sequence': 1},
                    ]
                  : [
                      {'draft_key': 'topic_30', 'sequence': 1},
                    ],
            }),
            200,
          );
        }),
      );
      final controller = DraftListController(
        api: api,
        credentials: _ReadyApiKeys(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);

      await controller.load(_instance);

      expect(controller.feedFor(_siteUrl).drafts.map((draft) => draft.key), [
        for (var index = 5; index < 30; index++) 'topic_$index',
      ]);
      expect(controller.feedFor(_siteUrl).hasMore, isTrue);
      expect(controller.feedFor(_siteUrl).nextOffset, 30);

      await controller.load(_instance);
      expect(offsets, [0, 30]);
      expect(controller.feedFor(_siteUrl).drafts.last.key, 'topic_30');
      expect(controller.feedFor(_siteUrl).hasMore, isFalse);
      await controller.load(_instance);
      expect(offsets, [0, 30]);
    });

    test('an entirely invalid full page keeps load more available', () async {
      final offsets = <int>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          final offset = int.parse(request.url.queryParameters['offset']!);
          offsets.add(offset);
          return http.Response(
            jsonEncode({
              'drafts': offset == 0
                  ? List<Object?>.filled(30, null)
                  : [
                      {'draft_key': 'topic_30', 'sequence': 1},
                    ],
            }),
            200,
          );
        }),
      );
      final controller = DraftListController(
        api: api,
        credentials: _ReadyApiKeys(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);

      await controller.load(_instance);

      final feed = controller.feedFor(_siteUrl);
      expect(feed.drafts, isEmpty);
      expect(
        feed.isEmpty,
        isFalse,
        reason: 'the view must still offer Load more',
      );
      expect(feed.hasMore, isTrue);
      await controller.load(_instance);
      expect(offsets, [0, 30]);
      expect(controller.feedFor(_siteUrl).drafts.single.key, 'topic_30');
      expect(controller.feedFor(_siteUrl).hasMore, isFalse);
    });

    test(
      'overlap consumes rows and preserves the latest usable draft',
      () async {
        final offsets = <int>[];
        final api = DiscourseApi(
          client: MockClient((request) async {
            final offset = int.parse(request.url.queryParameters['offset']!);
            offsets.add(offset);
            return http.Response(
              jsonEncode({
                'drafts': switch (offset) {
                  0 => [
                    for (var index = 0; index < 30; index++)
                      {
                        'draft_key': 'topic_$index',
                        'sequence': 4,
                        'data': {'reply': 'Saved draft $index'},
                      },
                  ],
                  30 => [
                    {
                      'draft_key': 'topic_0',
                      'sequence': 3,
                      'data': {'reply': 'Stale text'},
                    },
                    {'draft_key': 'topic_1', 'sequence': 4},
                    {
                      'draft_key': 'topic_2',
                      'sequence': 5,
                      'data': {'reply': 'Latest text'},
                    },
                    for (var index = 30; index < 57; index++)
                      {'draft_key': 'topic_$index', 'sequence': 1},
                  ],
                  _ => [
                    {'draft_key': 'topic_57', 'sequence': 1},
                  ],
                },
              }),
              200,
            );
          }),
        );
        final controller = DraftListController(
          api: api,
          credentials: _ReadyApiKeys(),
          lifecycle: SiteLifecycle(),
        );
        addTearDown(controller.dispose);

        await controller.load(_instance);
        await controller.load(_instance);
        final feed = controller.feedFor(_siteUrl);
        expect(feed.drafts, hasLength(57));
        expect(feed.drafts[0].sequence, 4);
        expect(feed.drafts[0].data?.reply, 'Saved draft 0');
        expect(feed.drafts[1].data?.reply, 'Saved draft 1');
        expect(feed.drafts[2].sequence, 5);
        expect(feed.drafts[2].data?.reply, 'Latest text');

        await controller.load(_instance);
        expect(offsets, [0, 30, 60]);
        expect(controller.feedFor(_siteUrl).drafts, hasLength(58));
        expect(controller.feedFor(_siteUrl).hasMore, isFalse);
      },
    );

    test(
      'an empty response stops further requests at the same offset',
      () async {
        final api = _GatedDraftsApi();
        final controller = DraftListController(
          api: api,
          credentials: _ReadyApiKeys(),
          lifecycle: SiteLifecycle(),
        );
        addTearDown(controller.dispose);

        final load = controller.load(_instance);
        await pumpEventQueue();
        api.pages.single.complete(const []);
        await load;
        await controller.load(_instance);

        expect(api.offsets, [0]);
        expect(controller.feedFor(_siteUrl).hasMore, isFalse);
        expect(controller.feedFor(_siteUrl).nextOffset, 0);
      },
    );
  });

  group('load credential invalidation', () {
    test('sends no request after forget during credential lookup', () async {
      final api = _RecordingDraftsApi();
      final credentials = _GatedApiKeys();
      final controller = DraftListController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);

      final load = controller.load(_instance);
      await pumpEventQueue();
      controller.forget(_siteUrl);
      credentials.results.single.complete('stale-key');
      await load;

      expect(api.loads, isEmpty);
    });

    test('lets a replacement load supersede pending credentials', () async {
      final oldKey = Completer<String?>();
      final replacementKey = Completer<String?>();
      final api = _RecordingDraftsApi();
      final credentials = _GatedApiKeys([oldKey, replacementKey]);
      final controller = DraftListController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);

      final oldLoad = controller.load(_instance);
      await pumpEventQueue();
      controller.forget(_siteUrl);
      final replacementLoad = controller.load(_instance);
      await pumpEventQueue();
      replacementKey.complete('replacement-key');
      await replacementLoad;

      oldKey.complete('stale-key');
      await oldLoad;

      expect(api.loads, [_siteUrl]);
    });
  });

  group('delete credential invalidation', () {
    test('sends no request after forget during credential lookup', () async {
      final api = _RecordingDraftsApi();
      final credentials = _GatedApiKeys();
      final controller = DraftListController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);

      final deletion = controller.delete(_instance, _draft);
      await pumpEventQueue();
      expect(controller.deleting(_siteUrl, _draft.key), isTrue);

      controller.forget(_siteUrl);
      credentials.results.single.complete('stale-key');

      expect(await deletion, isFalse);
      expect(api.deletions, isEmpty);
      expect(controller.deleting(_siteUrl, _draft.key), isFalse);
    });

    test('lets a replacement delete supersede pending credentials', () async {
      final oldKey = Completer<String?>();
      final replacementKey = Completer<String?>();
      final api = _RecordingDraftsApi();
      final credentials = _GatedApiKeys([oldKey, replacementKey]);
      final controller = DraftListController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);

      final oldDeletion = controller.delete(_instance, _draft);
      await pumpEventQueue();
      controller.forget(_siteUrl);
      final replacementDeletion = controller.delete(_instance, _draft);
      await pumpEventQueue();

      replacementKey.complete('replacement-key');
      expect(await replacementDeletion, isTrue);

      oldKey.complete('stale-key');
      expect(await oldDeletion, isFalse);
      expect(api.deletions, [(_siteUrl, _draft.key)]);
    });

    test(
      'sends nothing after account invalidation during credential lookup',
      () async {
        final api = _RecordingDraftsApi();
        final credentials = _GatedApiKeys();
        final lifecycle = SiteLifecycle();
        final controller = DraftListController(
          api: api,
          credentials: credentials,
          lifecycle: lifecycle,
        );
        addTearDown(controller.dispose);

        final deletion = controller.delete(_instance, _draft);
        await pumpEventQueue();
        lifecycle.invalidate(_siteUrl);
        credentials.results.single.complete('stale-key');

        expect(await deletion, isFalse);
        expect(api.deletions, isEmpty);
        expect(controller.deleting(_siteUrl, _draft.key), isFalse);
      },
    );
  });

  group('stale page reconciliation', () {
    test(
      'invalid rows and actual deletions adjust offsets separately',
      () async {
        final responses = <Completer<http.Response>>[];
        final offsets = <int>[];
        final api = DiscourseApi(
          client: MockClient((request) {
            offsets.add(int.parse(request.url.queryParameters['offset']!));
            final response = Completer<http.Response>();
            responses.add(response);
            return response.future;
          }),
        );
        final controller = DraftListController(
          api: api,
          credentials: _ReadyApiKeys(),
          lifecycle: SiteLifecycle(),
        );
        addTearDown(controller.dispose);

        final load = controller.load(_instance);
        await pumpEventQueue();
        controller.recordDeleted(_siteUrl, 'topic_3', knownToExist: true);
        responses.single.complete(
          http.Response(
            jsonEncode({
              'drafts': [
                null,
                for (var index = 1; index < 30; index++)
                  {'draft_key': 'topic_$index', 'sequence': 1},
              ],
            }),
            200,
          ),
        );
        await load;

        final feed = controller.feedFor(_siteUrl);
        expect(feed.drafts, hasLength(28));
        expect(
          feed.drafts.map((draft) => draft.key),
          isNot(contains('topic_3')),
        );
        expect(feed.nextOffset, 29);
        expect(feed.hasMore, isTrue);

        final more = controller.load(_instance);
        await pumpEventQueue();
        expect(offsets, [0, 29]);
        responses[1].complete(
          http.Response(
            jsonEncode({
              'drafts': [
                {'draft_key': 'topic_30', 'sequence': 1},
              ],
            }),
            200,
          ),
        );
        await more;
        expect(controller.feedFor(_siteUrl).drafts.last.key, 'topic_30');
        expect(controller.feedFor(_siteUrl).hasMore, isFalse);
      },
    );

    test('overlapping deleted rows shift the cursor only once', () async {
      final api = _GatedDraftsApi();
      final controller = DraftListController(
        api: api,
        credentials: _ReadyApiKeys(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);
      final seeded = [
        for (var index = 0; index < 30; index++)
          UserDraft(key: 'topic_$index', sequence: 1, data: null),
      ];
      final seed = controller.load(_instance);
      await pumpEventQueue();
      api.pages.single.complete(seeded);
      await seed;

      final more = controller.load(_instance);
      await pumpEventQueue();
      expect(await controller.delete(_instance, seeded[3]), isTrue);
      controller.recordDeleted(_siteUrl, 'topic_32', knownToExist: true);
      api.pages[1].complete([
        seeded[3],
        for (var index = 31; index < 60; index++)
          UserDraft(key: 'topic_$index', sequence: 1, data: null),
      ]);
      await more;

      final feed = controller.feedFor(_siteUrl);
      expect(feed.drafts.map((draft) => draft.key), isNot(contains('topic_3')));
      expect(
        feed.drafts.map((draft) => draft.key),
        isNot(contains('topic_32')),
      );
      expect(feed.nextOffset, 58);
      expect(feed.hasMore, isTrue);

      final last = controller.load(_instance);
      await pumpEventQueue();
      expect(api.offsets, [0, 30, 58]);
      api.pages[2].complete(const []);
      await last;
    });

    test('deletions during credentials affect the requested offset', () async {
      final api = _GatedDraftsApi();
      final keys = _GatedApiKeys([Completer<String?>(), Completer<String?>()]);
      final controller = DraftListController(
        api: api,
        credentials: keys,
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);
      final seeded = [
        for (var index = 0; index < 30; index++)
          UserDraft(key: 'topic_$index', sequence: 1, data: null),
      ];
      final seed = controller.load(_instance);
      keys.results[0].complete('key');
      await pumpEventQueue();
      api.pages.single.complete(seeded);
      await seed;

      final more = controller.load(_instance);
      await pumpEventQueue();
      controller.recordDeleted(_siteUrl, seeded[3].key, knownToExist: true);
      keys.results[1].complete('key');
      await pumpEventQueue();

      expect(api.offsets, [0, 29]);
      api.pages[1].complete(const []);
      await more;
      expect(controller.feedFor(_siteUrl).nextOffset, 29);
    });

    test(
      'deleting an entire captured page stops a nonadvancing load',
      () async {
        final api = _GatedDraftsApi();
        final controller = DraftListController(
          api: api,
          credentials: _ReadyApiKeys(),
          lifecycle: SiteLifecycle(),
        );
        addTearDown(controller.dispose);
        final page = [
          for (var index = 0; index < 30; index++)
            UserDraft(key: 'topic_$index', sequence: 1, data: null),
        ];
        final load = controller.load(_instance);
        await pumpEventQueue();
        for (final draft in page) {
          controller.recordDeleted(_siteUrl, draft.key, knownToExist: true);
        }
        api.pages.single.complete(page);
        await load;
        await controller.load(_instance);

        expect(api.offsets, [0]);
        expect(controller.feedFor(_siteUrl).nextOffset, 0);
        expect(controller.feedFor(_siteUrl).hasMore, isFalse);
        expect(controller.feedFor(_siteUrl).isEmpty, isTrue);
      },
    );

    test(
      'a concurrent deletion preserves loading and a full page cursor',
      () async {
        final api = _GatedDraftsApi();
        final controller = DraftListController(
          api: api,
          credentials: _ReadyApiKeys(),
          lifecycle: SiteLifecycle(),
        );
        addTearDown(controller.dispose);
        final page = [
          for (var index = 0; index < DraftListController.pageSize; index++)
            UserDraft(key: 'topic_$index', sequence: 1, data: null),
        ];
        final load = controller.load(_instance);
        await pumpEventQueue();
        controller.recordDeleted(_siteUrl, page[3].key, knownToExist: true);
        expect(controller.feedFor(_siteUrl).loading, isTrue);

        api.pages.single.complete(page);
        await load;
        final feed = controller.feedFor(_siteUrl);
        expect(feed.loading, isFalse);
        expect(feed.drafts, hasLength(29));
        expect(feed.hasMore, isTrue);
        expect(
          feed.drafts.map((draft) => draft.key),
          isNot(contains('topic_3')),
        );

        final more = controller.load(_instance);
        await pumpEventQueue();
        expect(api.offsets, [0, 29]);
        api.pages[1].complete(const [
          UserDraft(key: 'topic_30', sequence: 1, data: null),
        ]);
        await more;
        expect(controller.feedFor(_siteUrl).drafts, hasLength(30));
        expect(controller.feedFor(_siteUrl).hasMore, isFalse);
      },
    );

    test(
      'a queued refresh expires with the account that requested it',
      () async {
        final api = _GatedDraftsApi();
        final lifecycle = SiteLifecycle();
        final controller = DraftListController(
          api: api,
          credentials: _ReadyApiKeys(),
          lifecycle: lifecycle,
        );
        addTearDown(controller.dispose);
        final initial = controller.load(_instance);
        await pumpEventQueue();
        await controller.load(_instance, refresh: true);
        lifecycle.invalidate(_siteUrl);

        api.pages.single.complete(const [_draft]);
        await initial;
        await pumpEventQueue();
        expect(api.pages, hasLength(1));

        final refresh = controller.load(_instance, refresh: true);
        await pumpEventQueue();
        api.pages[1].complete(const []);
        await refresh;
        expect(controller.feedFor(_siteUrl).loading, isFalse);
        expect(controller.feedFor(_siteUrl).loaded, isTrue);
      },
    );

    test('a current account refresh can follow an expired page', () async {
      final api = _GatedDraftsApi();
      final lifecycle = SiteLifecycle();
      final controller = DraftListController(
        api: api,
        credentials: _ReadyApiKeys(),
        lifecycle: lifecycle,
      );
      addTearDown(controller.dispose);
      final initial = controller.load(_instance);
      await pumpEventQueue();
      lifecycle.invalidate(_siteUrl);
      await controller.load(_instance, refresh: true);

      api.pages.single.complete(const [_draft]);
      await initial;
      await pumpEventQueue();
      expect(api.pages, hasLength(2));
      expect(controller.feedFor(_siteUrl).drafts, isEmpty);
      api.pages[1].complete(const []);
      await pumpEventQueue();
      expect(controller.feedFor(_siteUrl).loaded, isTrue);
      expect(controller.feedFor(_siteUrl).loading, isFalse);
    });

    test('queues a live refresh received while a page is in flight', () async {
      final api = _GatedDraftsApi();
      final controller = DraftListController(
        api: api,
        credentials: _ReadyApiKeys(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);

      final initial = controller.load(_instance);
      await pumpEventQueue();
      await controller.load(_instance, refresh: true);

      api.pages.single.complete(const [_draft]);
      await initial;
      await pumpEventQueue();
      expect(api.pages, hasLength(2));

      api.pages[1].complete(const []);
      await pumpEventQueue();

      expect(controller.feedFor(_siteUrl).drafts, isEmpty);
    });

    test('keeps a draft deleted while a page is in flight', () async {
      final api = _GatedDraftsApi();
      final controller = DraftListController(
        api: api,
        credentials: _ReadyApiKeys(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);

      final seed = controller.load(_instance);
      await pumpEventQueue();
      api.pages.single.complete(const [_draft]);
      await seed;
      expect(controller.feedFor(_siteUrl).drafts.single.key, _draft.key);

      final refresh = controller.load(_instance, refresh: true);
      await pumpEventQueue();
      expect(await controller.delete(_instance, _draft), isTrue);

      // The refresh response was produced before the server-side delete landed.
      api.pages[1].complete(const [_draft]);
      await refresh;

      expect(api.deletions, [(_siteUrl, _draft.key)]);
      expect(controller.feedFor(_siteUrl).drafts, isEmpty);
    });

    test('keeps a concurrent deletion after a failed page', () async {
      final api = _GatedDraftsApi();
      final controller = DraftListController(
        api: api,
        credentials: _ReadyApiKeys(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);

      final seeded = [
        for (var index = 0; index < DraftListController.pageSize; index++)
          UserDraft(key: 'topic_$index', sequence: 1, data: null),
      ];
      final seed = controller.load(_instance);
      await pumpEventQueue();
      api.pages.single.complete(seeded);
      await seed;
      expect(controller.feedFor(_siteUrl).hasMore, isTrue);

      final more = controller.load(_instance);
      await pumpEventQueue();
      expect(await controller.delete(_instance, seeded[3]), isTrue);

      api.pages[1].completeError(StateError('offline'));
      await more;

      final feed = controller.feedFor(_siteUrl);
      expect(feed.error, "Couldn't load more drafts from one.example.");
      expect(
        feed.drafts.map((draft) => draft.key),
        isNot(contains(seeded[3].key)),
      );
      expect(feed.nextOffset, 29);
      controller.invalidateTotalCount(_siteUrl);

      final retry = controller.load(_instance);
      await pumpEventQueue();
      expect(api.offsets, [0, 30, 29]);
      api.pages[2].complete(const [
        UserDraft(key: 'topic_30', sequence: 1, data: null),
      ]);
      await retry;
      expect(controller.feedFor(_siteUrl).error, isNull);
      expect(controller.feedFor(_siteUrl).nextOffset, 30);
    });
  });

  group('disposal boundary enforcement', () {
    test('sends no request when disposed during load credentials', () async {
      final api = _RecordingDraftsApi();
      final credentials = _GatedApiKeys();
      final controller = DraftListController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
      );

      final load = controller.load(_instance);
      await pumpEventQueue();
      controller.dispose();
      credentials.results.single.complete('stale-key');
      await load;

      expect(api.loads, isEmpty);
    });

    for (final operation
        in <
          ({
            String name,
            Future<void> Function(DraftListController controller) begin,
          })
        >[
          (name: 'load', begin: (controller) => controller.load(_instance)),
          (
            name: 'delete',
            begin: (controller) async {
              await controller.delete(_instance, _draft);
            },
          ),
        ]) {
      test(
        'prevents ${operation.name} credentials after reentrant disposal',
        () async {
          final api = _RecordingDraftsApi();
          final credentials = _GatedApiKeys();
          final controller = DraftListController(
            api: api,
            credentials: credentials,
            lifecycle: SiteLifecycle(),
          );
          controller.addListener(controller.dispose);

          await operation.begin(controller);

          expect(credentials.sites, isEmpty);
          expect(api.loads, isEmpty);
          expect(api.deletions, isEmpty);
        },
      );
    }
  });
}
