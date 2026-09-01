import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/draft_list_controller.dart';
import 'package:flutter_test/flutter_test.dart';

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
  Future<List<UserDraft>> userDrafts({
    required String siteUrl,
    required String apiKey,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async {
    loads.add(siteUrl);
    return const [];
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
  final List<(String, String)> deletions = [];

  @override
  Future<List<UserDraft>> userDrafts({
    required String siteUrl,
    required String apiKey,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) {
    final page = Completer<List<UserDraft>>();
    pages.add(page);
    return page.future;
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
