import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/desktop_panels.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/new_tab_page.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_metrics.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_post_sliver.dart';
import 'package:discourse_native/src/shell/topic_presentation.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/ui/foundation/glass_presets.dart';
import 'package:discourse_native/src/ui/foundation/material_surface.dart';
import 'package:discourse_native/src/ui/foundation/native_glass.dart'
    show NativeGlassShape;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _topic = Topic(id: 42, title: 'Panel topic', slug: 'panel-topic');
const _otherTopic = Topic(
  id: 43,
  title: 'Another topic',
  slug: 'another-topic',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ShellController shell;
  late FakeDiscourseApi api;

  setUp(() async {
    shell = ShellController(
      instanceStore: FakeInstanceStore([instance('panels.example')]),
      api: api = FakeDiscourseApi(
        creatableFeedPaths: const {'/latest.json'},
        feeds: const {
          '/latest.json': [_topic, _otherTopic],
        },
        topics: {
          for (final topic in [_topic, _otherTopic])
            topic.id: (
              detail: TopicDetail(
                id: topic.id,
                title: topic.title,
                stream: [topic.id],
                postsCount: 1,
              ),
              posts: [
                Post(
                  id: topic.id,
                  postNumber: 1,
                  username: 'reader',
                  cooked: '<p>Content for ${topic.id}</p>',
                ),
              ],
            ),
        },
      ),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    await shell.load();
    await shell.loadFeed('latest');
    shell.desktopTopicTabs = true;
  });
  tearDown(() => shell.dispose());

  for (final direction in TextDirection.values) {
    testWidgets(
      'swapping twice preserves documents, widths, tabs, scroll and focus in $direction',
      (tester) async {
        api.topics[42] = (
          detail: const TopicDetail(
            id: 42,
            title: 'Panel topic',
            stream: [42],
            postsCount: 1,
          ),
          posts: [
            Post(
              id: 42,
              postNumber: 1,
              username: 'reader',
              cooked: List.generate(
                70,
                (i) => '<p>Retained paragraph $i.</p>',
              ).join(),
            ),
          ],
        );
        _openTopicTab(shell, _otherTopic, panel: ForumPanel.main);
        _openTopicTab(shell, _topic);
        await _pump(tester, shell, direction: direction);
        final handle = find.byKey(const ValueKey('main-panel-resize-handle'));
        await tester.drag(
          handle,
          Offset(direction == TextDirection.ltr ? 64 : -64, 0),
        );
        await tester.pumpAndSettle();
        final selected = {
          for (final panel in ForumPanel.values)
            panel: shell.selectedTabIn(panel)!.id,
        };
        final before = {
          ForumPanel.main: tester.getRect(_mainPanel),
          ForumPanel.secondary: tester.getRect(_secondaryPanel),
        };
        final ancestry = {
          for (final panel in [_mainPanel, _secondaryPanel])
            panel: _panelAncestry(tester, panel),
        };
        final readers = tester
            .stateList(find.byType(TopicView, skipOffstage: false))
            .toList();
        final documents = tester
            .stateList(find.byType(MainContent, skipOffstage: false))
            .toList();
        final scroll = tester
            .stateList<ScrollableState>(
              find.descendant(
                of: _secondaryPanel,
                matching: find.byType(Scrollable),
              ),
            )
            .firstWhere((state) => state.position.maxScrollExtent > 200);
        scroll.position.jumpTo(180);
        await tester.pumpAndSettle();
        final focus = tester
            .widgetList<Focus>(
              find.descendant(of: _mainPanel, matching: find.byType(Focus)),
            )
            .firstWhere(
              (widget) => widget.focusNode != null && widget.canRequestFocus,
            )
            .focusNode!;
        focus.requestFocus();
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);
        final active = shell.activeTabId;
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(20, 20));
        addTearDown(mouse.removePointer);
        for (final swapped in [true, false]) {
          await mouse.moveTo(Offset(tester.getCenter(handle).dx, 20));
          await tester.pumpAndSettle();
          expect(_swapVisible(tester), isTrue);
          await tester.tap(_swapButton, kind: PointerDeviceKind.mouse);
          await tester.pumpAndSettle();
          expect(
            tester.getRect(_mainPanel).width,
            before[ForumPanel.main]!.width,
          );
          expect(
            tester.getRect(_secondaryPanel).width,
            before[ForumPanel.secondary]!.width,
          );
          expect(
            tester.getRect(_mainPanel).left <
                tester.getRect(_secondaryPanel).left,
            swapped == (direction == TextDirection.rtl),
          );
          for (final panel in ForumPanel.values) {
            expect(shell.selectedTabIn(panel)?.id, selected[panel]);
          }
          for (final panel in [_mainPanel, _secondaryPanel]) {
            expect(
              _panelAncestry(tester, panel),
              orderedEquals(ancestry[panel]!),
            );
          }
          expect(
            tester.stateList(find.byType(TopicView, skipOffstage: false)),
            orderedEquals(readers),
          );
          expect(
            tester.stateList(find.byType(MainContent, skipOffstage: false)),
            orderedEquals(documents),
          );
          expect(scroll.position.pixels, 180);
          expect(focus.hasFocus, isTrue);
          expect(shell.activeTabId, active);
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'swapped seam reverses pointer and keyboard resizing in $direction',
      (tester) async {
        _openTopicTab(shell, _topic);
        await _pump(tester, shell, direction: direction);
        await _activateSwap(tester);
        final handle = find.byKey(const ValueKey('main-panel-resize-handle'));
        expect(tester.getSize(handle), const Size(4, 36));
        final growsRight = direction == TextDirection.rtl;
        await tester.drag(handle, Offset(growsRight ? 60 : -60, 0));
        await tester.pumpAndSettle();
        expect(tester.getRect(_mainPanel).width, 460);
        final focus = tester
            .widget<Focus>(
              find.byKey(const ValueKey('main-panel-resize-focus')),
            )
            .focusNode!;
        focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(
          growsRight
              ? LogicalKeyboardKey.arrowRight
              : LogicalKeyboardKey.arrowLeft,
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(_mainPanel).width, 476);
        expect(
          tester.getRect(_mainPanel).width +
              tester.getRect(_secondaryPanel).width +
              workspacePanelGap,
          1200,
        );
        expect(tester.takeException(), isNull);
      },
    );

    for (final panel in ForumPanel.values) {
      testWidgets(
        'swapped $panel folds toward its side and restores in $direction',
        (tester) async {
          _openTopicTab(shell, _topic);
          await _pump(tester, shell, direction: direction);
          await _activateSwap(tester);
          final target = panel == ForumPanel.main
              ? _mainPanel
              : _secondaryPanel;
          final other = panel == ForumPanel.main ? _secondaryPanel : _mainPanel;
          final before = tester.getRect(target);
          final previous = {
            for (final panel in [_mainPanel, _secondaryPanel])
              panel: _panelAncestry(tester, panel),
          };
          await tester.tap(
            find.byKey(ValueKey('panel-split-view-${panel.name}')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          await tester.pump(const Duration(milliseconds: 100));
          final moving = tester.getRect(target);
          expect(
            moving.left > before.left,
            panel == ForumPanel.main
                ? direction == TextDirection.ltr
                : direction == TextDirection.rtl,
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(other), const Rect.fromLTWH(0, 0, 1200, 850));
          expect(_swapButton, findsNothing);
          await tester.tap(
            find.byKey(
              ValueKey(
                'panel-split-view-${panel == ForumPanel.main ? 'secondary' : 'main'}',
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(target), before);
          for (final panel in [_mainPanel, _secondaryPanel]) {
            expect(
              _panelAncestry(tester, panel),
              orderedEquals(previous[panel]!),
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'window edges follow swapped physical panel positions in $direction',
      (tester) async {
        final frame = ValueNotifier<Rect?>(
          const Rect.fromLTWH(100, 0, 1200, 850),
        );
        addTearDown(frame.dispose);
        _openTopicTab(shell, _topic);
        await _pump(tester, shell, direction: direction, windowFrame: frame);
        await _activateSwap(tester);
        final left = direction == TextDirection.ltr ? 140.0 : 100.0;
        frame.value = Rect.fromLTWH(left, 0, 1160, 850);
        tester.view.physicalSize = const Size(1160, 850);
        await tester.pumpAndSettle();
        expect(tester.getRect(_mainPanel).width, 360);
        final preferred = tester
            .widget<DesktopPanels>(find.byType(DesktopPanels))
            .layout!
            .mainWidth
            .value;
        await _activateSwap(tester);
        expect(
          tester.getRect(_mainPanel).width,
          360,
          reason: 'swap preserves the displayed window-resize width',
        );
        expect(
          tester
              .widget<DesktopPanels>(find.byType(DesktopPanels))
              .layout!
              .mainWidth
              .value,
          preferred,
        );
        frame.value = Rect.fromLTWH(
          direction == TextDirection.ltr ? 160 : 100,
          0,
          1140,
          850,
        );
        tester.view.physicalSize = const Size(1140, 850);
        await tester.pumpAndSettle();
        expect(tester.getRect(_mainPanel).width, 360);
        expect(tester.getRect(_secondaryPanel).width, 768);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('swap action stays flat under Liquid Glass', (tester) async {
    _openTopicTab(shell, _topic);
    await _pump(tester, shell, material: DAppearanceMaterial.liquidGlass);
    tester.widget<DButton>(_swapButton).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(_swapVisible(tester), isTrue);
    expect(DMaterialTheme.glassOf(tester.element(_mainPanel)), isTrue);
    expect(
      find.descendant(
        of: _swapButton,
        matching: find.byWidgetPredicate(
          (widget) => widget is DGlassSurface || widget is NativeGlassShape,
        ),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: _swapButton, matching: find.byType(DMaterialSurface)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'swap action reveals at hovered edge, stays focusable, hides while resizing, and leaves gaps inert',
    (tester) async {
      _openTopicTab(shell, _topic);
      await _pump(tester, shell);
      final semantics = tester.ensureSemantics();
      try {
        expect(_swapVisible(tester), isFalse);
        final node = tester.getSemantics(_swapButton);
        expect(node.getSemanticsData().label, contains('Swap panels'));
        expect(
          node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isTrue,
        );
        expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
        expect(node.rect.size, tester.getSize(_swapButton));
        tester.platformDispatcher.onSemanticsActionEvent!(
          ui.SemanticsActionEvent(
            type: ui.SemanticsAction.didGainAccessibilityFocus,
            viewId: tester.view.viewId,
            nodeId: node.id,
          ),
        );
        await tester.pumpAndSettle();
        expect(_swapVisible(tester), isTrue);
        tester.widget<DButton>(_swapButton).focusNode!.unfocus();
        await tester.pumpAndSettle();
        expect(_swapVisible(tester), isFalse);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(20, 20));
        addTearDown(mouse.removePointer);
        final handle = find.byKey(const ValueKey('main-panel-resize-handle'));
        final x = tester.getCenter(handle).dx;
        await mouse.moveTo(Offset(x, 20));
        await tester.pumpAndSettle();
        expect(_swapVisible(tester), isTrue);
        expect(tester.getRect(_swapButton), Rect.fromLTWH(x - 13, 44, 26, 26));
        await mouse.moveTo(Offset(x, 830));
        await tester.pumpAndSettle();
        expect(tester.getRect(_swapButton).bottom, 806);
        final width = tester.getRect(_mainPanel).width;
        for (final point in [
          Offset(x, 200),
          Offset(x - 3, 425),
          Offset(x + 3, 425),
        ]) {
          final gap = await tester.startGesture(point);
          await gap.moveBy(const Offset(60, 0));
          await gap.up();
          await tester.pumpAndSettle();
          expect(tester.getRect(_mainPanel).width, width);
        }
        await mouse.moveTo(const Offset(20, 20));
        await tester.pumpAndSettle();
        expect(_swapVisible(tester), isFalse);
        final hiddenRect = tester.getRect(_swapButton);
        await tester.tapAt(hiddenRect.center);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(_mainPanel).left,
          0,
          reason: 'a hidden action cannot receive pointer taps',
        );
        final focus = tester
            .widget<Focus>(
              find.byKey(const ValueKey('main-panel-resize-focus')),
            )
            .focusNode!;
        focus.requestFocus();
        await tester.pumpAndSettle();
        expect(_swapVisible(tester), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(tester.widget<DButton>(_swapButton).focusNode!.hasFocus, isTrue);
        expect(_swapVisible(tester), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(tester.getRect(_mainPanel).right, 1200);
        final drag = await tester.startGesture(tester.getCenter(handle));
        await drag.moveBy(const Offset(-40, 0));
        await tester.pump();
        expect(_swapVisible(tester), isFalse);
        await drag.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('mouse panel swaps retain editor focus, draft and selection', (
    tester,
  ) async {
    _openTopicTab(shell, _topic);
    await _pump(tester, shell);
    final focus = FocusNode();
    final draft = TextEditingController.fromValue(
      const TextEditingValue(
        text: 'An unfinished reply',
        selection: TextSelection(baseOffset: 3, extentOffset: 13),
      ),
    );
    addTearDown(focus.dispose);
    addTearDown(draft.dispose);
    final editor = OverlayEntry(
      builder: (_) => Positioned(
        left: 20,
        top: 100,
        width: 250,
        child: DCard(
          child: DInput(
            key: const ValueKey('swap-editor-draft'),
            controller: draft,
            focusNode: focus,
            semanticLabel: 'Reply draft',
          ),
        ),
      ),
    );
    Overlay.of(tester.element(find.byType(DesktopPanels))).insert(editor);
    try {
      await tester.pumpAndSettle();
      focus.requestFocus();
      await tester.pumpAndSettle();
      final state = tester.state(
        find.descendant(
          of: find.byKey(const ValueKey('swap-editor-draft')),
          matching: find.byType(EditableText),
        ),
      );
      final value = draft.value;
      final active = shell.activeTabId;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(20, 20));
      addTearDown(mouse.removePointer);
      for (var i = 0; i < 2; i++) {
        final handle = find.byKey(const ValueKey('main-panel-resize-handle'));
        await mouse.moveTo(Offset(tester.getCenter(handle).dx, 20));
        await tester.pumpAndSettle();
        await tester.tap(_swapButton, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);
        expect(draft.value, value);
        expect(shell.activeTabId, active);
        expect(
          tester.state(
            find.descendant(
              of: find.byKey(const ValueKey('swap-editor-draft')),
              matching: find.byType(EditableText),
            ),
          ),
          same(state),
        );
      }
    } finally {
      editor.remove();
      await tester.pumpAndSettle();
      editor.dispose();
    }
  });

  testWidgets('swap anchors a displayed main width above its preference', (
    tester,
  ) async {
    final frame = ValueNotifier<Rect?>(const Rect.fromLTWH(100, 0, 1200, 850));
    addTearDown(frame.dispose);
    _openTopicTab(shell, _topic);
    await _pump(tester, shell, windowFrame: frame);
    frame.value = const Rect.fromLTWH(140, 0, 1160, 850);
    await tester.pumpAndSettle();
    expect(tester.getRect(_mainPanel).width, 440);
    final layout = tester
        .widget<DesktopPanels>(find.byType(DesktopPanels))
        .layout!;
    expect(layout.mainWidth.value, 412);
    await _activateSwap(tester);
    expect(tester.getRect(_mainPanel).width, 440);
    expect(tester.getRect(_secondaryPanel).width, 748);
    expect(layout.mainWidth.value, 412);
    await _activateSwap(tester);
    expect(tester.getRect(_mainPanel).width, 440);
    expect(layout.mainWidth.value, 412);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swapped narrow restore returns to its ordered split', (
    tester,
  ) async {
    _openTopicTab(shell, _topic);
    await _pump(tester, shell, reduceMotion: true);
    await _activateSwap(tester);
    final mainWidth = tester.getRect(_mainPanel).width;
    final selected = shell.selectedTabIn(ForumPanel.secondary)!.id;
    await tester.tap(find.byKey(const ValueKey('panel-split-view-secondary')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(600, 850);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('panel-split-view-main')));
    await tester.pumpAndSettle();
    expect(shell.activeTabId, selected);
    expect(_secondaryPanel, findsOneWidget);
    expect(_swapButton, findsNothing);
    tester.view.physicalSize = const Size(1200, 850);
    await tester.pumpAndSettle();
    expect(tester.getRect(_mainPanel).width, mainWidth);
    expect(tester.getRect(_secondaryPanel).left, 0);
    expect(tester.getRect(_mainPanel).right, 1200);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('compact workspace keeps swap clear of grip at scale $scale', (
      tester,
    ) async {
      _openTopicTab(shell, _topic);
      await _pump(
        tester,
        shell,
        size: Size(1200, scale == 1 ? 140 : 176),
        textScale: scale,
      );
      expect(_swapButton, findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('main-panel-resize-handle'))),
        const Size(4, 36),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'panel swap renders at text scale $scale with safe area and reduced motion',
      (tester) async {
        await tester.runAsync(() async {
          await (FontLoader(
            'PanelSwapReview',
          )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
        _openTopicTab(shell, _topic);
        await _pump(
          tester,
          shell,
          reduceMotion: true,
          textScale: scale,
          fontFamily: 'PanelSwapReview',
          safeArea: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        );
        final prefix = scale == 1 ? '' : 'scale-2-';
        await _exportPanelSwap(tester, '${prefix}initial');
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(25, 30));
        addTearDown(mouse.removePointer);
        final handle = find.byKey(const ValueKey('main-panel-resize-handle'));
        await mouse.moveTo(Offset(tester.getCenter(handle).dx, 32));
        await tester.pumpAndSettle();
        expect(_swapVisible(tester), isTrue);
        expect(
          tester.getRect(_swapButton).center.dx,
          tester.getCenter(handle).dx,
        );
        expect(tester.getRect(_swapButton).top, 24 + 44);
        expect(
          tester.getRect(_swapButton).overlaps(tester.getRect(handle)),
          isFalse,
        );
        await _exportPanelSwap(tester, '${prefix}hover-top');
        await tester.tap(_swapButton);
        await tester.pumpAndSettle();
        await mouse.moveTo(const Offset(25, 30));
        await tester.pumpAndSettle();
        await _exportPanelSwap(tester, '${prefix}swapped');
        await mouse.moveTo(Offset(tester.getCenter(handle).dx, 820));
        await tester.pumpAndSettle();
        expect(tester.getRect(_swapButton).bottom, 850 - 16 - 44);
        expect(
          tester.getRect(_swapButton).center.dx,
          tester.getCenter(handle).dx,
        );
        await _exportPanelSwap(tester, '${prefix}hover-bottom');
        await mouse.moveTo(const Offset(25, 30));
        tester.widget<DButton>(_swapButton).focusNode!.requestFocus();
        await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(_swapVisible(tester), isTrue);
        await _exportPanelSwap(tester, '${prefix}keyboard-focus');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('desktop pages paint their workspace material only once', (
    tester,
  ) async {
    Future<void> expectSingleSurface() async {
      await _pump(tester, shell);
      for (final panel in [_mainPanel, _secondaryPanel]) {
        if (panel.evaluate().isEmpty) continue;
        final pages = tester.widgetList<DPageSurface>(
          find.descendant(of: panel, matching: find.byType(DPageSurface)),
        );
        expect(pages, isNotEmpty);
        expect(pages.every((page) => !page.framed), isTrue);
      }
      expect(tester.takeException(), isNull);
    }

    await expectSingleSurface(); // Topic list.
    shell.createTab();
    await expectSingleSurface(); // Start page.
    _openTopicTab(shell, _topic);
    await expectSingleSurface(); // Split reader and list.
  });

  for (final panel in ForumPanel.values) {
    test('list and sidebar navigation reuse the active $panel tab', () {
      shell.moveTabToPanel(shell.activeTabId!, panel);
      final original = shell.activeTabId;
      shell.pushContent(
        const ContentRoute(
          destination: PageDestination(CorePage.users),
          title: 'Users',
          icon: DIcons.user,
        ),
      );
      expect(shell.activeTabId, original);
      expect(shell.activeTab?.panel, panel);
      expect(shell.currentContent?.id, 'users');

      shell.pushContent(
        const ContentRoute(
          destination: PageDestination(CorePage.tags),
          title: 'Tags',
          icon: DIcons.tag,
        ),
      );
      expect(shell.activeTabId, original);
      expect(shell.currentContent?.id, 'all-tags');
      expect(shell.handleBack(canReturnToSidebar: false), isTrue);
      expect(shell.currentContent?.id, 'users');
      expect(shell.handleForward(), isTrue);
      expect(shell.currentContent?.id, 'all-tags');

      shell.selectDestination(
        const SidebarDestination(
          id: 'all-categories',
          label: 'Categories',
          icon: DIcons.folder,
        ),
      );
      expect(shell.activeTabId, original);
      expect(shell.activeTab?.panel, panel);
      expect(shell.currentContent?.id, 'all-categories');
      expect(
        shell.tabsForCurrentForum,
        hasLength(panel == ForumPanel.main ? 2 : 3),
      );
    });
  }

  test('topic clicks reuse the active tab and retain history', () {
    final main = shell.activeTab!;
    expect(shell.openTopicFromList(_topic), TabOpenResult.opened);
    expect(shell.activeTabId, main.id);
    expect(shell.activeTab?.panel, ForumPanel.main);
    expect(shell.currentContent?.topicId, 42);
    expect(shell.tabsForCurrentForum, hasLength(2));

    expect(shell.openTopicFromList(_otherTopic), TabOpenResult.opened);
    expect(shell.activeTabId, main.id);
    expect(shell.currentContent?.topicId, 43);
    expect(shell.contentStack, hasLength(2));
    expect(shell.tabsForCurrentForum, hasLength(2));
    expect(shell.handleBack(canReturnToSidebar: false), isTrue);
    expect(shell.currentContent?.topicId, 42);
    expect(shell.handleForward(), isTrue);
    expect(shell.currentContent?.topicId, 43);
  });

  test('topic links use the active panel and reset explicit posts', () {
    final main = shell.activeTab!;
    shell.createTab(panel: ForumPanel.secondary);
    final selectedId = shell.activeTabId!;
    shell.createTab(panel: ForumPanel.secondary);
    final other = shell.activeTab!;
    shell.selectTab(selectedId);
    shell.openTopic(_topic);
    shell.saveTopicScrollPost(42, 9);
    shell.openTopic(_otherTopic);
    shell.selectTab(main.id);

    expect(shell.openTopicUrl('/t/panel-topic/42/3'), isTrue);
    expect(shell.activeTabId, main.id);
    expect(shell.currentContent?.topicId, 42);
    expect(shell.currentContent?.postNumber, 3);
    expect(shell.topicScrollPostNumber(42), 3);
    expect(shell.activeTab?.anchors['topic-42'], isNull);
    expect(shell.currentWorkspace?.tabById(other.id), other);
    expect(shell.selectedTabIn(ForumPanel.secondary)?.id, selectedId);
    expect(shell.tabsForCurrentForum, hasLength(4));
  });

  for (final panel in ForumPanel.values) {
    for (final samePanel in [true, false]) {
      for (final entryPoint in ['link', 'content']) {
        test(
          '$entryPoint navigation to $panel from the '
          '${samePanel ? 'current' : 'opposite'} panel honors explicit posts',
          () {
            shell.createTab(panel: panel);
            final targetId = shell.activeTabId!;
            shell.openTopic(_topic);
            shell.saveTopicScrollPost(42, 9, viewportOffset: -24);
            shell.openTopic(_otherTopic);
            final sourcePanel = samePanel
                ? panel
                : panel == ForumPanel.main
                ? ForumPanel.secondary
                : ForumPanel.main;
            final sourceId = samePanel
                ? targetId
                : shell.selectedTabIn(sourcePanel)!.id;
            shell.selectTab(sourceId);

            TabOpenResult open({required bool explicit}) => entryPoint == 'link'
                ? shell.openLinkInPanel(
                    '/t/panel-topic/42${explicit ? '/3' : ''}',
                    panel: panel,
                  )
                : shell.openContentInPanel(
                    ContentRoute.topic(
                      topicId: 42,
                      slug: _topic.slug,
                      title: _topic.title,
                      postNumber: explicit ? 3 : null,
                    ),
                    panel: panel,
                    resetScrollPosition: explicit,
                  );

            expect(open(explicit: true), TabOpenResult.opened);
            expect(shell.activeTabId, targetId);
            expect(shell.currentContent?.postNumber, 3);
            expect(shell.topicScrollPostNumber(42), 3);
            expect(shell.topicScrollPostOffset(42), 0);
            expect(shell.activeTab!.anchors['topic-42'], isNull);

            shell.saveTopicScrollPost(42, 9, viewportOffset: -24);
            final anchor = shell.activeTab!.anchors['topic-42'];
            shell.openTopic(_otherTopic);
            shell.selectTab(sourceId);

            expect(open(explicit: false), TabOpenResult.opened);
            expect(shell.activeTabId, targetId);
            expect(shell.currentContent?.postNumber, isNull);
            expect(shell.topicScrollPostNumber(42), 9);
            expect(shell.topicScrollPostOffset(42), -24);
            expect(shell.activeTab!.anchors['topic-42'], same(anchor));
          },
        );
      }
    }

    test('search result posts override a saved reading position in $panel', () {
      shell.moveTabToPanel(shell.activeTabId!, panel);
      final targetId = shell.activeTabId;
      shell.openTopic(_topic);
      shell.saveTopicScrollPost(42, 9, viewportOffset: -24);
      shell.openTopic(_otherTopic);

      shell.openSearchResult(
        const SearchPostHit(
          postId: 4203,
          topicId: 42,
          postNumber: 3,
          topicTitle: 'Panel topic',
          topicSlug: 'panel-topic',
          username: 'reader',
          excerpt: SearchExcerpt([SearchExcerptSegment('Matched post')]),
        ),
      );

      expect(shell.activeTabId, targetId);
      expect(shell.currentContent?.postNumber, 3);
      expect(shell.topicScrollPostNumber(42), 3);
      expect(shell.topicScrollPostOffset(42), 0);
      expect(shell.activeTab!.anchors['topic-42'], isNull);
    });
  }

  test('topic clicks retain the current list as their source', () {
    final mainId = shell.activeTabId!;
    shell.openTopicFromList(_topic);
    expect(shell.activeTabId, mainId);
    shell.openListUrl('/tag/flutter');
    final list = shell.currentContent;

    shell.openTopicFromList(_otherTopic);

    expect(shell.activeTabId, mainId);
    expect(shell.topicListContent, list);
    expect(shell.currentContent?.topicId, 43);
    expect(shell.tabsForCurrentForum, hasLength(2));
    expect(shell.handleBack(canReturnToSidebar: false), isTrue);
    expect(shell.currentContent, list);
  });

  test(
    'move, persist, close and reopen retain tab state and panel selections',
    () {
      _openTopicTab(shell, _topic);
      final topic = shell.activeTab!;
      shell.saveTopicScrollPost(42, 7, viewportOffset: 21);
      final beforeMove = shell.activeTab!;
      shell.moveTabToPanel(topic.id, ForumPanel.main, index: 0);
      expect(shell.activeTab, beforeMove.copyWith(panel: ForumPanel.main));
      expect(
        shell.selectedTabIn(ForumPanel.secondary)?.currentContent.isNewTab,
        isTrue,
      );

      shell.createTab(panel: ForumPanel.secondary);
      final secondaryId = shell.activeTabId;
      final workspace = shell.currentWorkspace!;
      final restored = ForumWorkspace.tryFromJson(
        jsonDecode(jsonEncode(workspace.toJson())),
      )!;
      expect(restored, workspace);
      expect(restored.selectedTabIn(ForumPanel.main)?.id, topic.id);
      expect(restored.selectedTabIn(ForumPanel.secondary)?.id, secondaryId);

      shell.closeTab(topic.id);
      expect(shell.activeTabId, secondaryId);
      expect(shell.reopenClosedTab(topic.id), isTrue);
      expect(shell.activeTab, beforeMove.copyWith(panel: ForumPanel.main));
      expect(shell.topicScrollPostNumber(42), 7);
    },
  );

  test('closing other tabs is confined to the requested panel', () {
    final mainId = shell.activeTabId!;
    _openTopicTab(shell, _topic);
    final first = shell.activeTabId!;
    _openTopicTab(shell, _otherTopic);
    shell.closeOtherTabs(first, panel: ForumPanel.secondary);
    expect(shell.tabsForCurrentForum.map((tab) => tab.id), [mainId, first]);
  });

  test(
    'opening content in the secondary Start page works at the tab limit',
    () {
      while (shell.canCreateTab) {
        shell.createTab(panel: ForumPanel.main);
      }
      final before = shell.currentWorkspace;

      expect(
        shell.openContentInPanel(
          ContentRoute.topic(
            topicId: _topic.id,
            slug: _topic.slug,
            title: _topic.title,
          ),
          panel: ForumPanel.secondary,
        ),
        TabOpenResult.opened,
      );

      expect(shell.selectedTabIn(ForumPanel.main), before!.activeTab);
      expect(
        shell.selectedTabIn(ForumPanel.secondary)?.currentContent.topicId,
        42,
      );
      expect(shell.tabsForCurrentForum, hasLength(ForumWorkspace.maximumTabs));
    },
  );

  test('explicit new tabs at the limit preserve every existing document', () {
    while (shell.canCreateTab) {
      shell.createTab();
    }
    final workspace = shell.currentWorkspace;
    _openTopicTab(shell, _topic);
    expect(shell.currentWorkspace, workspace);
  });

  testWidgets(
    'middle-click explains the tab limit and opens after closing a tab',
    (tester) async {
      final main = shell.activeTabId!;
      while (shell.canCreateTab) {
        shell.createTab(panel: ForumPanel.secondary);
      }
      final extraTab = shell.activeTabId!;
      shell.selectTab(main);
      await _pump(tester, shell);
      final workspace = shell.currentWorkspace;
      final row = find.byKey(const ValueKey('topic-card-42')).first;

      await tester.tap(
        row,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await tester.pumpAndSettle();

      expect(shell.currentWorkspace, workspace);
      expect(find.text('Close a tab before opening another.'), findsOneWidget);

      shell.closeTab(extraTab);
      await tester.pumpAndSettle();
      await tester.tap(
        row,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await tester.pumpAndSettle();
      expect(shell.activeTab?.panel, ForumPanel.main);
      expect(shell.activeTabId, main);
      expect(shell.tabsForCurrentForum.last.currentContent.topicId, 42);
      shell.selectTab(shell.tabsForCurrentForum.last.id);
      await tester.pumpAndSettle();
      expect(find.text('Content for 42', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('both visible topics stay subscribed when either panel is focused', () {
    _openTopicTab(shell, _topic);
    final first = shell.activeTabId!;
    shell.moveTabToPanel(first, ForumPanel.main);
    _openTopicTab(shell, _otherTopic);
    final tracker = FakeSiteTracker.built.last;
    expect(tracker.watchedChannels, containsAll(['/topic/42', '/topic/43']));
    shell.selectTab(first);
    expect(tracker.watchedChannels, containsAll(['/topic/42', '/topic/43']));
    shell.closeTab(first);
    expect(tracker.watchedChannels, ['/topic/43']);
  });

  test('reading an inactive panel never changes input focus', () {
    final mainId = shell.activeTabId!;
    _openTopicTab(shell, _topic);
    final readerId = shell.activeTabId!;
    final main = shell.tabContext(mainId);
    final reader = shell.tabContext(readerId);
    expect(main.currentContent?.id, 'latest');
    expect(reader.currentContent?.topicId, 42);
    expect(shell.activeTabId, readerId);
    expect(shell.tabContext(null).currentContent, isNull);
    expect(shell.activeTabId, readerId);
  });

  test(
    'delayed panel commands keep their tab after focus and panel moves',
    () async {
      final mainId = shell.activeTabId!;
      final main = shell.tabContext(mainId);
      final release = Completer<void>();
      final pending = release.future.then(
        (_) => main.openTopicFromList(_otherTopic),
      );
      _openTopicTab(shell, _topic);
      final readerId = shell.activeTabId!;
      shell.moveTabToPanel(mainId, ForumPanel.secondary);
      shell.selectTab(readerId);
      release.complete();
      expect(await pending, TabOpenResult.opened);
      expect(main.currentContent?.topicId, 43);
      expect(shell.activeTabId, readerId);
      expect(shell.currentContent?.topicId, 42);
    },
  );

  test(
    'closed tabs and retired accounts reject captured panel commands',
    () async {
      _openTopicTab(shell, _topic);
      final closed = shell.tabContext(shell.activeTabId);
      shell.closeTab(closed.tabId!);
      final route = shell.currentContent;
      expect(closed.isCurrent, isFalse);
      expect(
        closed.openTopicFromList(_otherTopic),
        isNot(TabOpenResult.opened),
      );
      final retired = shell.focusedTabContext;
      shell.lifecycle.invalidate(shell.currentInstance!.url);
      expect(retired.isCurrent, isFalse);
      await retired.loadFeed('latest', force: true);
      expect(
        retired.openTopicFromList(_otherTopic),
        isNot(TabOpenResult.opened),
      );
      expect(shell.currentContent, same(route));
    },
  );

  testWidgets(
    'reply and quote retain their source while the other reader is focused',
    (tester) async {
      _openTopicTab(shell, _topic);
      final sourceId = shell.activeTabId!;
      shell.moveTabToPanel(sourceId, ForumPanel.main);
      await shell.loadTopic(42, _topic.slug);
      shell.store.put(
        shell.currentInstance!.url,
        const TopicDetail(
          id: 42,
          title: 'Panel topic',
          stream: [42],
          canCreatePost: true,
        ),
      );
      final source = shell.tabContext(sourceId);
      _openTopicTab(shell, _otherTopic);
      final focused = shell.activeTabId;
      source.openReply(replyToPostNumber: 1, replyToUsername: 'reader');
      final composer = shell.visibleComposer!;
      expect((composer.target as ExistingTopicComposerTarget?)?.topicId, 42);
      expect(composer.target.tabId, sourceId);
      await source.openQuote(
        const Post(
          id: 42,
          postNumber: 1,
          username: 'reader',
          cooked: '<p>Quoted</p>',
        ),
        '[quote]Quoted[/quote]',
      );
      expect(composer.value.text, contains('Quoted'));
      expect(shell.activeTabId, focused);
      expect(shell.currentContent?.topicId, 43);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
    },
  );

  test(
    'closing the unfocused selected tab activates its neighbour in place',
    () {
      final main = shell.activeTabId!;
      _openTopicTab(shell, _topic);
      _openTopicTab(shell, _otherTopic);
      final closing = shell.activeTabId!;
      _openTopicTab(shell, _topic);
      final neighbour = shell.activeTabId!;
      shell.selectTab(closing);
      shell.selectTab(main);
      expect(FakeSiteTracker.built.last.watchedChannels, ['/topic/43']);

      shell.closeTab(closing);

      expect(shell.activeTabId, main);
      expect(shell.selectedTabIn(ForumPanel.secondary)?.id, neighbour);
      expect(FakeSiteTracker.built.last.watchedChannels, ['/topic/42']);
    },
  );

  testWidgets(
    'both panels keep their content when focus moves and a panel minimizes',
    (tester) async {
      _openTopicTab(shell, _topic);
      final readerTab = shell.activeTabId!;
      await _pump(tester, shell);
      expect(find.byType(TopicListView), findsOneWidget);
      expect(find.byType(TopicView), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-view-options')), findsNothing);
      expect(find.byTooltip('Hide split view'), findsNWidgets(2));
      expect(find.byTooltip('Switch panel positions'), findsNothing);
      final reader = tester.state(find.byType(TopicView));
      final main = shell.selectedTabIn(ForumPanel.main)!.id;
      shell.selectTab(main);
      await tester.pumpAndSettle();
      expect(find.text('Content for 42', findRichText: true), findsOneWidget);
      expect(tester.state(find.byType(TopicView)), same(reader));
      final list = tester.getRect(_mainPanel);

      await tester.tap(
        find.byKey(const ValueKey('panel-split-view-secondary')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TopicView), findsNothing);
      expect(
        tester.state(find.byType(TopicView, skipOffstage: false)),
        same(reader),
      );
      expect(tester.getRect(_mainPanel).left, list.left);
      expect(tester.getRect(_mainPanel).right, 1200);
      expect(shell.activeTabId, main);

      _toggleSplit(tester);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TopicView)), same(reader));
      expect(tester.getRect(_mainPanel), list);
      expect(shell.activeTabId, main);
      expect(shell.selectedTabIn(ForumPanel.secondary)?.id, readerTab);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an unused panel shows a Start page and can take focus', (
    tester,
  ) async {
    final main = shell.activeTab!;
    final start = shell.selectedTabIn(ForumPanel.secondary)!;
    await _pump(tester, shell);
    expect(start.currentContent.isNewTab, isTrue);
    expect(find.text('Secondary panel'), findsNothing);
    expect(find.text('Drag a tab here or open a new tab.'), findsNothing);
    expect(
      find.descendant(of: _secondaryPanel, matching: find.byType(NewTabPage)),
      findsOneWidget,
    );
    expect(shell.activeTabId, main.id);

    await tester.tap(find.byKey(const ValueKey('panel-split-view-main')));
    await tester.pumpAndSettle();
    expect(shell.activeTabId, start.id);
    expect(find.byType(NewTabPage), findsOneWidget);
    expect(shell.currentWorkspace!.tabById(main.id), main);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Start page links navigate in their own panel', (tester) async {
    final start = shell.selectedTabIn(ForumPanel.secondary)!;
    await _pump(tester, shell);
    shell.openTopicFromList(_topic);
    await tester.pumpAndSettle();
    shell.handleBack(canReturnToSidebar: false);
    await tester.pumpAndSettle();
    final main = shell.activeTab!;

    await tester.tap(
      find.descendant(of: _secondaryPanel, matching: find.text('Topics')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: _secondaryPanel,
        matching: find.byKey(const ValueKey('topic-card-42')),
      ),
    );
    await tester.pumpAndSettle();

    expect(shell.activeTabId, start.id);
    expect(
      shell.selectedTabIn(ForumPanel.secondary)?.currentContent.topicId,
      42,
    );
    expect(shell.currentWorkspace!.tabById(main.id), main);
    expect(find.text('Content for 42', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a topic from the list keeps the other panel minimized', (
    tester,
  ) async {
    _openTopicTab(shell, _topic);
    final readerTab = shell.activeTabId!;
    shell.selectTab(shell.selectedTabIn(ForumPanel.main)!.id);
    await _pump(tester, shell);
    await tester.tap(find.byKey(const ValueKey('panel-split-view-secondary')));
    await tester.pumpAndSettle();
    expect(find.byType(TopicView), findsNothing);

    await tester.tap(find.byKey(const ValueKey('topic-card-43')).first);
    await tester.pumpAndSettle();

    expect(shell.activeTabId, shell.selectedTabIn(ForumPanel.main)?.id);
    expect(shell.selectedTabIn(ForumPanel.secondary)?.id, readerTab);
    expect(find.text('Content for 43', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets(
      'either panel disappears fully and restores retained tabs in $direction',
      (tester) async {
        _openTopicTab(shell, _topic, panel: ForumPanel.main);
        final first = shell.activeTabId!;
        _openTopicTab(shell, _otherTopic, panel: ForumPanel.main);
        final second = shell.activeTabId!;
        await _pump(tester, shell, direction: direction);
        final reader = tester.state(find.byType(TopicView).first);
        final before = tester.getRect(_mainPanel);
        await tester.tap(find.byKey(const ValueKey('panel-split-view-main')));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(_secondaryPanel),
          const Rect.fromLTWH(0, 0, 1200, 850),
        );
        expect(
          find.byKey(const ValueKey('main-panel-resize-handle')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey('panel-split-view-secondary')),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(_mainPanel), before);
        expect(shell.selectedTabIn(ForumPanel.main)?.id, second);
        expect(tester.state(find.byType(TopicView).first), same(reader));
        shell.selectTab(first);
        await tester.pumpAndSettle();
        expect(find.text('Content for 42', findRichText: true), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('minimizing and restoring move no document to another parent', (
    tester,
  ) async {
    _openTopicTab(shell, _topic);
    await _pump(tester, shell);
    // Reparenting a document would rebuild every widget in it that reads an
    // inherited value, so each panel must keep its chain of ancestors.
    List<Element> ancestry(ForumPanel panel) {
      final chain = <Element>[];
      tester
          .element(
            find.byKey(
              ValueKey('desktop-panel-${panel.name}'),
              skipOffstage: false,
            ),
          )
          .visitAncestorElements((ancestor) {
            if (ancestor.widget is DesktopPanels) return false;
            chain.add(ancestor);
            return true;
          });
      return chain;
    }

    final before = {
      for (final panel in ForumPanel.values) panel: ancestry(panel),
    };
    for (final action in [
      'panel-split-view-secondary',
      'toggle-split',
      'panel-split-view-main',
      'panel-split-view-secondary',
    ]) {
      if (action == 'toggle-split') {
        _toggleSplit(tester);
      } else {
        await tester.tap(find.byKey(ValueKey(action)));
      }
      await tester.pumpAndSettle();
      for (final panel in ForumPanel.values) {
        final after = ancestry(panel);
        expect(after, hasLength(before[panel]!.length), reason: action);
        for (var index = 0; index < after.length; index++) {
          expect(
            after[index],
            same(before[panel]![index]),
            reason: '$action: ${after[index].widget.runtimeType} of $panel',
          );
        }
      }
    }
    expect(tester.takeException(), isNull);
  });

  for (final panel in ForumPanel.values) {
    testWidgets('folding $panel retains document paint during motion', (
      tester,
    ) async {
      _openTopicTab(shell, _topic);
      await _pump(tester, shell);
      final documents = tester
          .renderObjectList<RenderObject>(find.byType(MainContent))
          .toSet();
      final paints = <RenderObject, int>{};
      final previous = debugOnProfilePaint;
      debugOnProfilePaint = (object) {
        previous?.call(object);
        if (documents.contains(object)) {
          paints.update(object, (count) => count + 1, ifAbsent: () => 1);
        }
      };

      Future<void> expectRetainedPaint() async {
        // Allow the initial width change and first visible motion frame (a
        // restored panel starts fully transparent). The remaining fold
        // frames should only composite document layers.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        paints.clear();
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(paints, isEmpty);
        await tester.pumpAndSettle();
      }

      try {
        await tester.tap(
          find.byKey(ValueKey('panel-split-view-${panel.name}')),
        );
        await expectRetainedPaint();
        _toggleSplit(tester);
        await expectRetainedPaint();
      } finally {
        debugOnProfilePaint = previous;
      }
      expect(find.byType(TopicView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the secondary panel folds away as the main panel opens up', (
    tester,
  ) async {
    _openTopicTab(shell, _topic);
    await _pump(tester, shell);
    final reader = tester.getRect(_secondaryPanel);
    await tester.tap(find.byKey(const ValueKey('panel-split-view-secondary')));
    // The frame that lays the panels out anew, then the motion's first tick:
    // nothing has moved yet.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getRect(_secondaryPanel), reader);

    await tester.pump(const Duration(milliseconds: 100));
    final folding = tester.getRect(_secondaryPanel);
    expect(find.byType(TopicView), findsOneWidget);
    expect(folding.left, greaterThan(reader.left));
    expect(folding.left, lessThan(1200 + workspacePanelGap));
    final list = tester.renderObject<RenderClipRRect>(
      find.ancestor(of: _mainPanel, matching: find.byType(ClipRRect)).first,
    );
    // The list's revealed edge keeps one gap from the folding reader's edge.
    expect(
      list.clipper!.getClip(list.size).right,
      closeTo(folding.left - workspacePanelGap, 0.01),
    );

    await tester.pumpAndSettle();
    expect(find.byType(TopicView), findsNothing);
    expect(tester.getRect(_mainPanel).right, 1200);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a restored panel slides back in before the seam returns', (
    tester,
  ) async {
    _openTopicTab(shell, _topic);
    await _pump(tester, shell);
    final reader = tester.getRect(_secondaryPanel);
    final seam = find.byKey(const ValueKey('main-panel-resize-handle'));
    expect(seam, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('panel-split-view-secondary')));
    await tester.pumpAndSettle();
    expect(seam, findsNothing);

    _toggleSplit(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final folded = tester.getRect(_secondaryPanel);
    expect(folded.left, 1200 + workspacePanelGap);
    await tester.pump(const Duration(milliseconds: 100));
    final opening = tester.getRect(_secondaryPanel);
    expect(opening.left, inExclusiveRange(reader.left, folded.left));
    expect(seam, findsNothing);
    // The list keeps its wide layout until the motion settles, cut at one
    // gap from the returning reader, so no hole opens between them.
    expect(tester.getRect(_mainPanel).right, 1200);
    final list = tester.renderObject<RenderClipRRect>(
      find.ancestor(of: _mainPanel, matching: find.byType(ClipRRect)).first,
    );
    expect(
      list.clipper!.getClip(list.size).right,
      closeTo(opening.left - workspacePanelGap, 0.01),
    );

    await tester.pumpAndSettle();
    expect(tester.getRect(_secondaryPanel), reader);
    expect(tester.getRect(_mainPanel).right, reader.left - workspacePanelGap);
    expect(seam, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with reduced motion a panel minimizes and restores at once', (
    tester,
  ) async {
    _openTopicTab(shell, _topic);
    await _pump(tester, shell, reduceMotion: true);
    final reader = tester.getRect(_secondaryPanel);
    await tester.tap(find.byKey(const ValueKey('panel-split-view-secondary')));
    await tester.pump();
    expect(find.byType(TopicView), findsNothing);
    expect(tester.getRect(_mainPanel).right, 1200);

    _toggleSplit(tester);
    await tester.pump();
    expect(find.byType(TopicView), findsOneWidget);
    expect(tester.getRect(_secondaryPanel), reader);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restoration hydrates both selected tabs while main has focus', (
    tester,
  ) async {
    final main = shell.activeTabId!;
    _openTopicTab(shell, _topic);
    final topic = shell.activeTabId!;
    shell.selectTab(main);
    final restored = ShellController(
      instanceStore: FakeInstanceStore([instance('panels.example')]),
      api: api,
      ownsApi: false,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore([shell.currentWorkspace!]),
      trackers: FakeSiteTracker.factory,
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.activeTabId, main, reason: 'before mounting panels');
    await _pump(tester, restored);
    expect(restored.activeTabId, main);
    expect(restored.selectedTabIn(ForumPanel.secondary)?.id, topic);
    expect(find.byType(TopicListView), findsOneWidget);
    expect(find.text('Content for 42', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a list keeps its heading and filter ownership with creation in the title bar',
    (tester) async {
      await _pump(tester, shell);
      final main = shell.activeTabId!;
      shell.openContentInNewTab(
        const ContentRoute(
          destination: PageDestination(CorePage.categories),
          title: 'All categories',
          icon: DIcons.folder,
        ),
        panel: ForumPanel.secondary,
        rootDestinationId: 'all-categories',
      );
      final secondary = shell.activeTabId!;
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('topic-list-title')))
            .data,
        'Latest topics',
      );
      expect(find.byKey(const ValueKey('new-topic-button')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('topic-list-filter')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('topic-filter-input')),
          matching: find.byType(TextField),
        ),
        'status:open ',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-filter-apply')));
      await tester.pumpAndSettle();

      expect(shell.activeTabId, main);
      expect(shell.currentContent?.topicFilterQuery, 'status:open');
      expect(shell.selectedTabIn(ForumPanel.secondary)?.id, secondary);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('primary click reuses the current tab even at the limit', (
    tester,
  ) async {
    final main = shell.activeTabId;
    while (shell.canCreateTab) {
      shell.createTab(panel: ForumPanel.secondary);
    }
    final secondary = shell.activeTab;
    shell.selectTab(main!);
    await _pump(tester, shell);

    await tester.tap(
      find.byKey(const ValueKey('topic-card-42')).first,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(shell.activeTabId, main);
    expect(shell.currentContent?.topicId, 42);
    expect(shell.tabsForCurrentForum, hasLength(ForumWorkspace.maximumTabs));
    expect(shell.selectedTabIn(ForumPanel.main)?.id, main);
    expect(shell.selectedTabIn(ForumPanel.secondary)?.id, secondary!.id);
    expect(find.text('Close a tab before opening another.'), findsNothing);
    expect(find.text('Content for 42', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('middle click opens a new tab in the current panel', (
    tester,
  ) async {
    await _pump(tester, shell);
    final main = shell.activeTabId;
    await tester.tap(
      find.descendant(of: _mainPanel, matching: find.text(_topic.title)),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await tester.pumpAndSettle();
    expect(shell.activeTabId, main);
    expect(shell.tabsForCurrentForum.last.panel, ForumPanel.main);
    expect(shell.tabsForCurrentForum.last.currentContent.topicId, 42);
    expect(shell.currentWorkspace?.tabById(main!)?.currentContent.id, 'latest');
    expect(tester.takeException(), isNull);
  });

  for (final pressDuration in [1, 50, 250]) {
    testWidgets(
      'topic click survives panel activation after $pressDuration ms',
      (tester) async {
        _openTopicTab(shell, _topic);
        final reader = shell.activeTab;
        final main = shell.selectedTabIn(ForumPanel.main)!.id;
        await _pump(tester, shell);
        final row = find.byKey(const ValueKey('topic-card-43'));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(1190, 840));
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(row));
        await tester.pump(const Duration(milliseconds: 40));
        await mouse.down(tester.getCenter(row));
        await tester.pump(Duration(milliseconds: pressDuration));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(shell.activeTabId, main);
        expect(shell.currentContent?.topicId, 43);
        expect(shell.selectedTabIn(ForumPanel.secondary)?.id, reader!.id);
        expect(
          shell.selectedTabIn(ForumPanel.secondary)?.currentContent.topicId,
          42,
        );
        expect(shell.selectedTabIn(ForumPanel.main)?.id, main);
        expect(shell.tabsForCurrentForum, hasLength(3));
        expect(find.text('Content for 43', findRichText: true), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('dragging the last tab leaves a Start page in each panel', (
    tester,
  ) async {
    await _pump(tester, shell);
    final id = shell.activeTabId!;
    Future<void> moveToPanel(Finder target) async {
      final tab = find.byKey(ValueKey('forum-tab-$id'));
      final gesture = await tester.startGesture(
        tester.getCenter(tab),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(target));
      await tester.pumpAndSettle();
      final indicator = find.byKey(
        const ValueKey('forum-tab-drop-placeholder'),
      );
      expect(indicator, findsOneWidget);
      expect(tester.getRect(indicator).width, 3);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(indicator, findsNothing);
    }

    await moveToPanel(_secondaryPanel);
    await tester.pumpAndSettle();
    expect(shell.activeTab?.panel, ForumPanel.secondary);
    expect(shell.activeTabId, id);
    final main = shell.selectedTabIn(ForumPanel.main)!;
    expect(main.currentContent.title, 'Start page');
    expect(main.currentContent.icon, DIcons.house);
    final startTab = find.byKey(ValueKey('forum-tab-${main.id}'));
    expect(
      find.descendant(of: startTab, matching: find.text('Start page')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: startTab,
        matching: find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.house,
        ),
      ),
      findsOneWidget,
    );

    await moveToPanel(startTab);
    await tester.pumpAndSettle();
    expect(shell.activeTab?.panel, ForumPanel.main);
    expect(shell.activeTabId, id);
    expect(
      shell.selectedTabIn(ForumPanel.secondary)?.currentContent.isNewTab,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a Start page panel previews an incoming tab and clears on drag exit',
    (tester) async {
      await _pump(tester, shell);
      final original = shell.currentWorkspace!;
      final source = find.byKey(ValueKey('forum-tab-${shell.activeTabId}'));
      final gesture = await tester.startGesture(
        tester.getCenter(source),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(_secondaryPanel));
      await tester.pumpAndSettle();
      final placeholder = find.byKey(
        const ValueKey('forum-tab-drop-placeholder'),
      );
      expect(placeholder, findsOneWidget);
      expect(tester.getRect(placeholder).bottom, lessThan(100));
      expect(shell.currentWorkspace, original);

      await gesture.moveTo(const Offset(-20, -20));
      await tester.pumpAndSettle();
      expect(placeholder, findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(shell.currentWorkspace, original);
      expect(tester.takeException(), isNull);
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets('the placeholder matches the insertion position in $direction', (
      tester,
    ) async {
      final initial = shell.activeTabId!;
      shell.openContentInNewTab(
        const ContentRoute(
          destination: ExtensionDestination('panel-a'),
          title: 'A',
          icon: DIcons.tag,
        ),
      );
      final first = shell.activeTabId!;
      shell.closeTab(initial);
      shell.openContentInNewTab(
        const ContentRoute(
          destination: ExtensionDestination('panel-b'),
          title: 'B',
          icon: DIcons.tag,
        ),
      );
      final second = shell.activeTabId!;
      _openTopicTab(shell, _topic);
      final incoming = shell.activeTabId!;
      await _pump(tester, shell, direction: direction);
      final source = find.byKey(ValueKey('forum-tab-$incoming'));
      final target = find.byKey(ValueKey('forum-tab-$second'));
      final barRect = tester.getRect(
        find.ancestor(of: target, matching: find.byType(ForumTabsBar)),
      );
      final targetRect = tester.getRect(target);
      final destination = Offset(
        direction == TextDirection.ltr
            ? targetRect.left + 2
            : targetRect.right - 2,
        targetRect.center.dy,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(source),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(destination);
      await tester.pumpAndSettle();
      final placeholder = find.byKey(
        const ValueKey('forum-tab-drop-placeholder'),
      );
      expect(placeholder, findsOneWidget);
      final previewRect = tester.getRect(placeholder);
      expect(previewRect.width, 3);
      expect(previewRect.height, 28);
      expect(
        tester
            .widget<Container>(
              find.descendant(
                of: placeholder,
                matching: find.byType(Container),
              ),
            )
            .decoration,
        isA<BoxDecoration>().having(
          (decoration) => decoration.color,
          'color',
          Theme.of(tester.element(placeholder)).colorScheme.primary,
        ),
      );
      final firstRect = tester.getRect(
        find.byKey(ValueKey('forum-tab-$first')),
      );
      final secondRect = tester.getRect(target);
      if (direction == TextDirection.ltr) {
        expect(previewRect.left, greaterThan(firstRect.right));
        expect(previewRect.right, lessThan(secondRect.left));
      } else {
        expect(previewRect.right, lessThan(firstRect.left));
        expect(previewRect.left, greaterThan(secondRect.right));
      }
      // Moving within the same insertion region must not chase the shifted tabs.
      await gesture.moveTo(destination + const Offset(1, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(placeholder), previewRect);

      // Cross several child hit targets, then return to the original slot.
      await gesture.moveTo(
        Offset(
          direction == TextDirection.ltr ? barRect.right - 2 : barRect.left + 2,
          destination.dy,
        ),
      );
      await tester.pumpAndSettle();
      final appended = tester.getRect(placeholder);
      final last = tester.getRect(target);
      expect(
        direction == TextDirection.ltr
            ? appended.left > last.right
            : appended.right < last.left,
        isTrue,
      );
      await gesture.moveTo(
        Offset(
          direction == TextDirection.ltr ? barRect.left + 2 : barRect.right - 2,
          destination.dy,
        ),
      );
      await tester.pumpAndSettle();
      final prepended = tester.getRect(placeholder);
      final leading = tester.getRect(find.byKey(ValueKey('forum-tab-$first')));
      expect(
        direction == TextDirection.ltr
            ? prepended.right < leading.left
            : prepended.left > leading.right,
        isTrue,
      );
      await gesture.moveTo(destination);
      await tester.pumpAndSettle();
      expect(tester.getRect(placeholder), previewRect);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(placeholder, findsNothing);
      expect(
        shell.currentWorkspace!.tabsIn(ForumPanel.main).map((tab) => tab.id),
        [first, incoming, second],
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dropping over panel content previews an appended tab', (
    tester,
  ) async {
    final original = shell.activeTabId!;
    _openTopicTab(shell, _topic);
    final incoming = shell.activeTabId!;
    await _pump(tester, shell);
    final source = find.byKey(ValueKey('forum-tab-$incoming'));
    final gesture = await tester.startGesture(
      tester.getCenter(source),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(TopicListView)));
    await tester.pumpAndSettle();
    final placeholder = find.byKey(
      const ValueKey('forum-tab-drop-placeholder'),
    );
    expect(placeholder, findsOneWidget);
    expect(
      tester.getRect(placeholder).left,
      greaterThan(
        tester.getRect(find.byKey(ValueKey('forum-tab-$original'))).right,
      ),
    );
    final tabRect = tester.getRect(find.byKey(ValueKey('forum-tab-$original')));
    await gesture.moveTo(Offset(tabRect.left + 2, tabRect.center.dy));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(placeholder).right,
      lessThan(
        tester.getRect(find.byKey(ValueKey('forum-tab-$original'))).left,
      ),
    );
    await gesture.moveTo(tester.getCenter(find.byType(TopicListView)));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(placeholder, findsNothing);
    expect(
      shell.currentWorkspace!.tabsIn(ForumPanel.main).map((tab) => tab.id),
      [original, incoming],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tabs select independently and move into an occupied strip', (
    tester,
  ) async {
    final original = shell.activeTabId!;
    shell.createTab();
    final second = shell.activeTabId!;
    _openTopicTab(shell, _topic);
    final reader = shell.activeTabId!;
    await _pump(tester, shell);
    await tester.tap(find.byKey(ValueKey('forum-tab-$original')));
    await tester.pumpAndSettle();
    expect(shell.activeTabId, original);
    expect(shell.selectedTabIn(ForumPanel.secondary)?.id, reader);
    await tester.tap(find.byKey(ValueKey('forum-tab-$second')));
    await tester.pumpAndSettle();
    expect(shell.activeTabId, second);
    final source = find.byKey(ValueKey('forum-tab-$second'));
    final target = find.byKey(ValueKey('forum-tab-$reader'));
    await tester.dragFrom(
      tester.getCenter(source),
      tester.getCenter(target) - tester.getCenter(source),
    );
    await tester.pumpAndSettle();
    expect(shell.activeTabId, second);
    expect(shell.activeTab?.panel, ForumPanel.secondary);
    expect(shell.selectedTabIn(ForumPanel.main)?.id, original);
    expect(shell.currentWorkspace!.tabsIn(ForumPanel.secondary), hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('seam resizing keeps tab controls and reader structure mounted', (
    tester,
  ) async {
    _openTopicTab(shell, _topic);
    await _pump(tester, shell);
    final controls = tester.elementList(find.byType(DDocumentTab)).toSet();
    final stream = tester.element(find.byType(TopicPostSliver));
    final retained = {...controls, stream};
    expect(controls, hasLength(3));
    final rebuilt = <Element>{};
    final reader = tester.state(find.byType(TopicView));
    final before = tester.getSize(_mainPanel).width;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (retained.contains(element)) rebuilt.add(element);
    };
    try {
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey('main-panel-resize-handle')),
        ),
      );
      for (var frame = 0; frame < 10; frame++) {
        await gesture.moveBy(const Offset(12, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      expect(rebuilt, isEmpty);
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }
    await tester.pumpAndSettle();
    expect(tester.getSize(_mainPanel).width, greaterThan(before + 90));
    expect(tester.state(find.byType(TopicView)), same(reader));
    expect(tester.element(find.byType(TopicPostSliver)), same(stream));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging the divider changes both panel widths', (tester) async {
    _openTopicTab(shell, _topic);
    await _pump(tester, shell);
    final handle = find.byKey(const ValueKey('main-panel-resize-handle'));
    expect(tester.getRect(_mainPanel).width, 400);
    expect(tester.getSize(handle), const Size(4, 36));
    await tester.drag(handle, const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(tester.getRect(_mainPanel).width, 480);
    expect(tester.getRect(_secondaryPanel).width, 708);
    expect(tester.takeException(), isNull);
  });

  for (final panel in ForumPanel.values) {
    testWidgets('reordering within ${panel.name} shows an insertion bar', (
      tester,
    ) async {
      final first = shell.selectedTabIn(panel)!.id;
      shell.createTab(panel: panel);
      final second = shell.selectedTabIn(panel)!.id;
      await _pump(tester, shell);

      final source = find.byKey(ValueKey('forum-tab-$first'));
      final target = find.byKey(ValueKey('forum-tab-$second'));
      final gesture = await tester.startGesture(
        tester.getCenter(source),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      final targetRect = tester.getRect(target);
      final sourceRect = tester.getRect(source);
      await gesture.moveTo(Offset(targetRect.right - 2, targetRect.center.dy));
      await tester.pumpAndSettle();
      final indicator = find.byKey(
        const ValueKey('forum-tab-drop-placeholder'),
      );
      expect(indicator, findsOneWidget);
      expect(tester.getRect(indicator).left, greaterThan(targetRect.right));
      expect(tester.getRect(target), targetRect);
      expect(tester.getRect(source), sourceRect);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(indicator, findsNothing);
      expect(shell.currentWorkspace!.tabsIn(panel).map((tab) => tab.id), [
        second,
        first,
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reordering within ${panel.name} keeps the dragged tab in '
        'place and drops past a whole neighbour', (tester) async {
      final first = shell.selectedTabIn(panel)!.id;
      shell.createTab(panel: panel);
      final second = shell.selectedTabIn(panel)!.id;
      shell.createTab(panel: panel);
      final third = shell.selectedTabIn(panel)!.id;
      await _pump(tester, shell);

      Rect rectOf(String id) =>
          tester.getRect(find.byKey(ValueKey('forum-tab-$id')));
      final indicator = find.byKey(
        const ValueKey('forum-tab-drop-placeholder'),
      );
      final gesture = await tester.startGesture(
        rectOf(second).center,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      // Pressing selects the tab, which widens it for its close action.
      final firstRect = rectOf(first);
      final secondRect = rectOf(second);
      final thirdRect = rectOf(third);

      Future<void> hover(double dx) async {
        await gesture.moveTo(Offset(dx, secondRect.center.dy));
        await tester.pumpAndSettle();
      }

      expect(
        find.ancestor(
          of: find.byKey(ValueKey('forum-tab-$second')),
          matching: find.byWidgetPredicate(
            (widget) => widget is Opacity && widget.opacity == 0,
          ),
        ),
        findsNothing,
      );

      // Its own slot would not move it.
      await hover(secondRect.left + 2);
      expect(indicator, findsNothing);
      await hover(secondRect.right - 2);
      expect(indicator, findsNothing);

      // Either half of a neighbour answers that neighbour's far side. A
      // scrolling strip centers the pressed tab and clips its neighbours, so
      // each half is sampled where the strip still shows it.
      for (final dx in [
        firstRect.right - 2,
        firstRect.left + firstRect.width / 4,
      ]) {
        await hover(dx);
        expect(indicator, findsOneWidget);
        expect(tester.getRect(indicator).right, lessThan(firstRect.left));
      }
      for (final dx in [
        thirdRect.left + 2,
        thirdRect.right - thirdRect.width / 4,
      ]) {
        await hover(dx);
        expect(indicator, findsOneWidget);
        expect(tester.getRect(indicator).left, greaterThan(thirdRect.right));
      }

      await hover(thirdRect.left + 2);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(shell.currentWorkspace!.tabsIn(panel).map((tab) => tab.id), [
        first,
        third,
        second,
      ]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'dragging the divider after an edge resize resets the preferred split',
    (tester) async {
      final frame = ValueNotifier<Rect?>(
        const Rect.fromLTWH(100, 0, 1200, 850),
      );
      addTearDown(frame.dispose);
      _openTopicTab(shell, _topic);
      await _pump(tester, shell, windowFrame: frame);
      frame.value = const Rect.fromLTWH(100, 0, 1160, 850);
      tester.view.physicalSize = const Size(1160, 850);
      await tester.pumpAndSettle();
      expect(tester.getRect(_mainPanel).width, 360);

      final handle = find.byKey(const ValueKey('main-panel-resize-handle'));
      await tester.drag(handle, const Offset(50, 0));
      await tester.pumpAndSettle();

      expect(tester.getRect(_mainPanel).width, 410);
      expect(tester.getRect(_secondaryPanel).width, 738);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'divider can return exactly to its preferred width after edge resize',
    (tester) async {
      final frame = ValueNotifier<Rect?>(
        const Rect.fromLTWH(100, 0, 1200, 850),
      );
      addTearDown(frame.dispose);
      _openTopicTab(shell, _topic);
      await _pump(tester, shell, windowFrame: frame);
      frame.value = const Rect.fromLTWH(100, 0, 1160, 850);
      tester.view.physicalSize = const Size(1160, 850);
      await tester.pumpAndSettle();
      expect(tester.getRect(_mainPanel).width, 360);

      final handle = find.byKey(const ValueKey('main-panel-resize-handle'));
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.getRect(_mainPanel).width, 400);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('right-edge resize shrinks main to 320 then hides it entirely', (
    tester,
  ) async {
    final frame = ValueNotifier<Rect?>(const Rect.fromLTWH(100, 0, 1200, 850));
    addTearDown(frame.dispose);
    _openTopicTab(shell, _topic);
    shell.selectTab(shell.selectedTabIn(ForumPanel.main)!.id);
    await _pump(tester, shell, windowFrame: frame);

    frame.value = const Rect.fromLTWH(100, 0, 1160, 850);
    tester.view.physicalSize = const Size(1160, 850);
    await tester.pumpAndSettle();
    expect(tester.getRect(_mainPanel).width, 360);
    expect(tester.getRect(_secondaryPanel).width, 788);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('main-panel-resize-handle')))
          .center
          .dx,
      366,
    );

    frame.value = const Rect.fromLTWH(100, 0, 1120, 850);
    tester.view.physicalSize = const Size(1120, 850);
    await tester.pumpAndSettle();
    expect(tester.getRect(_mainPanel).width, 320);
    expect(tester.getRect(_secondaryPanel).width, 788);

    frame.value = const Rect.fromLTWH(100, 0, 1119, 850);
    tester.view.physicalSize = const Size(1119, 850);
    await tester.pumpAndSettle();
    expect(_mainPanel, findsNothing);
    expect(
      tester.getRect(_secondaryPanel),
      const Rect.fromLTWH(0, 0, 1119, 850),
    );
    expect(
      find.byKey(const ValueKey('panel-split-view-secondary')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('main-panel-resize-handle')),
      findsNothing,
    );
    expect(shell.activeTab?.panel, ForumPanel.secondary);

    // A collapsing navigation sidebar can widen the document workspace
    // even as the outer window keeps getting narrower.
    frame.value = const Rect.fromLTWH(100, 0, 1099, 850);
    tester.view.physicalSize = const Size(1051, 850);
    await tester.pumpAndSettle();
    expect(_mainPanel, findsNothing);

    frame.value = const Rect.fromLTWH(100, 0, 1200, 850);
    tester.view.physicalSize = const Size(1200, 850);
    await tester.pumpAndSettle();
    expect(tester.getRect(_mainPanel).width, 400);
    expect(tester.getRect(_secondaryPanel).width, 788);
    expect(
      find.byKey(const ValueKey('main-panel-resize-handle')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'left-edge resize hides secondary at 320 and restores it on expansion',
    (tester) async {
      final frame = ValueNotifier<Rect?>(
        const Rect.fromLTWH(100, 0, 1200, 850),
      );
      addTearDown(frame.dispose);
      _openTopicTab(shell, _topic);
      await _pump(tester, shell, windowFrame: frame);

      frame.value = const Rect.fromLTWH(140, 0, 1160, 850);
      tester.view.physicalSize = const Size(1160, 850);
      await tester.pumpAndSettle();
      expect(tester.getRect(_mainPanel).width, 400);
      expect(tester.getRect(_secondaryPanel).width, 748);

      frame.value = const Rect.fromLTWH(568, 0, 732, 850);
      tester.view.physicalSize = const Size(732, 850);
      await tester.pumpAndSettle();
      expect(tester.getRect(_mainPanel).width, 400);
      expect(tester.getRect(_secondaryPanel).width, 320);

      frame.value = const Rect.fromLTWH(569, 0, 731, 850);
      tester.view.physicalSize = const Size(731, 850);
      await tester.pumpAndSettle();
      expect(_secondaryPanel, findsNothing);
      expect(tester.getRect(_mainPanel).width, 731);
      _toggleSplit(tester);
      await tester.pumpAndSettle();
      expect(_secondaryPanel, findsOneWidget);
      expect(
        find.byKey(const ValueKey('main-panel-resize-handle')),
        findsOneWidget,
      );
      _toggleSplit(tester);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('main-panel-resize-handle')),
        findsNothing,
      );
      expect(shell.activeTab?.panel, ForumPanel.main);

      frame.value = const Rect.fromLTWH(700, 0, 600, 850);
      tester.view.physicalSize = const Size(600, 850);
      await tester.pumpAndSettle();
      expect(tester.getRect(_mainPanel).width, 600);
      expect(_secondaryPanel, findsNothing);

      frame.value = const Rect.fromLTWH(100, 0, 1200, 850);
      tester.view.physicalSize = const Size(1200, 850);
      await tester.pumpAndSettle();
      expect(_secondaryPanel, findsNothing);
      _toggleSplit(tester);
      await tester.pumpAndSettle();
      expect(tester.getRect(_mainPanel).width, 400);
      expect(tester.getRect(_secondaryPanel).width, 788);
      expect(
        find.byKey(const ValueKey('main-panel-resize-handle')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'restoring a window-collapsed main panel brings back the draggable seam',
    (tester) async {
      final frame = ValueNotifier<Rect?>(
        const Rect.fromLTWH(100, 0, 1200, 850),
      );
      addTearDown(frame.dispose);
      _openTopicTab(shell, _topic);
      await _pump(tester, shell, windowFrame: frame);

      frame.value = const Rect.fromLTWH(100, 0, 1119, 850);
      tester.view.physicalSize = const Size(1119, 850);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('main-panel-resize-handle')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('panel-split-view-secondary')),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(_mainPanel).width, 400);
      expect(tester.getRect(_secondaryPanel).width, 707);

      await tester.drag(
        find.byKey(const ValueKey('main-panel-resize-handle')),
        const Offset(30, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(_mainPanel).width, 430);
      expect(tester.getRect(_secondaryPanel).width, 677);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow windows show only the visible panel tabs and restore both on resize',
    (tester) async {
      final main = shell.activeTabId!;
      _openTopicTab(shell, _topic);
      final reader = shell.activeTabId!;
      await _pump(tester, shell);
      expect(find.byType(ForumTabsBar), findsNWidgets(2));

      tester.view.physicalSize = const Size(580, 850);
      await tester.pumpAndSettle();
      expect(find.byType(ForumTabsBar), findsOneWidget);
      expect(find.byKey(ValueKey('forum-tab-$main')), findsNothing);
      expect(find.byKey(ValueKey('forum-tab-$reader')), findsOneWidget);
      expect(find.byType(TopicView), findsOneWidget);

      shell.selectTab(main);
      await tester.pumpAndSettle();
      expect(find.byType(ForumTabsBar), findsOneWidget);
      expect(find.byKey(ValueKey('forum-tab-$main')), findsOneWidget);
      expect(find.byKey(ValueKey('forum-tab-$reader')), findsNothing);
      expect(find.byType(TopicListView), findsOneWidget);
      expect(find.byType(TopicView), findsNothing);

      // One panel is all a narrow window shows, so neither stands down.
      expect(find.byTooltip('Hide split view'), findsNothing);

      tester.view.physicalSize = const Size(1200, 850);
      await tester.pumpAndSettle();
      expect(find.byType(ForumTabsBar), findsNWidgets(2));
      expect(find.byKey(ValueKey('forum-tab-$main')), findsOneWidget);
      expect(find.byKey(ValueKey('forum-tab-$reader')), findsOneWidget);
      expect(find.byType(TopicListView), findsOneWidget);
      expect(find.byType(TopicView), findsOneWidget);
      expect(shell.selectedTabIn(ForumPanel.main)?.id, main);
      expect(shell.selectedTabIn(ForumPanel.secondary)?.id, reader);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'two topic readers show their own posts and save separate anchors',
    (tester) async {
      _openTopicTab(shell, _topic);
      final first = shell.activeTabId!;
      shell.moveTabToPanel(first, ForumPanel.main);
      _openTopicTab(shell, _otherTopic);
      final second = shell.activeTabId!;
      await _pump(tester, shell);
      expect(find.byType(TopicView), findsNWidgets(2));
      expect(find.text('Content for 42', findRichText: true), findsOneWidget);
      expect(find.text('Content for 43', findRichText: true), findsOneWidget);
      shell.saveTopicScrollPost(42, 8, tabId: first);
      shell.saveTopicScrollPost(43, 5, tabId: second);
      expect(shell.topicScrollPostNumber(42, tabId: first), 8);
      expect(shell.topicScrollPostNumber(43, tabId: second), 5);
      expect(shell.activeTabId, second);
      expect(tester.takeException(), isNull);
    },
  );
}

final _mainPanel = find.byKey(const ValueKey('desktop-panel-main'));
final _secondaryPanel = find.byKey(const ValueKey('desktop-panel-secondary'));

Future<void> _pump(
  WidgetTester tester,
  ShellController shell, {
  TextDirection direction = TextDirection.ltr,
  bool reduceMotion = false,
  Size size = const Size(1200, 850),
  double textScale = 1,
  String? fontFamily,
  EdgeInsets safeArea = EdgeInsets.zero,
  ValueListenable<Rect?>? windowFrame,
  DAppearanceMaterial material = DAppearanceMaterial.standard,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final layout = DesktopPanelsLayout();
  addTearDown(layout.dispose);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: RepaintBoundary(
        key: const ValueKey('panel-swap-render'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: DMaterialTheme.apply(
            AppTheme.forBrightness(
              Brightness.light,
              fontFamily: fontFamily,
            ).copyWith(platform: TargetPlatform.macOS),
            material,
          ),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: reduceMotion,
                textScaler: TextScaler.linear(textScale),
              ),
              child: Directionality(
                textDirection: direction,
                child: TopicPresentationPreferences(
                  child: DToaster(
                    child: Scaffold(
                      body: Padding(
                        padding: safeArea,
                        child: DesktopPanels(
                          layout: layout,
                          windowFrame: windowFrame,
                        ),
                      ),
                    ),
                  ),
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

final _swapButton = find.byKey(const ValueKey('swap-panels'));

bool _swapVisible(WidgetTester tester) => tester
    .widget<Visibility>(
      find.ancestor(of: _swapButton, matching: find.byType(Visibility)).first,
    )
    .visible;

Future<void> _activateSwap(WidgetTester tester) async {
  tester.widget<DButton>(_swapButton).focusNode!.requestFocus();
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

List<Element> _panelAncestry(WidgetTester tester, Finder panel) {
  final chain = <Element>[];
  tester.element(panel).visitAncestorElements((ancestor) {
    if (ancestor.widget is DesktopPanels) return false;
    chain.add(ancestor);
    return true;
  });
  return chain;
}

Future<void> _exportPanelSwap(WidgetTester tester, String name) async {
  final directory = Platform.environment['PANEL_SWAP_EXPORT_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('panel-swap-render')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void _toggleSplit(WidgetTester tester) => tester
    .widget<DesktopPanels>(find.byType(DesktopPanels))
    .layout!
    .toggleSplit();

void _openTopicTab(
  ShellController shell,
  Topic topic, {
  ForumPanel panel = ForumPanel.secondary,
}) {
  final result = shell.openLinkInNewTab(
    '/t/${topic.slug}/${topic.id}',
    title: topic.title,
    panel: panel,
  );
  if (result == TabOpenResult.opened) {
    shell.selectTab(shell.tabsForCurrentForum.last.id);
  }
}
