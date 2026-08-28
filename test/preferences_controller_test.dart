import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/shell/preferences_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _siteUrl = 'https://one.example';
const _accountA = DiscourseInstance(
  url: _siteUrl,
  title: 'One',
  user: DiscourseUser(id: 10, username: 'alice'),
);
const _accountB = DiscourseInstance(
  url: _siteUrl,
  title: 'One',
  user: DiscourseUser(id: 20, username: 'bob'),
);
const _initial = UserPreferences(
  username: 'alice',
  timezone: 'Etc/UTC',
  likeNotificationFrequency: 1,
  notifyOnLinkedPosts: true,
  newTopicDurationMinutes: 2880,
  autoTrackTopicsAfterMsecs: 300000,
  notificationLevelWhenReplying: 2,
  canEdit: true,
  canChangeTrackingPreferences: true,
);

typedef _LoadCall = ({
  String siteUrl,
  String apiKey,
  String? clientId,
  String username,
});
typedef _UpdateCall = ({
  String siteUrl,
  String apiKey,
  String? clientId,
  String username,
  UserPreferences fallback,
  Map<String, Object?> values,
});

final class _PreferencesApi implements UserPreferencesApi {
  _PreferencesApi({this.onLoad, this.onUpdate});

  final Future<UserPreferences> Function(_LoadCall call)? onLoad;
  final Future<UserPreferences> Function(_UpdateCall call)? onUpdate;
  final List<_LoadCall> loads = [];
  final List<_UpdateCall> updates = [];
  int activeUpdates = 0;
  int maxActiveUpdates = 0;

  @override
  Future<UserPreferences> loadUserPreferences({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    final call = (
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      username: username,
    );
    loads.add(call);
    final handler = onLoad;
    return handler == null ? _initial : handler(call);
  }

  @override
  Future<UserPreferences> updateUserPreferences({
    required String siteUrl,
    required String apiKey,
    required String username,
    required UserPreferences fallback,
    required Map<String, Object?> values,
    String? clientId,
  }) async {
    final call = (
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      username: username,
      fallback: fallback,
      values: Map<String, Object?>.unmodifiable(values),
    );
    updates.add(call);
    activeUpdates++;
    if (activeUpdates > maxActiveUpdates) maxActiveUpdates = activeUpdates;
    try {
      final handler = onUpdate;
      return handler == null ? fallback : await handler(call);
    } finally {
      activeUpdates--;
    }
  }
}

final class _ReadyCredentials implements ApiCredentialReader {
  final List<String> sites = [];

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    sites.add(siteUrl);
    return 'api-key';
  }

  @override
  Future<String> clientId() async => 'test-client';
}

final class _SequencedCredentials implements ApiCredentialReader {
  _SequencedCredentials(this.results);

  final List<Future<String?>> results;
  final List<String> sites = [];

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    sites.add(siteUrl);
    return results[sites.length - 1];
  }

  @override
  Future<String> clientId() async => 'test-client';
}

PreferencesController _controller(
  UserPreferencesApi api, {
  ApiCredentialReader? credentials,
  SiteLifecycle? lifecycle,
  PreferencesSaved? onSaved,
}) => PreferencesController(
  api: api,
  credentials: credentials ?? _ReadyCredentials(),
  lifecycle: lifecycle ?? SiteLifecycle(),
  onSaved: onSaved,
);

Future<void> _seed(PreferencesController controller) async {
  await controller.load(_accountA);
  expect(controller.stateFor(_siteUrl)?.loaded, isTrue);
}

