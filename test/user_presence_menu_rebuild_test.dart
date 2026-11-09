import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _meta = 'https://meta.discourse.org';
const _team = 'https://team.discourse.org';
const _visible = DiscourseUser(id: 7, username: 'reader', hidePresence: false);
const _hidden = DiscourseUser(id: 8, username: 'quiet', hidePresence: true);

final class _Rebuilds {
  int all = 0;
  int presenceMenu = 0;
  int profileCard = 0;
}

bool _insideProfileCard(Element element) {
  const card = ValueKey('user-profile-card');
  if (element.widget.key == card) return true;
  var inside = false;
  element.visitAncestorElements((ancestor) {
    inside = ancestor.widget.key == card;
    return !inside;
  });
  return inside;
}

Future<_Rebuilds> _rebuildsDuring(Future<void> Function() event) async {
  final rebuilds = _Rebuilds();
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    rebuilds.all++;
    if (element.widget is UserPresenceMenu) rebuilds.presenceMenu++;
    if (_insideProfileCard(element)) rebuilds.profileCard++;
  };
  try {
    await event();
  } finally {
    debugOnRebuildDirtyWidget = previous;
  }
  return rebuilds;
}

Future<ShellController> _pumpShell(
  WidgetTester tester,
  Size size, {
  DiscourseUser team = _visible,
}) async {
  await pumpShell(
    tester,
    size,
    instances: [
      instance('meta.discourse.org', title: 'Meta', user: _visible),
      instance('team.discourse.org', title: 'Team', user: team),
    ],
    authenticator: FakeAuthenticator()
      ..keys[_meta] = 'meta-key'
      ..keys[_team] = 'team-key',
    api: FakeDiscourseApi(
      user: _visible,
      feeds: {
        '/latest.json': [
          for (var id = 1; id <= 40; id++)
            Topic(id: id + 100, title: 'Topic $id', slug: 'topic-$id'),
        ],
      },
    )..accounts['team-key'] = team,
  );
  await tester.pumpAndSettle();
  return ShellScope.read(tester.element(primaryMainContent));
}

String? _presenceLabel(WidgetTester tester) => tester
    .widget<DButton>(
      find.byKey(const ValueKey('user-presence-menu'), skipOffstage: false),
    )
    .semanticLabel;

String _labelFor(String presence) => 'Status and notifications, $presence';

void main() {
  final surfaces = [
    (
      name: 'phone',
      size: phone,
      variant: const TargetPlatformVariant({TargetPlatform.iOS}),
    ),
    (
      name: 'mac',
      size: desktop,
      variant: const TargetPlatformVariant({TargetPlatform.macOS}),
    ),
  ];

  for (final surface in surfaces) {
    final name = surface.name;

    testWidgets('$name: a shell notification leaves the presence menu alone', (
      tester,
    ) async {
      final shell = await _pumpShell(tester, surface.size);
      final tracker = FakeSiteTracker.built.lastWhere(
        (tracker) => tracker.siteUrl == _meta,
      );

      final notification = await _rebuildsDuring(() async {
        shell.notifyPluginStateChanged();
        await tester.pump();
      });

      var facadeNotifications = 0;
      void countFacadeNotification() => facadeNotifications++;
      shell.addListener(countFacadeNotification);
      addTearDown(() => shell.removeListener(countFacadeNotification));
      final tracking = await _rebuildsDuring(() async {
        for (var message = 0; message < 10; message++) {
          tracker.deliverTopicTracking({
            'topic_id': 900 + message,
            'message_type': 'unread',
            'payload': {
              'highest_post_number': 50,
              'last_read_post_number': 1,
              'notification_level': 2,
              'category_id': 1,
            },
          });
          // The tracking write and its coalesced notification are both
          // asynchronous, so a single frame can run ahead of them.
          for (var frame = 0; frame < 3; frame++) {
            await tester.pump(const Duration(milliseconds: 1));
          }
        }
      });

      for (final (metric, value) in [
        ('one_notification_presence_menu', notification.presenceMenu),
        ('one_notification_profile_card', notification.profileCard),
        ('one_notification_elements', notification.all),
        ('ten_tracking_presence_menu', tracking.presenceMenu),
        ('ten_tracking_profile_card', tracking.profileCard),
        ('ten_tracking_elements', tracking.all),
        ('ten_tracking_facade_notifications', facadeNotifications),
      ]) {
        debugPrint('PERF_PROOF presence-menu ${name}_$metric=$value');
      }
      expect(notification.presenceMenu, 0);
      expect(notification.profileCard, 0);
      expect(tracking.presenceMenu, 0);
      expect(tracking.profileCard, 0);
      expect(tester.takeException(), isNull);
    }, variant: surface.variant);

    testWidgets('$name: the label follows the presence setting', (
      tester,
    ) async {
      final shell = await _pumpShell(tester, surface.size);
      expect(_presenceLabel(tester), _labelFor('Online'));

      await shell.toggleHidePresence(_meta);
      await tester.pumpAndSettle();
      expect(_presenceLabel(tester), _labelFor('Offline'));

      await shell.toggleHidePresence(_meta);
      await tester.pumpAndSettle();
      expect(_presenceLabel(tester), _labelFor('Online'));
      expect(tester.takeException(), isNull);
    }, variant: surface.variant);

    testWidgets('$name: the label follows the selected account', (
      tester,
    ) async {
      final shell = await _pumpShell(tester, surface.size, team: _hidden);
      expect(_presenceLabel(tester), _labelFor('Online'));

      shell.selectInstance(1);
      await tester.pumpAndSettle();
      expect(_presenceLabel(tester), _labelFor('Offline'));

      shell.selectInstance(0);
      await tester.pumpAndSettle();
      expect(_presenceLabel(tester), _labelFor('Online'));
      expect(tester.takeException(), isNull);
    }, variant: surface.variant);
  }
}
