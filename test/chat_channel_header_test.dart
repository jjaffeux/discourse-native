import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_header.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
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
  testWidgets(
    'mockup identity, metadata, back and details with retained star',
    (tester) async {
      var backs = 0;
      var details = 0;
      await _pump(
        tester,
        messages: [
          for (var id = 1; id <= 8; id++)
            _message(id, thread: id == 1 ? 3 : null),
        ],
        onBack: () => backs++,
        onOpenDetails: () => details++,
      );

      expect(find.text('Channel', findRichText: true), findsOneWidget);
      expect(find.text('8 messages', findRichText: true), findsOneWidget);
      expect(find.text('1 thread', findRichText: true), findsOneWidget);
      expect(
        find.text('last today at 10:25 am', findRichText: true),
        findsOneWidget,
      );
      expect(find.byTooltip('Add to starred channels'), findsOneWidget);
      final title = find.text('general');
      final marker = find.byKey(const ValueKey('chat-channel-header-marker'));
      final back = find.byKey(const ValueKey('chat-channel-back'));
      final metadata = find.byKey(
        const ValueKey('chat-channel-header-metadata'),
      );
      final divider = find.byKey(const ValueKey('content-header-separator'));
      expect(tester.getSize(marker), const Size.square(12));
      expect(tester.getTopLeft(marker).dx, tester.getTopLeft(metadata).dx);
      expect(tester.getTopLeft(divider).dx, tester.getTopLeft(metadata).dx);
      expect(tester.getTopLeft(title).dx - tester.getTopRight(marker).dx, 10);
      expect(
        tester.getBottomLeft(back).dy,
        lessThan(tester.getTopLeft(title).dy),
      );
      expect(
        tester.getBottomLeft(title).dy,
        lessThan(tester.getTopLeft(metadata).dy),
      );
      await tester.tap(back);
      await tester.tap(title);
      expect(backs, 1);
      expect(details, 1);
    },
  );

  testWidgets('partial windows qualify counts and deduplicate threads', (
    tester,
  ) async {
    await _pump(
      tester,
      stream: const ChatStreamState(fetchedOnce: true, canLoadMorePast: true),
      messages: [
        _message(1, thread: 3),
        _message(2, thread: 3),
        _message(3, deleted: true),
      ],
    );
    expect(find.text('2+ messages', findRichText: true), findsOneWidget);
    expect(find.text('1+ threads', findRichText: true), findsOneWidget);
  });

  testWidgets('empty and loading channels do not invent last activity', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('0 messages', findRichText: true), findsOneWidget);
    expect(find.textContaining('last ', findRichText: true), findsNothing);
    expect(find.textContaining('thread', findRichText: true), findsNothing);
    await _pump(tester, stream: const ChatStreamState(loading: true));
    expect(find.text('0 messages', findRichText: true), findsNothing);
  });

  testWidgets(
    'activity follows the latest known channel message when viewing history',
    (tester) async {
      final latest = ChatChannel(
        id: 9,
        title: 'general',
        kind: ChatChannelKind.category,
        lastMessageId: 100,
        lastMessageAt: DateTime(2026, 9, 26, 15, 45),
      );
      await _pump(
        tester,
        channel: latest,
        messages: [_message(1, date: DateTime(2025, 12, 31, 10))],
        stream: const ChatStreamState(
          fetchedOnce: true,
          canLoadMoreFuture: true,
        ),
      );
      expect(
        find.text('last yesterday at 3:45 pm', findRichText: true),
        findsOneWidget,
      );
    },
  );

  testWidgets('older activity shows its date and singular message count', (
    tester,
  ) async {
    await _pump(
      tester,
      messages: [_message(1, date: DateTime(2025, 12, 31, 10))],
    );
    expect(find.text('1 message', findRichText: true), findsOneWidget);
    expect(
      find.text('last Dec 31, 2025 at 10:00 am', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets(
    'long direct-message names and metadata fit a narrow large-text header',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        channel: const ChatChannel(
          id: 9,
          title: 'A very long direct message conversation name',
          kind: ChatChannelKind.directMessage,
          membership: ChatMembership(following: true),
        ),
        messages: [_message(1, thread: 3)],
        scale: 2,
        platform: TargetPlatform.iOS,
      );
      expect(find.text('Direct message', findRichText: true), findsOneWidget);
      final marker = tester.widget<DAvatar>(
        find.byKey(const ValueKey('chat-channel-header-marker')),
      );
      expect(marker.borderRadius, BorderRadius.circular(6));
      expect(find.byTooltip('Add to starred channels'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pump(
  WidgetTester tester, {
  ChatChannel channel = _channel,
  ChatStreamState stream = const ChatStreamState(fetchedOnce: true),
  List<ChatMessage> messages = const [],
  VoidCallback? onBack,
  VoidCallback? onOpenDetails,
  double scale = 1,
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
  shell.chatRecords.put(_site, channel);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: PluginUiScope.own(
        chatPluginId,
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: platform),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Align(
                alignment: Alignment.topCenter,
                child: ChatChannelHeader(
                  siteUrl: _site,
                  channelId: channel.id,
                  channel: channel,
                  stream: stream,
                  activity: const ChatChannelActivity().adding(messages),
                  onBack: onBack ?? () {},
                  onOpenDetails: onOpenDetails ?? () {},
                  now: _now,
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
