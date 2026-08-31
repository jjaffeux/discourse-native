import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const siteUrl = 'https://meta.discourse.org';

  test('reads the core status contract and its message bus cursor', () {
    final status = UserStatus.fromJson(const {
      'description': 'Working remotely',
      'emoji': 'house',
      'ends_at': '2030-02-03T12:30:00.000Z',
      'message_bus_last_id': 91,
    });

    expect(status?.description, 'Working remotely');
    expect(status?.emoji, 'house');
    expect(status?.endsAt, DateTime.utc(2030, 2, 3, 12, 30));
    expect(status?.messageBusLastId, 91);
    expect(status?.isActiveAt(DateTime.utc(2030, 2, 3, 12)), isTrue);
    expect(status?.isActiveAt(DateTime.utc(2030, 2, 3, 13)), isFalse);
    expect(
      UserStatus.fromJson(const {'description': '', 'emoji': 'house'}),
      isNull,
    );
  });

  test('retains status and DND state in connected-account persistence', () {
    final user = DiscourseUser(
      id: 7,
      username: 'sam',
      status: const UserStatus(
        description: 'Heads down',
        emoji: 'technologist',
        messageBusLastId: 17,
      ),
      doNotDisturbUntil: DateTime.utc(2030, 2, 3, 12, 30),
      doNotDisturbChannelPosition: 23,
    );

    final restored = DiscourseUser.fromJson(user.toJson());

    expect(restored, user);
    expect(restored.hashCode, user.hashCode);
  });

  test('reads status from every basic-user shape used by native surfaces', () {
    const json = {
      'id': 8,
      'username': 'jane',
      'name': 'Jane',
      'avatar_template': '/user_avatar/meta/jane/{size}/1.png',
      'status': {'description': 'On holiday', 'emoji': 'beach_umbrella'},
    };

    expect(FoundUser.fromJson(json, siteUrl).status?.description, 'On holiday');
    expect(UserCard.fromJson(json, siteUrl).status?.emoji, 'beach_umbrella');
    expect(ChatUser.fromJson(json, siteUrl).status?.description, 'On holiday');
    expect(
      ChatMessageAuthor.fromJson(json, siteUrl).status?.emoji,
      'beach_umbrella',
    );
  });

  test('keeps user IDs with cooked mention statuses for live updates', () {
    final statuses = userStatusesByUsername(const [
      {
        'id': 42,
        'username': 'SomeOne',
        'status': {'description': 'Lunch', 'emoji': 'sandwich'},
      },
      {'id': 43, 'username': 'without-status'},
    ]);

    expect(statuses.keys, ['someone']);
    expect(statuses['someone']?.userId, 42);
    expect(statuses['someone']?.status.description, 'Lunch');
  });

  test('honors the enable_user_status client setting', () {
    expect(
      SiteConfig.fromSettings(const {
        'enable_user_status': true,
      }).userStatusEnabled,
      isTrue,
    );
    expect(SiteConfig.fromSettings(const {}).userStatusEnabled, isFalse);
    expect(
      SiteConfig.fromJson(
        SiteConfig.fromSettings(const {'enable_user_status': true}).toJson(),
      ).userStatusEnabled,
      isTrue,
    );
  });

  test('folds live status updates over every serialized snapshot', () async {
    const initial = UserStatus(
      description: 'In a meeting',
      emoji: 'spiral_calendar',
      messageBusLastId: 77,
    );
    const user = DiscourseUser(
      id: 7,
      username: 'reader',
      status: initial,
      doNotDisturbChannelPosition: 88,
    );
    final authenticator = FakeAuthenticator()..keys[siteUrl] = 'key';
    final statusEndsAt = DateTime.now().add(const Duration(hours: 2));
    final api = FakeDiscourseApi(
      user: user,
      doNotDisturbUntil: statusEndsAt,
      feeds: const {'/latest.json': <Topic>[]},
      siteConfigs: const {siteUrl: SiteConfig(userStatusEnabled: true)},
    );
    final instanceStore = FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: user, config: const SiteConfig(userStatusEnabled: true)),
    ]);
    final shell = ShellController(
      plugins: installedPlugins,
      instanceStore: instanceStore,
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);

    await shell.load();
    await pumpEventQueue();
    final tracker = FakeSiteTracker.built.single;

    expect(tracker.pluginChannelLastIds['/user-status'], 77);
    expect(tracker.pluginChannelLastIds['/do-not-disturb/7'], 88);
    final savesBeforeLiveStatus = instanceStore.saveCount;
    tracker.deliverPluginMessage('/user-status', const {
      '42': {'description': 'At lunch', 'emoji': 'sandwich'},
      '7': {'description': 'Available', 'emoji': 'green_circle'},
    });

    expect(
      shell
          .userStatusFor(
            siteUrl,
            42,
            const UserStatus(description: 'Old', emoji: 'clock1'),
          )
          ?.description,
      'At lunch',
    );
    expect(shell.currentInstance?.user?.status?.description, 'Available');
    expect(instanceStore.saveCount, greaterThan(savesBeforeLiveStatus));

    tracker.deliverPluginMessage('/user-status', const {'42': null});
    expect(
      shell.userStatusFor(
        siteUrl,
        42,
        const UserStatus(description: 'Old', emoji: 'clock1'),
      ),
      isNull,
    );

    tracker.deliverPluginMessage('/do-not-disturb/7', const {
      'ends_at': 'Wed, 28 Aug 2030 12:00:00 GMT',
    });
    expect(
      shell.doNotDisturb.stateFor(siteUrl).until,
      DateTime.utc(2030, 8, 28, 12),
    );
    expect(
      shell.currentInstance?.user?.doNotDisturbUntil,
      DateTime.utc(2030, 8, 28, 12),
    );

    expect(
      await shell.setUserStatus(
        siteUrl,
        description: 'Pairing',
        emoji: 'busts_in_silhouette',
        endsAt: statusEndsAt,
        pauseNotifications: true,
      ),
      isNull,
    );
    expect(api.userStatusesSet.single.description, 'Pairing');
    expect(
      api.doNotDisturbDurations.single.minutes,
      inInclusiveRange(119, 120),
    );
    expect(
      shell.currentInstance?.user?.doNotDisturbUntil,
      statusEndsAt.toUtc(),
    );
    expect(shell.currentInstance?.user?.status?.description, 'Pairing');

    expect(await shell.clearUserStatus(siteUrl), isNull);
    expect(api.userStatusesCleared, [siteUrl]);
    expect(api.doNotDisturbResumes, [siteUrl]);
    expect(shell.currentInstance?.user?.status, isNull);
  });
}
