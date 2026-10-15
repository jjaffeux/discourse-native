import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_header.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
final _now = DateTime(2026, 9, 27, 12);
const _channel = ChatChannel(
  id: 9,
  title: 'general',
  kind: ChatChannelKind.category,
  categoryColor: Color(0xFF888888),
  membership: ChatMembership(following: true),
  tracking: ChatTracking(unreadCount: 1),
);

ChatMessage _message(
  int id, {
  int? thread,
  DateTime? date,
  bool deleted = false,
}) => ChatMessage(
  id: id,
  channelId: 9,
  cooked: '<p>Message $id</p>',
  author: const ChatMessageAuthor(id: 2, username: 'sam'),
  createdAt: date ?? DateTime(2026, 9, 27, 10, 25),
  deletedAt: deleted ? _now : null,
  thread: thread == null
      ? null
      : ChatThreadPreview(threadId: thread, replyCount: 2),
);

void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('channel identity stays on one line on $platform', (
      tester,
    ) async {
      var details = 0;
      await _pump(tester, platform: platform, onOpenDetails: () => details++);
      final marker = find.byKey(const ValueKey('chat-channel-header-marker'));
      final title = find.text('general');
      final count = find.byKey(const ValueKey('chat-compact-message-count'));
      expect(tester.getSize(marker), const Size.square(10));
      expect(tester.getTopLeft(title).dx - tester.getTopRight(marker).dx, 8);
      expect(
        tester.getRect(title).center.dy,
        closeTo(tester.getRect(count).center.dy, .01),
      );
      expect(find.text('1 unread message'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-channel-header-metadata')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('content-header-separator')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('chat-channel-back')), findsNothing);
      await tester.tap(title);
      expect(details, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final unreadCount in [0, 1, 42]) {
    testWidgets('header shows exactly $unreadCount unread messages', (
      tester,
    ) async {
      await _pump(
        tester,
        channel: _channel.withTrackingState(
          tracking: ChatTracking(
            unreadCount: unreadCount,
            mentionCount: 3,
            watchedThreadsUnreadCount: 5,
          ),
        ),
      );
      expect(
        find.text(
          unreadCount == 1
              ? '1 unread message'
              : '$unreadCount unread messages',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('+'), findsNothing);
      expect(find.textContaining('thread'), findsNothing);
    });
  }

  testWidgets(
    'loading and empty channels keep the same compact header height',
    (tester) async {
      await _pump(tester, channel: null);
      final header = find.byKey(const ValueKey('chat-channel-header'));
      final loadingHeight = tester.getSize(header).height;
      expect(
        find.byKey(const ValueKey('chat-compact-message-count')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('chat-channel-header-metadata')),
        findsNothing,
      );
      await _pump(
        tester,
        channel: _channel.withTrackingState(tracking: ChatTracking.none),
      );
      expect(find.text('0 unread messages'), findsOneWidget);
      expect(tester.getSize(header).height, loadingHeight);
      expect(loadingHeight, 47);
    },
  );

  test(
    'activity keeps distinct thread counts and the latest loaded date for thread readers',
    () {
      final activity = const ChatChannelActivity().adding([
        _message(1, thread: 3),
        _message(2, thread: 3, date: _now),
        _message(3, deleted: true),
      ]);
      expect(activity.messageCount, 2);
      expect(activity.threadIds, {3});
      expect(activity.latestAt, _now);
    },
  );

  testWidgets('long direct-message names fit a narrow large-text single line', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      channel: const ChatChannel(
        id: 9,
        title: 'A very long direct message conversation name',
        kind: ChatChannelKind.directMessage,
        users: [ChatUser(id: 2, username: 'sam')],
        tracking: ChatTracking(unreadCount: 23),
      ),
      scale: 2,
      platform: TargetPlatform.iOS,
    );
    final marker = tester.widget<DAvatar>(
      find.byKey(const ValueKey('chat-channel-header-marker')),
    );
    expect(marker.dimension, 10);
    expect(marker.borderRadius, BorderRadius.circular(6));
    expect(
      find.byKey(const ValueKey('chat-channel-header-metadata')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  ChatChannel? channel = _channel,
  VoidCallback? onOpenDetails,
  double scale = 1,
  bool use24HourClock = false,
  TargetPlatform platform = TargetPlatform.macOS,
}) async {
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
    ]),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  if (channel != null) shell.chatRecords.put(_site, channel);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: PluginUiScope.own(
        chatPluginId,
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: platform),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(scale),
                alwaysUse24HourFormat: use24HourClock,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ChatChannelHeader(
                  siteUrl: _site,
                  channelId: channel?.id ?? 9,
                  channel: channel,
                  onOpenDetails: onOpenDetails ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
