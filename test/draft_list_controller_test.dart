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

  test('forget while load credentials are pending sends no request', () async {
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

  test('a replacement load supersedes a pending credential lookup', () async {
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

  test(
    'forget while delete credentials are pending sends no request',
    () async {
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
    },
  );

  test('a replacement delete supersedes a pending credential lookup', () async {
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
    'account invalidation while delete credentials are pending sends nothing',
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

  test('dispose while load credentials are pending sends no request', () async {
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
}