void main() {
  // Deliberately no TestWidgetsFlutterBinding.ensureInitialized(): this file
  // also pins that the controller remains usable by headless entry points.
  test('loads the connected account and saves a server-backed edit', () async {
    final saved = <UserPreferences>[];
    final api = _PreferencesApi();
    final credentials = _ReadyCredentials();
    final controller = _controller(
      api,
      credentials: credentials,
      onSaved: (_, _, preferences) => saved.add(preferences),
    );
    addTearDown(controller.dispose);

    await controller.load(_accountA);

    expect(api.loads, [
      (
        siteUrl: _siteUrl,
        apiKey: 'api-key',
        clientId: 'test-client',
        username: 'alice',
      ),
    ]);
    expect(controller.stateFor(_siteUrl)?.draft, _initial);

    controller.edit(
      _siteUrl,
      PreferenceSection.notifications,
      (current) => current.copyWith(notifyOnLinkedPosts: false),
    );

    expect(
      await controller.save(_accountA, PreferenceSection.notifications),
      isTrue,
    );
    final state = controller.stateFor(_siteUrl)!;
    expect(state.dirty(PreferenceSection.notifications), isFalse);
    expect(state.savedSection, PreferenceSection.notifications);
    expect(state.saving, isFalse);
    expect(saved.single.notifyOnLinkedPosts, isFalse);
    expect(credentials.sites, [_siteUrl, _siteUrl]);
  });

  test('forwards each supported section as one flat partial payload', () async {
    expect(PreferenceSection.values, [
      PreferenceSection.profile,
      PreferenceSection.notifications,
      PreferenceSection.tracking,
      PreferenceSection.interface,
    ]);

    final cases =
        <
          PreferenceSection,
          ({
            UserPreferences Function(UserPreferences) change,
            Map<String, Object?> payload,
          })
        >{
          PreferenceSection.profile: (
            change: (current) => current.copyWith(timezone: 'Europe/Paris'),
            payload: const {'timezone': 'Europe/Paris'},
          ),
          PreferenceSection.notifications: (
            change: (current) => current.copyWith(
              likeNotificationFrequency: 3,
              notifyOnLinkedPosts: false,
            ),
            payload: const {
              'like_notification_frequency': 3,
              'notify_on_linked_posts': false,
            },
          ),
          PreferenceSection.tracking: (
            change: (current) => current.copyWith(
              newTopicDurationMinutes: 10080,
              autoTrackTopicsAfterMsecs: 60000,
              notificationLevelWhenReplying: 3,
            ),
            payload: const {
              'new_topic_duration_minutes': 10080,
              'auto_track_topics_after_msecs': 60000,
              'notification_level_when_replying': 3,
            },
          ),
          PreferenceSection.interface: (
            change: (current) => current.copyWith(
              bookmarkAutoDeletePreference:
                  BookmarkAutoDeletePreference.onOwnerReply,
            ),
            payload: const {'bookmark_auto_delete_preference': 2},
          ),
        };

    for (final MapEntry(key: section, value: testCase) in cases.entries) {
      final api = _PreferencesApi();
      final controller = _controller(api);
      await _seed(controller);

      controller.edit(_siteUrl, section, testCase.change);
      expect(await controller.save(_accountA, section), isTrue);

      expect(api.updates.single.values, testCase.payload);
      expect(api.updates.single.values.keys, testCase.payload.keys);
      controller.dispose();
    }
  });

  test(
    'saving one section does not confirm or emit another unsaved edit',
    () async {
      final saved = <UserPreferences>[];
      final api = _PreferencesApi();
      final controller = _controller(
        api,
        onSaved: (_, _, preferences) => saved.add(preferences),
      );
      addTearDown(controller.dispose);
      await _seed(controller);

      controller.edit(
        _siteUrl,
        PreferenceSection.profile,
        (current) => current.copyWith(timezone: 'Europe/Paris'),
      );
      controller.edit(
        _siteUrl,
        PreferenceSection.notifications,
        (current) => current.copyWith(notifyOnLinkedPosts: false),
      );

      expect(
        await controller.save(_accountA, PreferenceSection.notifications),
        isTrue,
      );

      expect(api.updates.single.values, {'notify_on_linked_posts': false});
      final state = controller.stateFor(_siteUrl)!;
      expect(state.confirmed?.notifyOnLinkedPosts, isFalse);
      expect(state.confirmed?.timezone, 'Etc/UTC');
      expect(state.draft?.timezone, 'Europe/Paris');
      expect(state.dirty(PreferenceSection.notifications), isFalse);
      expect(state.dirty(PreferenceSection.profile), isTrue);
      expect(saved.single.timezone, 'Etc/UTC');
    },
  );

  test(
    'retains edits and the server validation error after a failed save',
    () async {
      final api = _PreferencesApi(
        onUpdate: (_) async => throw const WriteException(
          WriteFailure.validation,
          errors: ['The selected timezone is not available.'],
        ),
      );
      final controller = _controller(api);
      addTearDown(controller.dispose);
      await _seed(controller);

      controller.edit(
        _siteUrl,
        PreferenceSection.profile,
        (current) => current.copyWith(timezone: 'Mars/Olympus'),
      );

      expect(
        await controller.save(_accountA, PreferenceSection.profile),
        isFalse,
      );
      final state = controller.stateFor(_siteUrl)!;
      expect(state.draft?.timezone, 'Mars/Olympus');
      expect(state.confirmed?.timezone, 'Etc/UTC');
      expect(state.dirty(PreferenceSection.profile), isTrue);
      expect(state.error, 'The selected timezone is not available.');
      expect(state.saving, isFalse);
      expect(state.savedSection, isNull);
    },
  );

  test('serializes writes and supersedes an obsolete queued value', () async {
    final firstWrite = Completer<UserPreferences>();
    late final _PreferencesApi api;
    api = _PreferencesApi(
      onUpdate: (call) => api.updates.length == 1
          ? firstWrite.future
          : Future<UserPreferences>.value(call.fallback),
    );
    final controller = _controller(api);
    addTearDown(controller.dispose);
    await _seed(controller);

    controller.edit(
      _siteUrl,
      PreferenceSection.notifications,
      (current) => current.copyWith(likeNotificationFrequency: 2),
    );
    final firstSave = controller.save(
      _accountA,
      PreferenceSection.notifications,
    );
    await pumpEventQueue();
    expect(api.updates, hasLength(1));

    controller.edit(
      _siteUrl,
      PreferenceSection.notifications,
      (current) => current.copyWith(likeNotificationFrequency: 3),
    );
    final obsoleteSave = controller.save(
      _accountA,
      PreferenceSection.notifications,
    );
    controller.edit(
      _siteUrl,
      PreferenceSection.notifications,
      (current) => current.copyWith(likeNotificationFrequency: 0),
    );
    final latestSave = controller.save(
      _accountA,
      PreferenceSection.notifications,
    );
    await pumpEventQueue();

    expect(api.updates, hasLength(1));
    expect(controller.stateFor(_siteUrl)?.pendingWrites, 3);
    firstWrite.complete(_initial.copyWith(likeNotificationFrequency: 2));

    expect(await firstSave, isFalse);
    expect(await obsoleteSave, isFalse);
    expect(await latestSave, isTrue);
    expect(api.maxActiveUpdates, 1);
    expect(
      api.updates.map((call) => call.values['like_notification_frequency']),
      [2, 0],
    );
    final state = controller.stateFor(_siteUrl)!;
    expect(state.draft?.likeNotificationFrequency, 0);
    expect(state.confirmed?.likeNotificationFrequency, 0);
    expect(state.pendingWrites, 0);
  });

  test('a stale refresh cannot clobber a newer local edit', () async {
    final refresh = Completer<UserPreferences>();
    var loadCount = 0;
    final api = _PreferencesApi(
      onLoad: (_) {
        loadCount++;
        return loadCount == 1
            ? Future<UserPreferences>.value(_initial)
            : refresh.future;
      },
    );
    final controller = _controller(api);
    addTearDown(controller.dispose);
    await _seed(controller);

    final refreshTask = controller.load(_accountA, refresh: true);
    await pumpEventQueue();
    controller.edit(
      _siteUrl,
      PreferenceSection.profile,
      (current) => current.copyWith(timezone: 'Europe/Paris'),
    );
    refresh.complete(_initial.copyWith(timezone: 'America/New_York'));
    await refreshTask;

    final state = controller.stateFor(_siteUrl)!;
    expect(state.loading, isFalse);
    expect(state.draft?.timezone, 'Europe/Paris');
    expect(state.confirmed?.timezone, 'Etc/UTC');
    expect(state.dirty(PreferenceSection.profile), isTrue);
  });

  test('forget during a credential read dispatches no stale load', () async {
    final key = Completer<String?>();
    final api = _PreferencesApi();
    final credentials = _SequencedCredentials([key.future]);
    final controller = _controller(api, credentials: credentials);
    addTearDown(controller.dispose);

    final load = controller.load(_accountA);
    await pumpEventQueue();
    controller.forget(_siteUrl);
    key.complete('stale-key');
    await load;

    expect(api.loads, isEmpty);
    expect(controller.stateFor(_siteUrl), isNull);
  });

  test(
    'session invalidation and forget cancel a pending save credential read',
    () async {
      final saveKey = Completer<String?>();
      final credentials = _SequencedCredentials([
        Future<String?>.value('seed-key'),
        saveKey.future,
      ]);
      final api = _PreferencesApi();
      final lifecycle = SiteLifecycle();
      final controller = _controller(
        api,
        credentials: credentials,
        lifecycle: lifecycle,
      );
      addTearDown(controller.dispose);
      await _seed(controller);
      controller.edit(
        _siteUrl,
        PreferenceSection.notifications,
        (current) => current.copyWith(notifyOnLinkedPosts: false),
      );

      final save = controller.save(_accountA, PreferenceSection.notifications);
      await pumpEventQueue();
      lifecycle.invalidate(_siteUrl);
      controller.forget(_siteUrl);
      saveKey.complete('stale-key');

      expect(await save, isFalse);
      expect(api.updates, isEmpty);
      expect(controller.stateFor(_siteUrl), isNull);
    },
  );

  test(
    'a late response from another account cannot cross the account lane',
    () async {
      final accountA = Completer<UserPreferences>();
      final accountB = Completer<UserPreferences>();
      final api = _PreferencesApi(
        onLoad: (call) => switch (call.username) {
          'alice' => accountA.future,
          'bob' => accountB.future,
          _ => throw StateError('Unexpected account ${call.username}'),
        },
      );
      final controller = _controller(api);
      addTearDown(controller.dispose);

      final oldLoad = controller.load(_accountA);
      await pumpEventQueue();
      final newLoad = controller.load(_accountB);
      await pumpEventQueue();

      accountB.complete(
        _initial.copyWith(username: 'bob', timezone: 'Europe/Paris'),
      );
      await newLoad;
      accountA.complete(_initial.copyWith(timezone: 'America/New_York'));
      await oldLoad;

      expect(api.loads.map((call) => call.username), ['alice', 'bob']);
      final state = controller.stateFor(_siteUrl)!;
      expect(state.accountIdentity, 'id:20');
      expect(state.username, 'bob');
      expect(state.draft?.username, 'bob');
      expect(state.draft?.timezone, 'Europe/Paris');
    },
  );

  test('disposal during a credential read is safe without a binding', () async {
    final key = Completer<String?>();
    final api = _PreferencesApi();
    final controller = _controller(
      api,
      credentials: _SequencedCredentials([key.future]),
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    final load = controller.load(_accountA);
    await pumpEventQueue();
    expect(notifications, 1);

    controller.dispose();
    key.complete('stale-key');
    await load;

    expect(api.loads, isEmpty);
    expect(notifications, 1);
    expect(controller.stateFor(_siteUrl), isNull);
  });
}
