import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_avatar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';
const _presenceChannel = '/presence/chat/online';
const _firstTickId = 48;
const _reader = DiscourseUser(id: 1, username: 'reader');

void main() {
  testWidgets(
    'presence ticks for users not on screen wake no frame and rebuild no avatar',
    (tester) async {
      final tracker = await _pumpAvatars(tester, userIds: const [2, 2, 3]);
      final rebuilds = _RebuildLog()..attach(addTearDown);
      expect(tester.binding.hasScheduledFrame, isFalse);

      var framesScheduled = 0;
      for (var i = 0; i < 10; i++) {
        tracker.deliverPluginMessage(
          _presenceChannel,
          i.isEven
              ? {
                  'entering_users': [
                    {'id': 100 + i, 'username': 'offscreen$i'},
                  ],
                }
              : {
                  'leaving_user_ids': [100 + i - 1],
                },
          messageId: _firstTickId + i,
        );
        if (tester.binding.hasScheduledFrame) framesScheduled++;
        await tester.pump();
      }

      debugPrint('PERF_PROOF chat-presence frames_scheduled=$framesScheduled');
      debugPrint(
        'PERF_PROOF chat-presence avatar_rebuilds=${rebuilds.users.length}',
      );
      debugPrint(
        'PERF_PROOF chat-presence element_rebuilds=${rebuilds.elements}',
      );
      expect(framesScheduled, 0);
      expect(rebuilds.users, isEmpty);
      expect(rebuilds.elements, 0);
    },
  );

  testWidgets(
    'a presence tick rebuilds every avatar of its user and no other, and '
    'moves the ring',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final tracker = await _pumpAvatars(tester, userIds: const [2, 2, 3]);
      final rebuilds = _RebuildLog()..attach(addTearDown);
      final ringOfTwo = find.byKey(ChatUserAvatar.onlineRingKey(2));
      final ringOfThree = find.byKey(ChatUserAvatar.onlineRingKey(3));
      final onlineLabel = find.bySemanticsLabel(appL10n.online);
      expect(ringOfTwo, findsNWidgets(2));
      expect(ringOfThree, findsNothing);
      expect(onlineLabel, findsNWidgets(2));

      tracker.deliverPluginMessage(_presenceChannel, {
        'leaving_user_ids': [2],
      }, messageId: _firstTickId);
      await tester.pump();

      expect(rebuilds.users, [2, 2]);
      expect(ringOfTwo, findsNothing);
      expect(onlineLabel, findsNothing);

      rebuilds.users.clear();
      tracker.deliverPluginMessage(_presenceChannel, {
        'entering_users': [
          {'id': 3, 'username': 'third'},
        ],
      }, messageId: _firstTickId + 1);
      await tester.pump();

      expect(rebuilds.users, [3]);
      expect(ringOfTwo, findsNothing);
      expect(ringOfThree, findsOneWidget);
      expect(onlineLabel, findsOneWidget);

      rebuilds.users.clear();
      tracker.deliverPluginMessage(_presenceChannel, {
        'entering_users': [
          {'id': 2, 'username': 'second'},
        ],
      }, messageId: _firstTickId + 2);
      await tester.pump();

      expect(rebuilds.users, [2, 2]);
      expect(ringOfTwo, findsNWidgets(2));
      expect(ringOfThree, findsOneWidget);
      expect(onlineLabel, findsNWidgets(3));
      semantics.dispose();
    },
  );

  testWidgets('an avatar reused for another user follows that user', (
    tester,
  ) async {
    final tracker = await _pumpAvatars(tester, userIds: const [2]);
    final controller = _harnessOf(tester);
    final ringOfTwo = find.byKey(ChatUserAvatar.onlineRingKey(2));
    final ringOfThree = find.byKey(ChatUserAvatar.onlineRingKey(3));
    expect(ringOfTwo, findsOneWidget);

    await tester.pumpWidget(
      _Avatars(controller: controller, userIds: const [3]),
    );

    expect(ringOfTwo, findsNothing);
    expect(ringOfThree, findsNothing);

    tracker.deliverPluginMessage(_presenceChannel, {
      'entering_users': [
        {'id': 3, 'username': 'third'},
      ],
    }, messageId: _firstTickId);
    await tester.pump();

    expect(ringOfThree, findsOneWidget);

    tracker.deliverPluginMessage(_presenceChannel, {
      'leaving_user_ids': [2],
    }, messageId: _firstTickId + 1);
    await tester.pump();

    expect(ringOfThree, findsOneWidget);
  });

  testWidgets('an unmounted avatar ignores later presence ticks', (
    tester,
  ) async {
    final tracker = await _pumpAvatars(tester, userIds: const [2]);
    final controller = _harnessOf(tester);

    await tester.pumpWidget(
      _Avatars(controller: controller, userIds: const []),
    );
    tracker.deliverPluginMessage(_presenceChannel, {
      'leaving_user_ids': [2],
    }, messageId: _firstTickId);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a mounted avatar follows the site being forgotten and reloaded',
    (tester) async {
      await _pumpAvatars(tester, userIds: const [2]);
      final controller = _harnessOf(tester);
      final ring = find.byKey(ChatUserAvatar.onlineRingKey(2));
      expect(ring, findsOneWidget);

      controller.chat.forget(_siteUrl);
      await tester.pump();

      expect(ring, findsNothing);

      await tester.pumpWidget(
        _Avatars(controller: controller, userIds: const [2]),
      );
      await controller.chat.loadChannels(_siteUrl, force: true);
      await tester.pump();

      expect(ring, findsOneWidget);
    },
  );
}

/// Records every element the framework rebuilds, naming the user of each
/// avatar among them, from the moment it is attached.
final class _RebuildLog {
  final users = <int>[];
  int elements = 0;

  void attach(void Function(VoidCallback) addTearDown) {
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      elements++;
      if (element.widget is DAvatar) {
        users.add(
          element.findAncestorWidgetOfExactType<ChatUserAvatar>()!.userId,
        );
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
  }
}

ShellController _harnessOf(WidgetTester tester) =>
    tester.widget<_Avatars>(find.byType(_Avatars)).controller;

/// User 2 is online in the snapshot the tracker's stream continues from.
Future<FakeSiteTracker> _pumpAvatars(
  WidgetTester tester, {
  required List<int> userIds,
}) async {
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      const DiscourseInstance(
        url: _siteUrl,
        title: 'Meta',
        apiVersion: 4,
        user: _reader,
      ),
    ]),
    api: FakeDiscourseApi(
      user: _reader,
      chatChannelsBySite: {
        _siteUrl: const ChatChannels(
          public: [],
          direct: [],
          presence: ChatPresence(userIds: {2}, lastMessageId: 47),
        ),
      },
    ),
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: installedPlugins,
  );
  addTearDown(controller.dispose);
  await controller.load();
  await controller.chat.loadChannels(_siteUrl);
  await tester.pumpWidget(_Avatars(controller: controller, userIds: userIds));
  await tester.pumpAndSettle();
  return FakeSiteTracker.built.single;
}

class _Avatars extends StatelessWidget {
  const _Avatars({required this.controller, required this.userIds});

  final ShellController controller;
  final List<int> userIds;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: controller,
    child: PluginUiScope.own(
      chatPluginId,
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Row(
            children: [
              for (final userId in userIds)
                ChatUserAvatar(
                  siteUrl: _siteUrl,
                  userId: userId,
                  url: null,
                  size: 28,
                  fallback: const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
