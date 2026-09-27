import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/assign/assign_module.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/bundled_plugins.dart';
import 'support/shell_test_harness.dart';

TopicPayload mobileTopicPayload({
  bool canReply = true,
  bool canEditTags = true,
  bool privateMessage = false,
  bool? canAssign,
}) => (
  detail: TopicDetail(
    id: 7,
    title: 'Show & tell: houseplant shelfie thread',
    stream: const [71, 72, 73, 74],
    postsCount: 4,
    replyCount: 3,
    views: 400,
    canCreatePost: canReply,
    canEditTags: canEditTags,
    canCloseTopic: true,
    privateMessage: privateMessage,
    plugins: pluginRegistry.readTopic({
      'can_assign': ?canAssign,
    }, 'https://meta.discourse.org'),
    tags: privateMessage
        ? const []
        : const [TopicTag(id: 1, name: 'show-and-tell')],
    participants: const [
      TopicParticipant(username: 'mira'),
      TopicParticipant(username: 'solene'),
      TopicParticipant(username: 'theo'),
    ],
  ),
  posts: [
    for (var i = 1; i <= 4; i++)
      Post(
        id: 70 + i,
        postNumber: i,
        username: ['mira', 'solene', 'theo', 'violet'][i - 1],
        cooked:
            '<p>Drop your best shelfie below. I finally got my pothos to cascade properly after moving it away from the west window.</p>'
            '<p>Happy to be told I have this backwards.</p>',
      ),
  ],
);

Future<ShellController> pumpMobileTopicFixture(
  WidgetTester tester, {
  Size size = phone,
  bool canReply = true,
  bool canEditTags = true,
}) async {
  final shell = await pumpMobileShellFixture(
    tester,
    size: size,
    events: true,
    chatUnreadCount: 32,
    topic: mobileTopicPayload(canReply: canReply, canEditTags: canEditTags),
  );
  await tester.tap(find.byKey(const ValueKey('topic-card-7')));
  await tester.pumpAndSettle();
  return shell;
}

