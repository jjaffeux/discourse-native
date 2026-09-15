import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/app_settings_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/topic_scroll_capture.dart';

final _reader = find.byType(TopicView);
final _allLists = find.byType(TopicListView, skipOffstage: false);
final _back = find.byKey(const ValueKey('topic-page-back'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final direction in TextDirection.values) {
    testWidgets(
      'topic replaces the list without covering navigation ($direction)',
      (tester) async {
        final h = await _setup(
          tester,
          direction: direction,
          size: const Size(1800, 900),
        );
        final listElement = tester.element(_allLists);
        final listRect = tester.getRect(find.byType(TopicListView));
        h.shell.openTopicFromList(h.topics.first);
        await tester.pumpAndSettle();
        expect(_reader, findsOneWidget);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byType(TopicListView), findsNothing);
        expect(tester.element(_allLists), same(listElement));
        final reader = tester.getRect(_reader);
        expect(reader.left, closeTo(listRect.left, 1));
        expect(reader.width, closeTo(listRect.width, 1));
        expect(find.byType(InstanceRail).hitTestable(), findsOneWidget);
        expect(find.byType(InstanceSidebar).hitTestable(), findsOneWidget);
        expect(Navigator.of(tester.element(_reader)).canPop(), isFalse);
        final previous = find.byKey(const ValueKey('inbox-previous-topic'));
        final next = find.byKey(const ValueKey('inbox-next-topic'));
        expect(tester.getCenter(previous).dy, tester.getCenter(next).dy);
        expect(tester.widget<DButton>(previous).onPressed, isNull);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(h.shell.currentContent?.topicId, 2);
        expect(h.shell.contentStack, hasLength(2));
        await tester.tap(previous);
        await tester.pumpAndSettle();
        expect(h.shell.currentContent?.topicId, 1);
        await tester.tap(_back);
        await tester.pumpAndSettle();
        expect(_reader, findsNothing);
        expect(find.byType(TopicListView), findsOneWidget);
        expect(tester.element(_allLists), same(listElement));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'return restores the exact list scroll and the topic reading position',
    (tester) async {
      final h = await _setup(tester);
      await tester.drag(find.byType(TopicListView), const Offset(0, -420));
      await tester.pumpAndSettle();
      final listPosition = tester
          .state<ScrollableState>(
            find.descendant(
              of: _allLists,
              matching: find.byType(Scrollable, skipOffstage: false),
              skipOffstage: false,
            ),
          )
          .position;
      final listOffset = listPosition.pixels;
      expect(listOffset, greaterThan(0));
      h.shell.openTopicFromList(h.topics.first);
      await tester.pumpAndSettle();
      await tester.drag(_reader, const Offset(0, -380));
      await tester.pumpAndSettle();
      final readingOffset = _readerScroll(tester).pixels;
      expect(readingOffset, greaterThan(0));
      await tester.tap(_back);
      await tester.pumpAndSettle();
      expect(listPosition.pixels, closeTo(listOffset, 1));
      h.shell.openTopicFromList(h.topics.first);
      await tester.pumpAndSettle();
      expect(_readerScroll(tester).pixels, closeTo(readingOffset, 1));
      await tester.tap(find.byKey(const ValueKey('inbox-next-topic')));
      await tester.pumpAndSettle();
      await tester.tap(_back);
      await tester.pumpAndSettle();
      expect(listPosition.pixels, closeTo(listOffset, 1));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'topic switcher searches the source list and keeps the draft destination',
    (tester) async {
      final h = await _setup(tester);
      h.shell.openTopicFromList(h.topics.first);
      await tester.pumpAndSettle();
      h.shell.openReply();
      await tester.pumpAndSettle();
      final composer = h.shell.visibleComposer!;
      composer.text.text = 'My reply to the first topic';
      await tester.pump(const Duration(seconds: 2));
      final editorState = tester.state(find.byType(ComposerEditor));
      await tester.tap(find.byKey(const ValueKey('topic-switcher-trigger')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(('switch-topic', 2))), findsOneWidget);
      final input = find.descendant(
        of: find.byType(DComboboxInput<int>),
        matching: find.byType(EditableText),
      );
      await tester.enterText(input, 'Conversation 12');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey(('switch-topic', 12))));
      await tester.pumpAndSettle();
      expect(h.shell.currentContent?.topicId, 12);
      expect(h.shell.visibleComposer, same(composer));
      expect(composer.target.topicId, 1);
      expect(composer.raw, 'My reply to the first topic');
      expect(tester.state(find.byType(ComposerEditor)), same(editorState));
      await tester.tap(find.byKey(const ValueKey('composer-return-to-topic')));
      await tester.pumpAndSettle();
      expect(h.shell.currentContent?.topicId, 1);
      expect(composer.raw, 'My reply to the first topic');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('Escape dismisses the switcher and U returns to the list', (
    tester,
  ) async {
    final h = await _setup(tester);
    h.shell.openTopicFromList(h.topics.first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('topic-switcher-trigger')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.shell.currentContent?.topicId, 1);
    expect(find.byType(DComboboxInput<int>), findsNothing);
    await tester.tap(_reader, warnIfMissed: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.pumpAndSettle();
    expect(h.shell.currentContent?.isTopicList, isTrue);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'responsive docking retains editor and reader while rail stays visible',
    (tester) async {
      final h = await _setup(tester);
      h.shell.openTopicFromList(h.topics.first);
      await tester.pumpAndSettle();
      final topicState = tester.state(_reader);
      h.shell.openReply();
      await tester.pumpAndSettle();
      final composer = h.shell.visibleComposer!;
      composer.text.text = 'A draft that survives resizing';
      await tester.pump(const Duration(seconds: 2));
      composer.text.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 8,
      );
      final editor = find.byType(ComposerEditor);
      final editorState = tester.state(editor);
      for (final width in [1440.0, 960.0, 720.0, 390.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpAndSettle();
        expect(tester.state(_reader), same(topicState));
        expect(tester.state(editor), same(editorState));
        expect(
          composer.text.selection,
          const TextSelection(baseOffset: 2, extentOffset: 8),
        );
        expect(find.byType(InstanceRail).hitTestable(), findsOneWidget);
        final reader = tester.getRect(_reader);
        final panel = tester.getRect(find.byType(ComposerPanel));
        if (width >= 890) {
          expect(panel.left, greaterThanOrEqualTo(reader.right));
          expect(reader.width, greaterThanOrEqualTo(480));
        } else {
          expect(panel.top, greaterThanOrEqualTo(reader.bottom));
        }
        expect(
          find.byKey(const ValueKey('desktop-navigation-trigger')),
          width < 1100 ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
      expect(composer.raw, 'A draft that survives resizing');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'narrow navigation opens and dismisses without losing topic or draft',
    (tester) async {
      final h = await _setup(tester, size: const Size(960, 900));
      h.shell.openTopicFromList(h.topics.first);
      await tester.pumpAndSettle();
      h.shell.openReply();
      await tester.pumpAndSettle();
      final composer = h.shell.visibleComposer!;
      composer.text.text = 'Still here';
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(
        find.byKey(const ValueKey('desktop-navigation-trigger')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InstanceSidebar).hitTestable(), findsOneWidget);
      expect(
        tester.getRect(find.byType(InstanceSidebar).hitTestable()).left,
        greaterThanOrEqualTo(tester.getRect(find.byType(InstanceRail)).right),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.shell.currentContent?.topicId, 1);
      expect(composer.raw, 'Still here');
      expect(find.byType(InstanceSidebar).hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final dock in ['left', 'bottom', 'right']) {
    testWidgets('$dock dock leaves rail, sidebar and titlebar in place', (
      tester,
    ) async {
      final h = await _setup(tester);
      h.shell.openTopicFromList(h.topics.first);
      await tester.pumpAndSettle();
      final rail = tester.getRect(find.byType(InstanceRail));
      final sidebar = tester.getRect(find.byType(InstanceSidebar));
      final titlebar = tester.getRect(find.byType(ShellTitleBar));
      h.shell.openReply();
      await tester.pumpAndSettle();
      if (dock == 'right') {
        await tester.tap(find.byKey(const ValueKey('composer-options')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Dock bottom'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('composer-options')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Dock $dock'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(InstanceRail)), rail);
      expect(tester.getRect(find.byType(InstanceSidebar)), sidebar);
      expect(tester.getRect(find.byType(ShellTitleBar)), titlebar);
      expect(h.shell.visibleComposer!.focus.hasFocus, isTrue);
      expect(find.byType(TopicListView), findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }

  testWidgets('tabs preserve each topic position and the active draft', (
    tester,
  ) async {
    final h = await _setup(tester);
    final firstTab = h.shell.activeTabId!;
    h.shell.openTopicFromList(h.topics.first);
    await tester.pumpAndSettle();
    await tester.drag(_reader, const Offset(0, -350));
    await tester.pumpAndSettle();
    final offset = _readerScroll(tester).pixels;
    h.shell.openReply();
    await tester.pumpAndSettle();
    final composer = h.shell.visibleComposer!;
    composer.text.text = 'Draft in the first topic';
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('forum-tabs-add')));
    await tester.pumpAndSettle();
    h.shell.openTopicFromList(h.topics[1]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('forum-tab-item-$firstTab')));
    await tester.pumpAndSettle();
    expect(h.shell.currentContent?.topicId, 1);
    expect(_readerScroll(tester).pixels, closeTo(offset, 1));
    expect(h.shell.visibleComposer, same(composer));
    expect(composer.raw, 'Draft in the first topic');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final reply in [true, false]) {
    testWidgets('compose shortcut works from the topic scope ($reply)', (
      tester,
    ) async {
      final h = await _setup(tester);
      h.shell.openTopicFromList(h.topics.first);
      await tester.pumpAndSettle();
      FocusScope.of(tester.element(_reader)).unfocus();
      await tester.pump();
      await _composeShortcut(tester, reply: reply);
      await tester.pumpAndSettle();
      expect(h.shell.visibleComposer, isNotNull);
      expect(h.shell.visibleComposer!.target.createsTopic, !reply);
      expect(h.shell.visibleComposer!.focus.hasFocus, isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }

  testWidgets('dialogs block compose shortcuts until dismissed', (
    tester,
  ) async {
    final h = await _setup(tester);
    h.shell.openTopicFromList(h.topics.first);
    await tester.pumpAndSettle();
    final dialog = showDDialog<void>(
      context: tester.element(_reader),
      builder: (context, controller) => const DDialogContent(
        children: [DDialogTitle(child: Text('Topic details'))],
      ),
    );
    await tester.pumpAndSettle();
    await _composeShortcut(tester, reply: true);
    await tester.pumpAndSettle();
    expect(h.shell.visibleComposer, isNull);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await dialog;
    await _composeShortcut(tester, reply: true);
    await tester.pumpAndSettle();
    expect(h.shell.visibleComposer, isNotNull);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('mobile retains its existing inline reader', (tester) async {
    final h = await _setup(tester, size: const Size(390, 844));
    h.shell.openTopicFromList(h.topics.first);
    await tester.pumpAndSettle();
    expect(_reader, findsOneWidget);
    expect(find.byKey(const ValueKey('topic-page-navigation')), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}

ScrollPosition _readerScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(TopicView),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      ),
    )
    .position;

Future<void> _composeShortcut(
  WidgetTester tester, {
  required bool reply,
}) async {
  if (reply) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(
    reply ? LogicalKeyboardKey.keyR : LogicalKeyboardKey.keyC,
  );
  if (reply) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
}

Future<({ShellController shell, List<Topic> topics})> _setup(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  TextDirection direction = TextDirection.ltr,
  AppSettingsController? settings,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const user = DiscourseUser(id: 1, username: 'reader', canCreateTopic: true);
  final topics = [
    for (var id = 1; id <= 40; id++)
      Topic(id: id, title: 'Conversation $id', slug: 'conversation-$id'),
  ];
  final api = FakeDiscourseApi(
    user: user,
    feeds: {'/latest.json': topics},
    creatableFeedPaths: const {'/latest.json'},
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
  final diagnostics = (await tester.runAsync(
    () => DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
      topicScrollCapture: topicScrollCaptureWithoutVm(),
    ),
  ))!;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    shell.dispose();
    await tester.runAsync(diagnostics.close);
  });
  await shell.load();
  await shell.loadFeed('latest');
  await tester.pumpWidget(
    DiagnosticsScope(
      controller: diagnostics,
      child: ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light,
          home: DDirection(
            textDirection: direction,
            child: settings == null
                ? const AdaptiveShell()
                : ContentAlignmentScope(
                    controller: settings,
                    child: const AdaptiveShell(),
                  ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (shell: shell, topics: topics);
}
