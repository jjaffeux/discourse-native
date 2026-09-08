import 'dart:ui'
    show
        ImageByteFormat,
        PointerDeviceKind,
        SemanticsAction,
        SemanticsRole,
        Tristate;

import 'package:discourse_native/discourse_ui.dart' show DSeparator;
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/theme/d_tooltip.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/media_pipeline.dart';

void main() {
  const first = ForumTabItem(
    id: 'topic-1',
    title: 'A long-running topic',
    icon: DIcons.comment,
  );
  const second = ForumTabItem(
    id: 'chat-2',
    title: 'Team chat',
    icon: DIcons.comments,
  );
  const third = ForumTabItem(
    id: 'updates-3',
    title: 'Updates',
    icon: DIcons.bell,
  );

  group('tab presentation', () {
    testWidgets('renders title shortcodes as site emoji', (tester) async {
      final controller = ShellController(
        instanceStore: FakeInstanceStore([instance('meta.example')]),
        api: FakeDiscourseApi(
          emojisBySite: const {
            'https://meta.example': [
              SiteEmoji(
                name: 'magic_wand',
                url: '/images/emoji/magic_wand.png',
              ),
            ],
          },
        ),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);
      installTestMediaPipeline(
        client: MockClient((_) async => http.Response('', 404)),
      );
      await controller.ensureEmojiCatalog('https://meta.example');

      await _pumpBar(
        tester,
        controller: controller,
        items: const [
          ForumTabItem(
            id: 'topic-1',
            title: ':magic_wand: Introducing the new Admin Design Wizard',
            siteUrl: 'https://meta.example',
          ),
        ],
        selectedId: 'topic-1',
      );

      final emoji = tester.widget<SiteEmojiImage>(
        find.descendant(
          of: find.byType(ForumTabsBar),
          matching: find.byType(SiteEmojiImage),
        ),
      );
      expect(emoji.siteUrl, 'https://meta.example');
      expect(emoji.name, 'magic_wand');
      expect(
        find.bySemanticsLabel(
          ':magic_wand: Introducing the new Admin Design Wizard',
        ),
        findsOneWidget,
      );
    });

    testWidgets('matches shell geometry and places add after the final tab', (
      tester,
    ) async {
      await _pumpBar(
        tester,
        items: const [first, second],
        selectedId: first.id,
        width: 560,
      );

      const barKey = ValueKey('forum-tabs-bar');
      const addKey = ValueKey('forum-tabs-add');
      final bar = find.byKey(barKey);
      final add = find.byKey(addKey);
      final selected = find.byKey(const ValueKey('forum-tab-item-topic-1'));
      final ordinary = find.byKey(const ValueKey('forum-tab-item-chat-2'));
      final theme = Theme.of(tester.element(bar));

      expect(ForumTabsBar.height, 38);
      expect(tester.getSize(bar).height, 38);
      expect(tester.getSize(bar).width, 560);
      expect(
        tester.getSize(add),
        const Size.square(ForumTabsBar.minimumActionTarget),
      );
      expect(tester.getSize(selected).width, ForumTabsBar.maximumTabWidth);
      expect(tester.getSize(ordinary).width, ForumTabsBar.maximumTabWidth);

      final barDecoration = _decoration(tester, bar);
      expect(barDecoration.color, theme.shell.sidebar);

      final barRect = tester.getRect(bar);
      final selectedRect = tester.getRect(selected);
      final ordinaryRect = tester.getRect(ordinary);
      expect(
        selectedRect.left,
        barRect.left + 4 + ForumTabsBar.minimumActionTarget + 4,
      );
      expect(selectedRect.top, barRect.top + 3);
      expect(selectedRect.bottom, barRect.bottom);
      expect(ordinaryRect.top, selectedRect.top);
      expect(ordinaryRect.bottom, selectedRect.bottom);

      final selectedDecoration = _tabDecoration(tester, selected);
      final ordinaryDecoration = _tabDecoration(tester, ordinary);
      expect(selectedDecoration.color, theme.shell.content);
      expect(
        (selectedDecoration.shape as OutlinedBorder).side,
        BorderSide.none,
      );
      expect(ordinaryDecoration.color, Colors.transparent);
      expect(
        (ordinaryDecoration.shape as OutlinedBorder).side,
        BorderSide.none,
      );
      expect(
        find.byKey(const ValueKey('forum-tab-indicator-topic-1')),
        findsNothing,
      );

      final addRect = tester.getRect(add);
      expect(addRect.left, ordinaryRect.right + 4);
      expect(
        addRect.center.dy,
        barRect.top + 3 + (ForumTabsBar.height - 3) / 2,
      );

      // Check the painted bottom edge as well as layout: the active tab must
      // connect to the page without adding a separator beneath inactive tabs.
      await _expectTabPixels(tester, [
        (
          Offset(selectedRect.center.dx, selectedRect.bottom - 1),
          theme.shell.content,
        ),
        (
          Offset(ordinaryRect.center.dx, ordinaryRect.bottom - 1),
          theme.shell.sidebar,
        ),
        // The active tab widens into the page at its feet, with cutouts beside
        // its body and rounded upper corners rather than a rectangle.
        for (final x in [selectedRect.left + 3, selectedRect.right - 4]) ...[
          (Offset(x, selectedRect.bottom - 1), theme.shell.content),
          (Offset(x, selectedRect.center.dy), theme.shell.sidebar),
        ],
        (selectedRect.topLeft + const Offset(5, 1), theme.shell.sidebar),
        (
          Offset(selectedRect.center.dx, selectedRect.top + 1),
          theme.shell.content,
        ),
      ]);

      final close = find.byKey(const ValueKey('forum-tab-close-topic-1'));
      expect(tester.getSize(close).width, ForumTabsBar.closeTargetWidth);
      expect(
        tester.getSize(close).height,
        greaterThanOrEqualTo(ForumTabsBar.minimumActionTarget),
      );
    });

    testWidgets('separates neighboring inactive tabs without outlines', (
      tester,
    ) async {
      await _pumpBar(
        tester,
        items: const [first, second, third],
        selectedId: third.id,
        theme: AppTheme.dark,
      );

      final firstTab = find.byKey(const ValueKey('forum-tab-item-topic-1'));
      final secondTab = find.byKey(const ValueKey('forum-tab-item-chat-2'));
      final selectedTab = find.byKey(
        const ValueKey('forum-tab-item-updates-3'),
      );
      final divider = find.byKey(const ValueKey('forum-tab-divider-topic-1'));
      final theme = Theme.of(tester.element(divider));

      expect(divider, findsOneWidget);
      expect(tester.getSize(divider), const Size(1, 18));
      expect(tester.widget<DSeparator>(divider).color, theme.shell.divider);
      expect(
        tester.getCenter(divider).dy,
        moreOrLessEquals(tester.getCenter(firstTab).dy),
      );
      expect(
        find.byKey(const ValueKey('forum-tab-divider-chat-2')),
        findsNothing,
      );
      for (final tab in [firstTab, secondTab, selectedTab]) {
        expect(
          (_tabDecoration(tester, tab).shape as OutlinedBorder).side,
          BorderSide.none,
        );
      }

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(pointer.removePointer);
      await pointer.addPointer();
      for (final tab in [firstTab, secondTab]) {
        await pointer.moveTo(tester.getCenter(tab));
        await tester.pumpAndSettle();
        expect(tester.widget<DSeparator>(divider).color, Colors.transparent);
      }
      await pointer.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(tester.widget<DSeparator>(divider).color, theme.shell.divider);
    });

    testWidgets(
      'shows an inset tertiary-low hover pill without moving the tab',
      (tester) async {
        await _pumpBar(
          tester,
          items: const [first, second],
          selectedId: first.id,
        );

        final tab = find.byKey(const ValueKey('forum-tab-item-chat-2'));
        final before = tester.getRect(tab);
        final theme = Theme.of(tester.element(tab));
        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(pointer.removePointer);
        await pointer.addPointer();
        await pointer.moveTo(tester.getCenter(tab));
        await tester.pumpAndSettle();

        expect(tester.getRect(tab), before);
        expect(
          _tabDecoration(tester, tab).color,
          theme.colorScheme.primaryContainer,
        );
        await _expectTabPixels(tester, [
          (before.topLeft + const Offset(5, 3), theme.shell.sidebar),
          (
            Offset(before.center.dx, before.top + 3),
            theme.colorScheme.primaryContainer,
          ),
          (
            Offset(before.left + 3, before.center.dy),
            theme.colorScheme.primaryContainer,
          ),
          (
            Offset(before.center.dx, before.bottom - 6),
            theme.colorScheme.primaryContainer,
          ),
          (Offset(before.center.dx, before.bottom - 1), theme.shell.sidebar),
        ]);
      },
    );
  });

  group('pointer and editing interactions', () {
    testWidgets('delegate add, selection, and distinct close actions by ID', (
      tester,
    ) async {
      var addCount = 0;
      final selected = <String>[];
      final closed = <String>[];
      await _pumpBar(
        tester,
        items: const [first, second],
        selectedId: first.id,
        onAdd: () => addCount += 1,
        onSelect: selected.add,
        onClose: closed.add,
      );

      final secondTabRect = tester.getRect(
        find.byKey(const ValueKey('forum-tab-chat-2')),
      );
      final selectionGesture = await tester.startGesture(
        Offset(secondTabRect.left + 20, secondTabRect.top + 1),
      );
      // Native desktop tabs activate on pointer-down rather than waiting for the
      // complete click gesture, and the full tab height is selectable.
      expect(selected, [second.id]);
      expect(closed, isEmpty);
      await selectionGesture.up();
      expect(selected, [second.id]);

      final closeRect = tester.getRect(
        find.byKey(const ValueKey('forum-tab-close-topic-1')),
      );
      await tester.tapAt(Offset(closeRect.left + 1, closeRect.center.dy));
      expect(closed, [first.id]);
      expect(selected, [second.id]);

      await tester.tap(find.byKey(const ValueKey('forum-tabs-add')));
      expect(addCount, 1);

      final platform = Theme.of(
        tester.element(find.byKey(const ValueKey('forum-tabs-bar'))),
      ).platform;
      final addTooltip = tester.widget<DTooltip>(
        find.descendant(
          of: find.byKey(const ValueKey('forum-tabs-add')),
          matching: find.byType(DTooltip),
        ),
      );
      final selectedCloseTooltip = tester.widget<DTooltip>(
        find.descendant(
          of: find.byKey(const ValueKey('forum-tab-close-topic-1')),
          matching: find.byType(DTooltip),
        ),
      );
      final inactiveCloseTooltip = tester.widget<DTooltip>(
        find.descendant(
          of: find.byKey(const ValueKey('forum-tab-close-chat-2')),
          matching: find.byType(DTooltip),
        ),
      );
      expect(addTooltip.message, 'Open a new tab');
      expect(selectedCloseTooltip.message, 'Close A long-running topic');
      _expectPrimaryShortcut(
        addTooltip.shortcut![0],
        platform,
        LogicalKeyboardKey.keyT,
      );
      _expectPrimaryShortcut(
        selectedCloseTooltip.shortcut![0],
        platform,
        LogicalKeyboardKey.keyW,
      );
      _expectPrimaryShortcut(
        inactiveCloseTooltip.shortcut![0],
        platform,
        LogicalKeyboardKey.keyW,
      );
    });

    testWidgets('delegate horizontal drag-and-drop reordering by ID', (
      tester,
    ) async {
      final reordered = <({String id, int newIndex})>[];
      await _pumpBar(
        tester,
        items: const [first, second],
        selectedId: first.id,
        onReorder: (id, newIndex) =>
            reordered.add((id: id, newIndex: newIndex)),
      );

      final firstTab = find.byKey(const ValueKey('forum-tab-item-topic-1'));
      final secondTab = find.byKey(const ValueKey('forum-tab-item-chat-2'));
      final drag = await tester.startGesture(tester.getCenter(firstTab));
      await drag.moveTo(tester.getCenter(secondTab));
      await tester.pump();

      final targetOutline =
          _tabDecoration(tester, secondTab).shape as OutlinedBorder;
      expect(targetOutline.side.width, 2);
      expect(targetOutline.side.style, BorderStyle.solid);

      await drag.up();
      await tester.pumpAndSettle();

      expect(reordered, [(id: first.id, newIndex: 1)]);
    });

    testWidgets('show the click cursor across every tab', (tester) async {
      await _pumpBar(
        tester,
        items: const [first, second],
        selectedId: first.id,
      );

      for (final item in const [first, second]) {
        final hoverRegion = find.byKey(
          ValueKey('forum-tab-pointer-${item.id}'),
        );

        expect(hoverRegion, findsOneWidget);
        expect(
          tester.widget<MouseRegion>(hoverRegion).cursor,
          SystemMouseCursors.click,
        );
      }
    });

    testWidgets('rename a tab inline after a double click', (tester) async {
      final renamed = <(String, String)>[];
      await _pumpBar(
        tester,
        items: const [first, second],
        selectedId: first.id,
        onRename: (id, title) => renamed.add((id, title)),
      );

      await tester.tap(find.text(first.title));
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(find.text(first.title));
      await tester.pump();

      final editor = find.byKey(const ValueKey('forum-tab-rename-topic-1'));
      expect(editor, findsOneWidget);
      expect(
        tester.widget<TextField>(editor).controller!.selection,
        TextSelection(baseOffset: 0, extentOffset: first.title.length),
      );

      await tester.enterText(editor, 'Release planning');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(renamed, [(first.id, 'Release planning')]);
      expect(editor, findsNothing);
      await tester.pump(kDoubleTapTimeout);
    });

    testWidgets('reveal close on tab hover without shifting the title', (
      tester,
    ) async {
      await _pumpBar(
        tester,
        items: const [first, second],
        selectedId: first.id,
      );

      const closeKey = ValueKey('forum-tab-close-topic-1');
      const surfaceKey = ValueKey('forum-tab-close-surface-topic-1');
      final close = find.byKey(closeKey);
      final surface = find.byKey(surfaceKey);
      final theme = Theme.of(tester.element(close));
      final titleRect = tester.getRect(find.text(first.title));

      expect(tester.getSize(close).width, ForumTabsBar.closeTargetWidth);
      expect(
        tester.getSize(close).height,
        greaterThanOrEqualTo(ForumTabsBar.minimumActionTarget),
      );
      expect(tester.getSize(surface), const Size.square(24));
      expect(_decoration(tester, surface).color, Colors.transparent);
      expect(_closeOpacity(tester, first.id), 0);
      expect(_closeOpacity(tester, second.id), 0);

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(pointer.removePointer);
      await pointer.addPointer();
      await pointer.moveTo(tester.getCenter(find.text(first.title)));
      await tester.pumpAndSettle();

      expect(_closeOpacity(tester, first.id), 1);
      expect(_closeOpacity(tester, second.id), 0);
      expect(tester.getRect(find.text(first.title)), titleRect);

      await pointer.moveTo(tester.getCenter(close));
      await tester.pumpAndSettle();

      expect(_decoration(tester, surface).color, theme.shell.selected);
      expect(tester.getSize(surface), const Size.square(24));

      await pointer.moveTo(tester.getCenter(find.text(second.title)));
      await tester.pumpAndSettle();
      expect(_closeOpacity(tester, first.id), 0);
      expect(_closeOpacity(tester, second.id), 1);
      expect(tester.getRect(find.text(first.title)), titleRect);

      await pointer.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(_closeOpacity(tester, first.id), 0);
      expect(_closeOpacity(tester, second.id), 0);
    });

    testWidgets(
      'show close actions on secondary click without selecting the tab',
      (tester) async {
        final selected = <String>[];
        final closed = <String>[];
        final closedOthers = <String>[];
        await _pumpBar(
          tester,
          items: const [first, second],
          selectedId: first.id,
          onSelect: selected.add,
          onClose: closed.add,
          onCloseOthers: closedOthers.add,
        );

        await tester.tap(
          find.byKey(const ValueKey('forum-tab-chat-2')),
          buttons: kSecondaryButton,
        );
        await tester.pumpAndSettle();

        expect(find.text('Close tab'), findsOneWidget);
        expect(find.text('Close other tabs'), findsOneWidget);
        expect(selected, isEmpty);
        expect(
          tester
              .widget<MenuItemButton>(
                find.byKey(const ValueKey('forum-tab-menu-close-chat-2')),
              )
              .leadingIcon,
          isNull,
        );
        expect(
          tester
              .widget<MenuItemButton>(
                find.byKey(
                  const ValueKey('forum-tab-menu-close-others-chat-2'),
                ),
              )
              .leadingIcon,
          isNull,
        );
        expect(
          tester
              .widget<MenuItemButton>(
                find.byKey(const ValueKey('forum-tab-menu-close-chat-2')),
              )
              .shortcut,
          isNull,
        );

        await tester.tap(
          find.byKey(const ValueKey('forum-tab-menu-close-others-chat-2')),
        );
        await tester.pumpAndSettle();

        expect(closed, isEmpty);
        expect(closedOthers, [second.id]);

        await tester.tap(
          find.byKey(const ValueKey('forum-tab-chat-2')),
          buttons: kSecondaryButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('forum-tab-menu-close-chat-2')),
        );
        await tester.pumpAndSettle();

        expect(closed, [second.id]);
      },
    );

    testWidgets('keep close-other visible but disabled for a sole tab', (
      tester,
    ) async {
      await _pumpBar(tester, items: const [first], selectedId: first.id);

      await tester.tap(
        find.byKey(const ValueKey('forum-tab-topic-1')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      final closeOthers = tester.widget<MenuItemButton>(
        find.byKey(const ValueKey('forum-tab-menu-close-others-topic-1')),
      );
      final close = tester.widget<MenuItemButton>(
        find.byKey(const ValueKey('forum-tab-menu-close-topic-1')),
      );
      _expectPrimaryShortcut(
        close.shortcut,
        Theme.of(tester.element(find.byType(ForumTabsBar))).platform,
        LogicalKeyboardKey.keyW,
      );
      expect(closeOthers.onPressed, isNull);
    });

    testWidgets(
      'keep the add hover surface compact and clear of the final tab',
      (tester) async {
        await _pumpBar(tester, items: const [first], selectedId: first.id);

        const addKey = ValueKey('forum-tabs-add');
        const surfaceKey = ValueKey('forum-tabs-add-surface');
        final tab = find.byKey(const ValueKey('forum-tab-item-topic-1'));
        final add = find.byKey(addKey);
        final surface = find.byKey(surfaceKey);
        final theme = Theme.of(tester.element(add));

        expect(
          tester.getSize(add),
          const Size.square(ForumTabsBar.minimumActionTarget),
        );
        expect(tester.getSize(surface), const Size.square(28));
        expect(tester.getRect(add).left, tester.getRect(tab).right + 4);
        expect(tester.getRect(surface).left, tester.getRect(tab).right + 7);
        expect(_decoration(tester, surface).color, Colors.transparent);

        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(pointer.removePointer);
        await pointer.addPointer();
        await pointer.moveTo(tester.getCenter(add));
        await tester.pumpAndSettle();

        expect(
          _decoration(tester, surface).color,
          theme.colorScheme.primaryContainer,
        );
        expect(tester.getSize(surface), const Size.square(28));
      },
    );
  });

  group('tab switcher', () {
    testWidgets('renders as a bordered button with a tertiary hover state', (
      tester,
    ) async {
      await _pumpBar(tester, items: const [first], selectedId: first.id);

      final switcher = find.byKey(const ValueKey('forum-tabs-switcher'));
      final surface = find.byKey(const ValueKey('forum-tabs-switcher-surface'));
      final theme = Theme.of(tester.element(surface));
      final decoration = _decoration(tester, surface);

      expect(tester.getSize(switcher).width, ForumTabsBar.minimumActionTarget);
      expect(
        tester.getSize(switcher).height,
        greaterThanOrEqualTo(ForumTabsBar.minimumActionTarget),
      );
      expect(tester.getSize(surface), const Size.square(28));
      expect(decoration.color, theme.shell.content);
      expect((decoration.border! as Border).top.color, theme.shell.divider);

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(pointer.removePointer);
      await pointer.addPointer();
      await pointer.moveTo(tester.getCenter(switcher));
      await tester.pumpAndSettle();

      expect(
        _decoration(tester, surface).color,
        theme.colorScheme.primaryContainer,
      );
    });

    testWidgets('searches open tabs and restores a chosen closed tab', (
      tester,
    ) async {
      final selected = <String>[];
      final reopened = <String>[];
      await _pumpBar(
        tester,
        items: const [first, second],
        recentlyClosedItems: const [third],
        selectedId: first.id,
        onSelect: selected.add,
        onReopen: reopened.add,
      );

      await tester.tap(
        find.byKey(const ValueKey('forum-tabs-switcher-surface')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Open tabs  2'), findsOneWidget);
      expect(find.text('Recently closed  1'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('forum-tabs-switcher-recent-updates-3')),
        findsNothing,
      );
      final rowTitle = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('forum-tabs-switcher-open-topic-1')),
          matching: find.text(first.title),
        ),
      );
      expect(rowTitle.style?.fontSize, DiscourseTypography.sm);
      expect(find.textContaining('Scoped to'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('forum-tabs-switcher-open-topic-1')),
          matching: find.byWidgetPredicate(
            (widget) => widget is DIcon && widget.icon == DIcons.comment,
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('forum-tabs-switcher-history')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('forum-tabs-switcher-search')),
        'updates',
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('forum-tabs-switcher-open-topic-1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('forum-tabs-switcher-recent-updates-3')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('forum-tabs-switcher-recent-updates-3')),
      );
      await tester.pumpAndSettle();
      expect(reopened, [third.id]);
      expect(
        find.byKey(const ValueKey('forum-tabs-switcher-menu')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('forum-tabs-switcher-surface')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('forum-tabs-switcher-open-chat-2')),
      );
      await tester.pumpAndSettle();
      expect(selected, [second.id]);
    });

    testWidgets('hides empty history and sizes the menu to its results', (
      tester,
    ) async {
      await _pumpBar(tester, items: const [first], selectedId: first.id);

      await tester.tap(
        find.byKey(const ValueKey('forum-tabs-switcher-surface')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('forum-tabs-switcher-history')),
        findsNothing,
      );
      expect(find.text('No matching recently closed tabs'), findsNothing);
      final menu = find.byKey(const ValueKey('forum-tabs-switcher-menu'));
      expect(tester.getSize(menu).height, lessThan(200));

      await tester.enterText(
        find.byKey(const ValueKey('forum-tabs-switcher-search')),
        'missing',
      );
      await tester.pump();

      expect(find.text('No matching open tabs'), findsOneWidget);
      expect(tester.getSize(menu).height, lessThan(200));
    });

    for (final theme in [AppTheme.light, AppTheme.dark]) {
      testWidgets(
        'wraps titles and keeps close actions separate at 200% text size in ${theme.brightness.name} mode',
        (tester) async {
          tester.view
            ..physicalSize = const Size(320, 540)
            ..devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          const longTab = ForumTabItem(
            id: 'long-topic',
            title:
                'SECURITY: Enforce private livestream event chat permissions',
            icon: DIcons.layerGroup,
          );
          final closed = <String>[];
          final selected = <String>[];
          await _pumpBar(
            tester,
            items: const [longTab, third],
            selectedId: longTab.id,
            width: 320,
            theme: theme,
            onClose: closed.add,
            onSelect: selected.add,
          );

          await tester.tap(
            find.byKey(const ValueKey('forum-tabs-switcher-surface')),
          );
          await tester.pumpAndSettle();

          final menu = find.byKey(const ValueKey('forum-tabs-switcher-menu'));
          final row = find.byKey(
            const ValueKey('forum-tabs-switcher-open-long-topic'),
          );
          final shortRow = find.byKey(
            const ValueKey('forum-tabs-switcher-open-updates-3'),
          );
          final close = find.descendant(
            of: row,
            matching: find.byType(IconButton),
          );
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(row).height,
            greaterThan(tester.getSize(shortRow).height),
          );
          expect(tester.getRect(menu).right, lessThanOrEqualTo(320));
          expect(tester.getRect(menu).bottom, lessThanOrEqualTo(540));
          expect(tester.getRect(row).contains(tester.getCenter(close)), isTrue);

          await tester.tap(close);
          await tester.pumpAndSettle();

          expect(closed, [longTab.id]);
          expect(selected, isEmpty);
          expect(menu, findsOneWidget);
        },
      );
    }
  });

  group('tab adornments', () {
    testWidgets('render prefixes, unread badges, and ellipsized labels', (
      tester,
    ) async {
      const childColor = Color(0xFF0088CC);
      const parentColor = Color(0xFFFF0000);
      const iconColor = Color(0xFF00AA00);
      const items = [
        ForumTabItem(
          id: 'category-3',
          title: 'A category title too long to fit in this narrow tab',
          icon: DIcons.comment,
          color: childColor,
          parentColor: parentColor,
          badge: SidebarBadge.count(3),
        ),
        ForumTabItem(
          id: 'urgent-4',
          title: 'Urgent chat',
          icon: DIcons.comments,
          iconColor: iconColor,
          badge: SidebarBadge.dot(urgent: true),
        ),
      ];
      await _pumpBar(
        tester,
        items: items,
        selectedId: items.first.id,
        width: 280,
      );

      final swatch = tester.widget<Container>(
        find.byKey(const ValueKey('forum-tab-prefix-category-3')),
      );
      final gradient = (swatch.decoration! as BoxDecoration).gradient!;
      final longTitle = tester.widget<Text>(find.text(items.first.title));
      final countBadge = find.byKey(
        const ValueKey('forum-tab-badge-category-3'),
      );
      final urgentDot = find.byKey(const ValueKey('forum-tab-badge-urgent-4'));
      final theme = Theme.of(tester.element(urgentDot));

      expect((gradient as LinearGradient).colors, [parentColor, childColor]);
      expect(longTitle.maxLines, 1);
      expect(longTitle.overflow, TextOverflow.ellipsis);
      expect(find.text('3'), findsOneWidget);
      expect(tester.getSize(countBadge).height, 18);
      expect(tester.getSize(urgentDot), const Size(8, 8));
      expect(_decoration(tester, urgentDot).color, theme.discourse.success);

      final urgentIcon = tester.widget<DIcon>(
        find.descendant(
          of: find.byKey(const ValueKey('forum-tab-item-urgent-4')),
          matching: find.byWidgetPredicate(
            (widget) => widget is DIcon && widget.icon == DIcons.comments,
          ),
        ),
      );
      expect(urgentIcon.color, iconColor);
      expect(urgentIcon.size, 15);
    });

    testWidgets('keep unread dots beside the title', (tester) async {
      const item = ForumTabItem(
        id: 'chat-2',
        title: 'Team chat',
        icon: DIcons.comments,
        badge: SidebarBadge.dot(),
      );
      await _pumpBar(tester, items: const [item], selectedId: item.id);

      final titleFinder = find.text(item.title);
      final title = tester.widget<Text>(titleFinder);
      final titleContext = tester.element(titleFinder);
      final titlePainter = TextPainter(
        text: TextSpan(text: item.title, style: title.style),
        textDirection: Directionality.of(titleContext),
        textScaler: MediaQuery.textScalerOf(titleContext),
      )..layout();
      final titleEnd = tester.getTopLeft(titleFinder).dx + titlePainter.width;
      final dot = tester.getRect(
        find.byKey(const ValueKey('forum-tab-badge-chat-2')),
      );

      expect(dot.left, greaterThan(titleEnd));
      expect(dot.left - titleEnd, lessThanOrEqualTo(3));
    });

    testWidgets('render owner-provided prefix and label decorations', (
      tester,
    ) async {
      double? prefixSize;
      double? suffixSize;
      final item = ForumTabItem(
        id: 'plugin-route',
        title: 'Plugin route',
        prefixBuilder: (_, size) {
          prefixSize = size;
          return const SizedBox(key: ValueKey('plugin-tab-prefix'));
        },
        labelSuffixBuilder: (_, size) {
          suffixSize = size;
          return const SizedBox(key: ValueKey('plugin-tab-label-suffix'));
        },
        semanticDescription: 'feature state',
      );

      await _pumpBar(tester, items: [item], selectedId: item.id);

      expect(find.byKey(const ValueKey('plugin-tab-prefix')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('plugin-tab-label-suffix')),
        findsOneWidget,
      );
      expect(prefixSize, 15);
      expect(suffixSize, 13);
      expect(
        find.bySemanticsLabel('Plugin route, feature state'),
        findsOneWidget,
      );
    });

    testWidgets('omit the OPEN label and opened-tab totals', (tester) async {
      final items = [
        for (var index = 0; index < 5; index++)
          ForumTabItem(
            id: 'tab-$index',
            title: 'Tab $index',
            icon: DIcons.comment,
          ),
      ];
      await _pumpBar(tester, items: items, selectedId: items.first.id);

      expect(find.text('OPEN'), findsNothing);
      expect(find.text('5 open'), findsNothing);
      expect(find.text('5'), findsNothing);
      expect(find.text('+5'), findsNothing);
      expect(find.text('+2'), findsNothing);
      expect(find.byKey(const ValueKey('forum-tabs-add')), findsOneWidget);
    });
  });

  group('overflow layout', () {
    testWidgets('scrolls overflowing tabs and keeps add after the final tab', (
      tester,
    ) async {
      final items = [
        for (var index = 0; index < 8; index++)
          ForumTabItem(
            id: 'tab-$index',
            title: 'Forum tab $index',
            icon: DIcons.comment,
            badge: index == 3
                ? const SidebarBadge.count(999)
                : SidebarBadge.none,
          ),
      ];
      await _pumpBar(
        tester,
        items: items,
        selectedId: items.first.id,
        width: 320,
      );

      final scrollable = _scrollable(tester);
      final add = find.byKey(const ValueKey('forum-tabs-add'));
      final initialAddRect = tester.getRect(add);
      final initialLastTabRect = tester.getRect(
        find.byKey(ValueKey('forum-tab-item-${items.last.id}')),
      );
      final initialViewportRect = tester.getRect(
        find.byKey(const ValueKey('forum-tabs-scroll')),
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      expect(scrollable.position.pixels, 0);
      expect(initialAddRect.left, initialLastTabRect.right + 4);
      expect(initialAddRect.left, greaterThan(initialViewportRect.right));
      expect(
        find.byKey(const ValueKey('forum-tab-badge-tab-3')),
        findsOneWidget,
      );
      for (final item in items) {
        expect(find.byKey(ValueKey('forum-tab-${item.id}')), findsOneWidget);
      }

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(
            find.byKey(const ValueKey('forum-tabs-scroll')),
          ),
          scrollDelta: const Offset(180, 0),
        ),
      );
      await tester.pumpAndSettle();

      expect(scrollable.position.pixels, greaterThan(0));
      expect(tester.getRect(add).left, lessThan(initialAddRect.left));
      expect(
        tester.getRect(add).left,
        tester
                .getRect(
                  find.byKey(ValueKey('forum-tab-item-${items.last.id}')),
                )
                .right +
            4,
      );

      await _pumpBar(
        tester,
        items: items,
        selectedId: items.last.id,
        width: 320,
      );
      await tester.pumpAndSettle();

      expect(_scrollable(tester).position.pixels, greaterThan(0));
      final lastTabRect = tester.getRect(
        find.byKey(ValueKey('forum-tab-item-${items.last.id}')),
      );
      final viewportRect = tester.getRect(
        find.byKey(const ValueKey('forum-tabs-scroll')),
      );
      expect(lastTabRect.left, greaterThanOrEqualTo(viewportRect.left));
      expect(lastTabRect.right, lessThanOrEqualTo(viewportRect.right));
      expect(tester.getRect(add).left, lastTabRect.right + 4);
      expect(tester.getRect(add).right, lessThanOrEqualTo(viewportRect.right));
    });
  });

  group('accessibility', () {
    testWidgets('keyboard focus reveals close and Enter closes the tab', (
      tester,
    ) async {
      final closed = <String>[];
      await _pumpBar(
        tester,
        items: const [first],
        selectedId: first.id,
        onClose: closed.add,
      );
      final button = tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(const ValueKey('forum-tab-close-topic-1')),
          matching: find.byType(IconButton),
        ),
      );
      expect(_closeOpacity(tester, first.id), 0);
      for (var step = 0; step < 6; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        if (button.statesController!.value.contains(WidgetState.focused)) break;
      }
      expect(button.statesController!.value, contains(WidgetState.focused));
      expect(_closeOpacity(tester, first.id), 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(closed, [first.id]);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_closeOpacity(tester, first.id), 0);
    });

    testWidgets('exposes a named tab bar, selected states, and close actions', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      const items = [
        ForumTabItem(
          id: 'topic-1',
          title: 'A long-running topic',
          icon: DIcons.comment,
          badge: SidebarBadge.count(3),
        ),
        ForumTabItem(
          id: 'chat-2',
          title: 'Team chat',
          icon: DIcons.comments,
          badge: SidebarBadge.dot(urgent: true),
        ),
      ];
      await _pumpBar(tester, items: items, selectedId: items.first.id);

      final tabBar = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.role == SemanticsRole.tabBar,
      );
      final selectedNode = tester.getSemantics(
        find.byKey(const ValueKey('forum-tab-topic-1')),
      );
      final ordinaryNode = tester.getSemantics(
        find.byKey(const ValueKey('forum-tab-chat-2')),
      );
      final closeNode = tester.getSemantics(
        find.byKey(const ValueKey('forum-tab-close-topic-1')),
      );

      expect(tabBar, findsOneWidget);
      expect(tester.getSemantics(tabBar).label, 'Open tabs in Discourse Meta');
      expect(selectedNode.getSemanticsData().role, SemanticsRole.tab);
      expect(selectedNode.label, 'A long-running topic, 3 unread items');
      expect(
        selectedNode.getSemanticsData().flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(ordinaryNode.getSemanticsData().role, SemanticsRole.tab);
      expect(ordinaryNode.label, 'Team chat, urgent unread activity');
      expect(
        ordinaryNode.getSemanticsData().flagsCollection.isSelected,
        Tristate.isFalse,
      );
      expect(closeNode.label, 'Close A long-running topic');
      expect(closeNode.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('forum-tabs-add'))).label,
        'Open a new tab',
      );

      semantics.dispose();
    });

    testWidgets('announces and disables add at tab capacity', (tester) async {
      final semantics = tester.ensureSemantics();

      await _pumpBar(
        tester,
        items: const [
          ForumTabItem(id: 'one', title: 'One', icon: DIcons.comments),
        ],
        selectedId: 'one',
        addEnabled: false,
      );

      final target = find.byKey(const ValueKey('forum-tabs-add'));
      final data = tester.getSemantics(target).getSemanticsData();
      expect(data.label, 'Close a tab before opening another');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(
        tester
            .widget<DTooltip>(
              find.descendant(of: target, matching: find.byType(DTooltip)),
            )
            .shortcut,
        isNull,
      );
      semantics.dispose();
    });
  });
}