void main() {
  const platforms = TargetPlatformVariant({
    TargetPlatform.iOS,
    TargetPlatform.android,
  });
  for (final (enabled, allowed) in [
    (true, true),
    (true, false),
    (false, true),
  ]) {
    testWidgets('mobile header assignment enabled=$enabled allowed=$allowed', (
      tester,
    ) async {
      await pumpMobileShellFixture(
        tester,
        topic: mobileTopicPayload(canAssign: allowed),
        pluginManifest: PluginManifest([
          for (final module in bundledWidgetTestManifest.modules)
            if (enabled || module is! AssignModule) module,
        ]),
      );
      await tester.tap(find.byKey(const ValueKey('topic-card-7')));
      await tester.pumpAndSettle();
      final assignment = find.byKey(const Key('assign-topic-header'));
      expect(assignment, enabled && allowed ? findsOneWidget : findsNothing);
      if (enabled && allowed) {
        expect(tester.widget<DButton>(assignment).size, DButtonSize.filter);
        expect(assignment.hitTestable(), findsOneWidget);
        await tester.tap(assignment);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('assignment-drawer')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }, variant: platforms);
  }

  testWidgets('mobile topic header shares grouped actions and mockup spacing', (
    tester,
  ) async {
    await pumpMobileTopicFixture(tester);
    final actions = find.byKey(const ValueKey('topic-header-taxonomy'));
    final wrap = tester.widget<Wrap>(actions);
    expect(wrap.spacing, 8);
    expect(wrap.runSpacing, 8);
    final bookmark = find.byKey(const ValueKey('topic-header-bookmark-button'));
    final notifications = find.byKey(
      const ValueKey('topic-header-notification-button'),
    );
    final reminders = find.ancestor(
      of: bookmark,
      matching: find.byType(DButtonGroup),
    );
    expect(reminders, findsOneWidget);
    expect(
      find.descendant(of: reminders, matching: notifications),
      findsOneWidget,
    );
    Finder surface(Finder control) => find.descendant(
      of: control,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is AnimatedContainer &&
            widget.decoration is DButtonDecoration,
      ),
    );
    final category = find.descendant(
      of: find.byKey(const ValueKey('topic-header-parent-category')),
      matching: find.byType(DButton),
    );
    final categorySurface = tester.getRect(surface(category));
    for (final control in [
      bookmark,
      notifications,
      find.byKey(const ValueKey('topic-status-button')),
    ]) {
      expect(tester.widget<DButton>(control).size, DButtonSize.filter);
      expect(tester.getRect(surface(control)).height, categorySurface.height);
    }
    expect(
      tester.getRect(surface(bookmark)).right,
      tester.getRect(surface(notifications)).left,
    );
    final title = tester.getRect(
      find.byKey(const ValueKey('topic-header-compact-title')),
    );
    expect(categorySurface.top - title.bottom, closeTo(16, .1));
    final back = find.byKey(const ValueKey('topic-close-reader'));
    final backSurface = tester.getRect(surface(back));
    final header = tester.getRect(
      find.byKey(const ValueKey('topic-content-header')),
    );
    expect(backSurface.top - header.top, closeTo(16, .1));
    expect(title.top - backSurface.bottom, lessThanOrEqualTo(14));
    tester.view.physicalSize = const Size(800, 1000);
    await tester.pumpAndSettle();
    final notificationSurface = tester.getRect(surface(notifications));
    final statusSurface = tester.getRect(
      surface(find.byKey(const ValueKey('topic-status-button'))),
    );
    expect(statusSurface.top, notificationSurface.top);
    expect(statusSurface.left - notificationSurface.right, 8);
    expect(tester.takeException(), isNull);
  }, variant: platforms);
  testWidgets('mobile topic chrome fits and keeps the reader footer free', (
    tester,
  ) async {
    await pumpMobileTopicFixture(tester);
    final bar = find.byKey(const ValueKey('mobile-bottom-bar'));
    final actions = find.byKey(const ValueKey('topic-header-taxonomy'));
    final progress = find.byKey(const ValueKey('topic-progress-button'));
    final reply = find.byKey(const ValueKey('mobile-topic-reply'));
    for (final (width, scale) in [
      (496.0, 1.0),
      (390.0, 1.0),
      (320.0, 1.0),
      (320.0, 2.0),
      (800.0, 1.0),
    ]) {
      tester.view.physicalSize = Size(width, 1000);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topic-bottom-bar')), findsNothing);
      expect(find.byKey(const ValueKey('mobile-new-topic')), findsNothing);
      expect(
        find.byKey(const ValueKey('topic-header-edit-tags')),
        findsNothing,
      );
      expect(
        find.descendant(of: reply, matching: find.text('Reply')),
        findsOneWidget,
      );
      expect(tester.getRect(reply).right, tester.getRect(bar).right);
      for (final key in [
        'topic-header-bookmark-button',
        'topic-header-notification-button',
        'topic-status-button',
      ]) {
        final button = find.byKey(ValueKey(key));
        expect(find.descendant(of: actions, matching: button), findsOneWidget);
        expect(tester.getRect(button).right, lessThanOrEqualTo(width));
        expect(button.hitTestable(), findsOneWidget);
      }
      final panel = tester.getRect(
        find.byKey(const ValueKey('mobile-content-panel')),
      );
      expect(
        tester.getRect(progress).bottom,
        closeTo(panel.bottom - DSpacing.sm, .1),
      );
      expect(
        tester.getRect(progress).right,
        closeTo(panel.right - DSpacing.sm, .1),
      );
      expect(tester.widget<DButton>(progress).shape, DButtonShape.pill);
      expect(tester.takeException(), isNull);
    }
  }, variant: platforms);

  testWidgets('private-message actions match the topic header\'s compact row', (
    tester,
  ) async {
    await pumpMobileShellFixture(
      tester,
      size: const Size(430, 900),
      topic: mobileTopicPayload(privateMessage: true),
    );
    await tester.tap(find.byKey(const ValueKey('topic-card-7')));
    await tester.pumpAndSettle();

    final tag = find.byKey(const ValueKey('topic-header-edit-tags'));
    final actions = find.byKey(const ValueKey('topic-header-taxonomy'));
    final bookmark = find.byKey(const ValueKey('topic-header-bookmark-button'));
    final archive = find.byKey(const ValueKey('message-archive-button'));
    final status = find.byKey(const ValueKey('topic-status-button'));
    expect(tag, findsOneWidget);
    expect(actions, findsOneWidget);
    for (final action in [bookmark, archive, status]) {
      expect(tester.getRect(action).top, tester.getRect(tag).top);
      expect(tester.getSize(action), tester.getSize(bookmark));
    }
    expect(
      find.descendant(of: archive, matching: find.text('Archive')),
      findsNothing,
    );
    expect(find.byTooltip('Archive from your inboxes'), findsOneWidget);
    expect(tester.getRect(actions).right, lessThanOrEqualTo(430));
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets(
    'mobile topic actions edit, navigate posts, and reply to the current topic',
    (tester) async {
      final shell = await pumpMobileTopicFixture(tester);
      await tester.tap(
        find.byKey(const ValueKey(('topic-header-tag', 'show-and-tell'))),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('topic-tag-picker-query')),
        findsOneWidget,
      );
      expect(shell.currentContent?.topicId, 7);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('topic-header-bookmark-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bookmark topic'), findsOneWidget);
      await tester.tapAt(const Offset(3, 3));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('topic-header-notification-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Watching'));
      await tester.pumpAndSettle();
      expect(
        shell.currentTopic?.notificationLevel,
        TopicNotificationLevel.watching,
      );

      await tester.tap(find.byKey(const ValueKey('topic-status-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topic-status-closed')), findsOneWidget);
      await tester.tapAt(const Offset(3, 3));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('topic-progress-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Latest post'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('topic-progress-selection')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('topic-progress-button')),
          matching: find.text('4 / 4'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('mobile-topic-reply')));
      await tester.pumpAndSettle();
      expect(shell.visibleComposer?.target.topicId, 7);
      shell.closeComposer();
      await tester.pumpAndSettle();
      shell.closeTopicListReader();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mobile-topic-reply')), findsNothing);
      expect(find.byKey(const ValueKey('mobile-new-topic')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: platforms,
  );

  testWidgets(
    'a topic without reply permission does not expose creation actions',
    (tester) async {
      await pumpMobileTopicFixture(tester, canReply: false, canEditTags: false);
      expect(find.byKey(const ValueKey('mobile-topic-reply')), findsNothing);
      expect(find.byKey(const ValueKey('mobile-new-topic')), findsNothing);
      expect(
        find.byKey(const ValueKey('topic-header-edit-tags')),
        findsNothing,
      );
      expect(find.bySemanticsLabel('Open tag show-and-tell'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('topic-progress-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: platforms,
  );
}
