import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/assign/assign_module.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/ui/foundation/control_artwork.dart';
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
  List<TopicTag> tags = const [TopicTag(id: 1, name: 'show-and-tell')],
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
    tags: privateMessage ? const [] : tags,
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
  testWidgets('mobile tag overflow and wrapped rows have 8px painted gaps', (
    tester,
  ) async {
    await pumpMobileShellFixture(
      tester,
      size: const Size(320, 1000),
      topic: mobileTopicPayload(
        tags: const [
          TopicTag(id: 1, name: 'ui'),
          TopicTag(id: 2, name: 'long-hidden-tag'),
        ],
      ),
    );
    await tester.tap(find.byKey(const ValueKey('topic-card-7')));
    await tester.pumpAndSettle();
    Rect surface(Key key) => tester.getRect(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(DControlArtwork),
      ),
    );
    Rect category() => tester.getRect(
      find
          .descendant(
            of: find.byKey(const ValueKey('topic-header-parent-category')),
            matching: find.byType(DControlArtwork),
          )
          .first,
    );
    final line = find.byKey(const ValueKey('topic-header-taxonomy'));
    final more = find.byKey(const ValueKey('topic-header-more-tags'));
    // Neither tag fits beside the tools, so the count stands for both.
    expect(
      find.byKey(const ValueKey(('topic-header-tag', 'ui'))),
      findsNothing,
    );
    final overflow = surface(const ValueKey('topic-header-more-tags'));
    var bookmark = surface(const ValueKey('topic-header-bookmark-button'));
    expect(overflow.left - category().right, closeTo(8, .001));
    expect(bookmark.left - overflow.right, greaterThanOrEqualTo(8));
    expect(bookmark.top, overflow.top);
    expect(
      surface(const ValueKey('topic-more-actions')).right,
      tester.getRect(line).right,
    );

    // The count opens every tag inline, wrapping onto rows of their own.
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(more, findsNothing);
    expect(find.byKey(const ValueKey('topic-tag-picker-query')), findsNothing);
    final tag = surface(const ValueKey(('topic-header-tag', 'ui')));
    final wrapped = surface(
      const ValueKey(('topic-header-tag', 'long-hidden-tag')),
    );
    bookmark = surface(const ValueKey('topic-header-bookmark-button'));
    expect(tag.left - category().right, closeTo(8, .001));
    expect(wrapped.top - tag.bottom, closeTo(8, .001));
    expect(bookmark.top - wrapped.bottom, closeTo(8, .001));
    // The tools stay at the end of the run's last line.
    expect(
      surface(const ValueKey('topic-more-actions')).right,
      tester.getRect(line).right,
    );
    expect(tester.takeException(), isNull);
  }, variant: platforms);
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
      // A phone keeps assigning in the topic's actions sheet, not the head.
      expect(find.byKey(const Key('assign-topic-header')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('topic-more-actions')));
      await tester.pumpAndSettle();
      final assignment = find.byKey(const Key('assign-topic-action'));
      expect(assignment, enabled && allowed ? findsOneWidget : findsNothing);
      if (enabled && allowed) {
        expect(
          find.descendant(of: assignment, matching: find.text('Assign topic')),
          findsOneWidget,
        );
        expect(assignment.hitTestable(), findsOneWidget);
        await tester.tap(assignment);
        await tester.pumpAndSettle();
        expect(find.byType(DDropdownMenuContent), findsNothing);
        expect(find.byKey(const Key('assignment-drawer')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }, variant: platforms);
  }

  testWidgets('mobile topic header shares grouped actions and mockup spacing', (
    tester,
  ) async {
    await pumpMobileTopicFixture(tester);
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
    Finder surface(Finder control) =>
        find.descendant(of: control, matching: find.byType(DControlArtwork));
    final category = find.descendant(
      of: find.byKey(const ValueKey('topic-header-parent-category')),
      matching: find.byType(DButton),
    );
    final categorySurface = tester.getRect(surface(category));
    final more = find.byKey(const ValueKey('topic-more-actions'));
    // One actions button holds staff's tools on a phone.
    expect(find.byKey(const ValueKey('topic-status-button')), findsNothing);
    for (final control in [bookmark, notifications, more]) {
      expect(tester.widget<DButton>(control).size, DButtonSize.filter);
      expect(tester.widget<DButton>(control).variant, DButtonVariant.tool);
      expect(
        tester.getRect(surface(control)).height,
        closeTo(categorySurface.height, .01),
      );
    }
    expect(
      tester.getRect(surface(bookmark)).right,
      tester.getRect(surface(notifications)).left,
    );
    expect(
      tester.getRect(surface(more)).left -
          tester.getRect(surface(notifications)).right,
      closeTo(8, .01),
    );
    final countSurface = tester.getRect(
      surface(find.byKey(const ValueKey('topic-header-more-tags'))),
    );
    expect(countSurface.left - categorySurface.right, closeTo(8, .01));
    expect(countSurface.top, categorySurface.top);
    final title = tester.getRect(
      find.byKey(const ValueKey('topic-header-compact-title')),
    );
    expect(categorySurface.top - title.bottom, closeTo(16, .1));
    expect(find.byKey(const ValueKey('topic-close-reader')), findsNothing);
    expect(find.byKey(const ValueKey('sheet-drag-handle')), findsOneWidget);
    final header = tester.getRect(
      find.byKey(const ValueKey('topic-header-morph')),
    );
    expect(title.top - header.top, closeTo(16, .1));
    tester.view.physicalSize = const Size(800, 1000);
    await tester.pumpAndSettle();
    final notificationSurface = tester.getRect(surface(notifications));
    final moreSurface = tester.getRect(surface(more));
    expect(moreSurface.top, notificationSurface.top);
    expect(moreSurface.left - notificationSurface.right, closeTo(8, .01));
    expect(find.byKey(const ValueKey('topic-status-button')), findsNothing);
    // With room for it, the tag joins the category on the tools' line.
    final tagSurface = tester.getRect(
      surface(
        find.byKey(const ValueKey(('topic-header-tag', 'show-and-tell'))),
      ),
    );
    expect(tagSurface.top, notificationSurface.top);
    expect(
      tagSurface.left - tester.getRect(surface(category)).right,
      closeTo(8, .01),
    );
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
      expect(tester.widget<DButton>(reply).tooltip, 'Reply');
      expect(
        tester.getRect(reply).right,
        lessThanOrEqualTo(tester.getRect(bar).right),
      );
      expect(reply.hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-status-button')), findsNothing);
      for (final key in [
        'topic-header-bookmark-button',
        'topic-header-notification-button',
        'topic-more-actions',
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
        closeTo(tester.getRect(bar).top - 6 - DSpacing.sm, .1),
      );
      expect(
        tester.getRect(progress).right,
        closeTo(panel.right - DSpacing.sm, .1),
      );
      expect(tester.widget<DButton>(progress).shape, DButtonShape.pill);
      expect(
        tester.widget<DButton>(progress).density,
        DButtonDensity.floatingDate,
      );
      expect(tester.takeException(), isNull);
    }
  }, variant: platforms);

  testWidgets('the reader header names its topic once', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpMobileTopicFixture(tester);
    // iOS speaks a node's tooltip after its label.
    final title = tester
        .getSemantics(find.byKey(const ValueKey('topic-header-compact-title')))
        .getSemanticsData();
    expect(title.label, 'Show & tell: houseplant shelfie thread');
    expect(title.tooltip, isEmpty);
    expect(
      find.byTooltip('Show & tell: houseplant shelfie thread'),
      findsOneWidget,
    );
    semantics.dispose();
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
    final more = find.byKey(const ValueKey('topic-more-actions'));
    expect(tag, findsOneWidget);
    expect(actions, findsOneWidget);
    expect(find.byKey(const ValueKey('topic-status-button')), findsNothing);
    for (final action in [bookmark, archive, more]) {
      expect(tester.getRect(action).top, tester.getRect(tag).top);
      expect(tester.getSize(action), tester.getSize(bookmark));
    }
    expect(
      find.descendant(of: archive, matching: find.text('Archive')),
      findsNothing,
    );
    expect(find.byTooltip('Archive from your inboxes'), findsOneWidget);
    expect(tester.getRect(actions).right, lessThanOrEqualTo(430));
    expect(tester.getRect(more).right, tester.getRect(actions).right);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets(
    'mobile topic actions edit, navigate posts, and reply to the current topic',
    (tester) async {
      final shell = await pumpMobileTopicFixture(tester);
      // The tag waits behind its count on a phone; opening it shows the tag,
      // and tapping the tag edits.
      await tester.tap(find.byKey(const ValueKey('topic-header-more-tags')));
      await tester.pumpAndSettle();
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

      await tester.tap(find.byKey(const ValueKey('topic-more-actions')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topic-status-closed')), findsOneWidget);
      await tester.tapAt(const Offset(3, 3));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('topic-progress-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Latest post'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topic-progress-sheet')), findsNothing);
      expect(shell.currentContent?.postNumber, 4);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('topic-progress-button')),
          matching: find.text('4 / 4'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('mobile-topic-reply')));
      await tester.pumpAndSettle();
      expect(
        (shell.visibleComposer?.target as ExistingTopicComposerTarget?)
            ?.topicId,
        7,
      );
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
    'a topic without reply permission retains independent topic creation',
    (tester) async {
      final shell = await pumpMobileTopicFixture(
        tester,
        canReply: false,
        canEditTags: false,
      );
      expect(find.byKey(const ValueKey('mobile-topic-reply')), findsNothing);
      expect(find.byKey(const ValueKey('mobile-new-topic')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('topic-header-edit-tags')),
        findsNothing,
      );
      expect(find.bySemanticsLabel('Open tag show-and-tell'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('topic-header-more-tags')));
      await tester.pumpAndSettle();
      // Without editing, the opened tag navigates rather than edits.
      expect(find.bySemanticsLabel('Open tag show-and-tell'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('topic-tag-picker-query')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('topic-progress-button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('mobile-new-topic')));
      await tester.pumpAndSettle();
      expect(shell.visibleComposer, isNotNull);
      expect(shell.visibleComposer?.target.isNewTopic, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: platforms,
  );
}