Future<void> _expectTabPixels(
  WidgetTester tester,
  List<(Offset, Color)> samples,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('forum-tabs-paint-boundary')),
  );
  final origin = boundary.localToGlobal(Offset.zero);
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
      for (final (point, color) in samples) {
        final local = point - origin;
        final offset = (local.dy.floor() * image.width + local.dx.floor()) * 4;
        expect(
          Color.fromARGB(
            bytes.getUint8(offset + 3),
            bytes.getUint8(offset),
            bytes.getUint8(offset + 1),
            bytes.getUint8(offset + 2),
          ),
          color,
          reason: 'Tab surface at $point',
        );
      }
    } finally {
      image.dispose();
    }
  });
}

ShapeDecoration _tabDecoration(WidgetTester tester, Finder finder) =>
    tester.widget<AnimatedContainer>(finder).decoration! as ShapeDecoration;

double _closeOpacity(WidgetTester tester, String tabId) => tester
    .widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byKey(ValueKey('forum-tab-close-surface-$tabId')),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    )
    .opacity;

BoxDecoration _decoration(WidgetTester tester, Finder finder) => switch (tester
    .widget(finder)) {
  final Container box => box.decoration! as BoxDecoration,
  final AnimatedContainer box => box.decoration! as BoxDecoration,
  final DecoratedBox box => box.decoration as BoxDecoration,
  final widget => throw StateError('${widget.runtimeType} decorates nothing'),
};

