import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/list_boundary_shortcuts.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

final _sheet = find.byKey(const ValueKey('desktop-topic-sheet'));
final _list = find.byKey(const ValueKey('inbox-topic-list-pane'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'topic sheets retain the full-width list and return to its scroll position',
    (tester) async {
      final h = await _setup(tester);
      final listElement = tester.element(find.byType(TopicListView));
      final listRect = tester.getRect(_list);
      await tester.drag(find.byType(TopicListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(TopicListView),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      final offset = scroll.pixels;
      h.shell.openTopicFromList(h.topics.first);
      await tester.pumpAndSettle();
      expect(_sheet, findsOneWidget);
      expect(tester.getRect(_list), listRect);
      expect(tester.element(find.byType(TopicListView)), same(listElement));
      expect(scroll.pixels, offset);
      expect(tester.getRect(_sheet).left, greaterThan(listRect.left));
      await tester.tap(find.byKey(const ValueKey('topic-close-reader')));
      await tester.pumpAndSettle();
      expect(_sheet, findsNothing);
      expect(tester.element(find.byType(TopicListView)), same(listElement));
      expect(scroll.pixels, offset);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'all physical docks stay inside the expanding sheet ($direction)',
      (tester) async {
        final h = await _setup(tester, direction: direction);
        h.shell.openTopicFromList(h.topics.first);
        await tester.pumpAndSettle();
        final readingWidth = tester.getSize(_sheet).width;
        final listRect = tester.getRect(_list);
        h.shell.openReply();
        await tester.pumpAndSettle();
        final editor = find.byType(ComposerEditor);
        final editorState = tester.state(editor);
        final composer = h.shell.visibleComposer!;
        await tester.enterText(
          find.descendant(of: editor, matching: find.byType(EditableText)),
          'A draft inside the sheet',
        );
        composer.text.selection = const TextSelection(
          baseOffset: 2,
          extentOffset: 7,
        );
        final selection = composer.text.selection;
        final topicState = tester.state(find.byType(TopicView));
        expect(tester.getSize(_sheet).width, greaterThan(readingWidth));
        for (final dock in ['left', 'bottom', 'right']) {
          await tester.tap(find.byKey(const ValueKey('composer-options')));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Dock $dock'));
          await tester.pumpAndSettle();
          final bounds = tester.getRect(_sheet);
          final frame = tester.getRect(find.byType(ComposerPanel));
          final reader = tester.getRect(find.byType(TopicView));
          expect(bounds.contains(frame.topLeft), isTrue);
          expect(frame.right, lessThanOrEqualTo(bounds.right + .01));
          expect(frame.bottom, lessThanOrEqualTo(bounds.bottom + .01));
          expect(frame.overlaps(reader), isFalse);
          if (dock == 'left') {
            expect(frame.right, lessThanOrEqualTo(reader.left));
          }
          if (dock == 'right') {
            expect(frame.left, greaterThanOrEqualTo(reader.right));
          }
          if (dock == 'bottom') {
            expect(frame.top, greaterThanOrEqualTo(reader.bottom));
          }
          expect(tester.state(editor), same(editorState));
          expect(tester.state(find.byType(TopicView)), same(topicState));
          expect(composer.text.selection, selection);
          expect(tester.getRect(_list), listRect);
          expect(tester.takeException(), isNull);
        }
        await tester.tap(find.byKey(const ValueKey('composer-minimize')));
        await tester.pumpAndSettle();
        expect(tester.getSize(_sheet).width, readingWidth);
        expect(find.byKey(const ValueKey('composer-restore')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('composer-restore')));
        await tester.pumpAndSettle();
        expect(tester.state(editor), same(editorState));
        h.shell.closeTopicSheet();
        await tester.pumpAndSettle();
        expect(find.byType(ComposerPanel), findsNothing);
        expect(h.shell.visibleComposer, same(composer));
        h.shell.openTopicFromList(h.topics.first);
        await tester.pumpAndSettle();
        expect(tester.state(editor), same(editorState));
        expect(composer.raw, 'A draft inside the sheet');
        expect(composer.text.selection, selection);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'narrow desktop falls back to bottom then restores the preferred side',
    (tester) async {
      final h = await _setup(tester);
      h.shell.openTopicFromList(h.topics.first);
      await tester.pumpAndSettle();
      h.shell.openReply();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-options')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Dock left'));
      await tester.pumpAndSettle();
      final editorState = tester.state(find.byType(ComposerEditor));
      tester.view.physicalSize = const Size(650, 850);
      await tester.pumpAndSettle();
      var frame = tester.getRect(find.byType(ComposerPanel));
      var reader = tester.getRect(find.byType(TopicView));
      expect(frame.top, greaterThanOrEqualTo(reader.bottom));
      expect(frame.width, closeTo(tester.getSize(_sheet).width, 1));
      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpAndSettle();
      frame = tester.getRect(find.byType(ComposerPanel));
      reader = tester.getRect(find.byType(TopicView));
      expect(frame.right, lessThanOrEqualTo(reader.left));
      expect(tester.state(find.byType(ComposerEditor)), same(editorState));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Escape dismisses a nested popup before closing the sheet from the reader',
    (tester) async {
      final h = await _setup(tester);
      h.shell.openTopicFromList(h.topics.first);
      await tester.pumpAndSettle();
      h.shell.openReply();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-options')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_sheet, findsOneWidget);
      expect(find.text('Dock side'), findsNothing);
      tester
          .widget<ListBoundaryShortcuts>(
            find.descendant(
              of: find.byType(TopicView),
              matching: find.byType(ListBoundaryShortcuts),
            ),
          )
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_sheet, findsNothing);
      expect(h.shell.currentContent!.isTopic, isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('topic links without a source list still open in a sheet', (
    tester,
  ) async {
    final h = await _setup(tester);
    h.shell.pushContent(ContentRoute.userActivity());
    h.shell.openTopic(h.topics.first);
    await tester.pumpAndSettle();
    expect(_sheet, findsOneWidget);
    h.shell.closeTopicSheet();
    await tester.pumpAndSettle();
    expect(h.shell.currentContent!.id, 'activity');
    expect(_sheet, findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'reading shortcuts navigate within the sheet and return to the list',
    (tester) async {
      final h = await _setup(tester);
      h.shell.openTopicFromList(h.topics.first);
      await tester.pumpAndSettle();
      final readerFocus = tester
          .widget<ListBoundaryShortcuts>(
            find.descendant(
              of: find.byType(TopicView),
              matching: find.byType(ListBoundaryShortcuts),
            ),
          )
          .focusNode!;
      readerFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pumpAndSettle();
      expect(h.shell.currentContent!.topicId, h.topics[1].id);
      expect(_sheet, findsOneWidget);
      tester
          .widget<ListBoundaryShortcuts>(
            find.descendant(
              of: find.byType(TopicView),
              matching: find.byType(ListBoundaryShortcuts),
            ),
          )
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
      await tester.pumpAndSettle();
      expect(_sheet, findsNothing);
      expect(h.shell.currentContent!.isTopicList, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('switching forum tabs retains each sheet editor and its draft', (
    tester,
  ) async {
    final h = await _setup(tester);
    final firstTab = h.shell.activeTabId!;
    h.shell.openTopicFromList(h.topics.first);
    await tester.pumpAndSettle();
    h.shell.openReply();
    await tester.pumpAndSettle();
    final first = h.shell.visibleComposer!;
    final firstEditor = tester.state(find.byType(ComposerEditor));
    first.text.text = 'First tab draft';
    h.shell.createTab();
    h.shell.openTopicFromList(h.topics[1]);
    await tester.pumpAndSettle();
    h.shell.openReply();
    await tester.pumpAndSettle();
    final secondTab = h.shell.activeTabId!;
    final second = h.shell.visibleComposer!;
    final secondEditor = tester.state(find.byType(ComposerEditor));
    second.text.text = 'Second tab draft';
    h.shell.selectTab(firstTab);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(ComposerEditor)), same(firstEditor));
    expect(h.shell.visibleComposer!.raw, 'First tab draft');
    h.shell.selectTab(secondTab);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(ComposerEditor)), same(secondEditor));
    expect(h.shell.visibleComposer!.raw, 'Second tab draft');
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('mobile keeps the existing inline topic presentation', (
    tester,
  ) async {
    final h = await _setup(tester, size: const Size(390, 844));
    h.shell.openTopicFromList(h.topics.first);
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(find.byType(TopicView), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}

Future<({ShellController shell, List<Topic> topics})> _setup(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const user = DiscourseUser(id: 1, username: 'reader');
  final topics = [
    for (var id = 1; id <= 40; id++)
      Topic(id: id, title: 'Conversation $id', slug: 'conversation-$id'),
  ];
  final api = FakeDiscourseApi(
    user: user,
    feeds: {'/latest.json': topics},
    topics: {
      for (final topic in topics)
        topic.id: (
          detail: TopicDetail(
            id: topic.id,
            title: topic.title,
            stream: [topic.id * 10],
            postsCount: 1,
            canCreatePost: true,
          ),
          posts: [
            Post(
              id: topic.id * 10,
              postNumber: 1,
              username: 'sam',
              cooked:
                  '<p>${List.filled(100, 'A conversation with enough text to scroll.').join(' ')}</p>',
            ),
          ],
        ),
    },
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('sheet.example').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys['https://sheet.example'] = 'key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    shell.dispose();
  });
  await shell.load();
  await shell.loadFeed('latest');
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light,
        home: DDirection(
          textDirection: direction,
          child: const AdaptiveShell(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (shell: shell, topics: topics);
}