ScrollableState _scrollable(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('forum-tabs-scroll')),
        matching: find.byType(Scrollable),
      ),
    );

void _expectPrimaryShortcut(
  Object? shortcut,
  TargetPlatform platform,
  LogicalKeyboardKey trigger,
) {
  expect(shortcut, isA<SingleActivator>());
  final activator = shortcut! as SingleActivator;
  expect(activator.trigger, trigger);
  expect(activator.meta, platform == TargetPlatform.macOS);
  expect(activator.control, platform != TargetPlatform.macOS);
  expect(activator.alt, isFalse);
  expect(activator.shift, isFalse);
}

Future<void> _pumpBar(
  WidgetTester tester, {
  required List<ForumTabItem> items,
  required String selectedId,
  VoidCallback? onAdd,
  bool addEnabled = true,
  ValueChanged<String>? onSelect,
  ValueChanged<String>? onClose,
  void Function(String id, int newIndex)? onReorder,
  ValueChanged<String>? onCloseOthers,
  List<ForumTabItem> recentlyClosedItems = const [],
  ValueChanged<String>? onReopen,
  void Function(String id, String title)? onRename,
  double width = 500,
  ThemeData? theme,
  ShellController? controller,
}) async {
  Widget child = MaterialApp(
    theme: theme ?? AppTheme.light,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: Column(
            children: [
              RepaintBoundary(
                key: const ValueKey('forum-tabs-paint-boundary'),
                child: ForumTabsBar(
                  forumName: 'Discourse Meta',
                  items: items,
                  selectedId: selectedId,
                  onAdd: addEnabled ? (onAdd ?? () {}) : null,
                  onSelect: onSelect ?? (_) {},
                  onClose: onClose ?? (_) {},
                  onReorder: onReorder ?? (_, _) {},
                  onCloseOthers: onCloseOthers ?? (_) {},
                  recentlyClosedItems: recentlyClosedItems,
                  onReopen: onReopen,
                  onRename: onRename,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (controller != null) {
    child = ShellScope(controller: controller, child: child);
  }
  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
}
