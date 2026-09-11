import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpMenu(
    WidgetTester tester, {
    Widget? child,
    TextDirection direction = TextDirection.ltr,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Directionality(
            textDirection: direction,
            child: Center(child: child ?? const _MenuHarness()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final direction in TextDirection.values) {
    testWidgets('separators paint visible full-width lines in $direction', (
      tester,
    ) async {
      final theme = ValueNotifier(AppTheme.light);
      addTearDown(theme.dispose);
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: ValueListenableBuilder(
            valueListenable: theme,
            builder: (context, value, _) => MaterialApp(
              theme: value.copyWith(platform: TargetPlatform.macOS),
              home: Scaffold(
                body: Directionality(
                  textDirection: direction,
                  child: MediaQuery(
                    data: const MediaQueryData(
                      textScaler: TextScaler.linear(2),
                    ),
                    child: Center(
                      child: DDropdownMenu(
                        content: const DDropdownMenuContent(
                          width: 220,
                          children: [
                            DDropdownMenuItem(
                              onPressed: _noop,
                              child: Text('First'),
                            ),
                            DDropdownMenuSeparator(),
                            DDropdownMenuItem(
                              onPressed: _noop,
                              child: Text('Last'),
                            ),
                          ],
                        ),
                        child: DDropdownMenuTrigger.button(
                          label: const Text('Open'),
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
      await open(tester);
      final separator = find.byType(DDropdownMenuSeparator);
      final element = tester.element(separator);
      for (final value in [
        AppTheme.light,
        AppTheme.dark,
        StyleguideTheme.forest.resolve(AppTheme.light),
        StyleguideTheme.plum.resolve(AppTheme.dark),
        for (final dark in [false, true])
          AppTheme.fromPalette(
            ResolvedSitePalette.fromJson({
              'primary': dark ? 0xFFDDDDDD : 0xFF222222,
              'secondary': dark ? 0xFF222222 : 0xFFFFFFFF,
              'tertiary': 0xFF0088CC,
              // Site content dividers can match the floating menu surface.
              'contentBorderColor': dark ? 0xFF303030 : 0xFFFFFFFF,
              'secondaryVeryHigh': dark ? 0xFF303030 : 0xFFFFFFFF,
            }),
          ),
      ]) {
        theme.value = value;
        await tester.pumpAndSettle();
        expect(tester.element(separator), same(element));
        final line = find.descendant(
          of: separator,
          matching: find.byType(ColoredBox),
        );
        final lineRect = tester.getRect(line);
        final menuRect = tester.getRect(find.byType(DDropdownMenuContent));
        expect(lineRect.width, menuRect.width);
        expect(lineRect.left, menuRect.left);
        expect(lineRect.height, 1);
        expect(tester.getSize(separator).height, 9);
        final boundary =
            capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final pixels = (await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            Color pixel(Offset point) {
              final local = boundary.globalToLocal(point) * 2;
              final index =
                  (local.dy.floor() * image.width + local.dx.floor()) * 4;
              return Color.fromARGB(
                data.getUint8(index + 3),
                data.getUint8(index),
                data.getUint8(index + 1),
                data.getUint8(index + 2),
              );
            }

            return [
              pixel(lineRect.center),
              pixel(Offset(lineRect.left + 2, lineRect.center.dy)),
              pixel(lineRect.center.translate(0, -2)),
            ];
          } finally {
            image.dispose();
          }
        }))!;
        expect(_contrast(pixels[0], pixels[2]), greaterThan(1.2));
        expect(pixels[1], pixels[0]);
        final tokens = DTokens.of(tester.element(separator));
        if (_contrast(tokens.border, tokens.surface) > 1.4) {
          expect(pixels[0], tokens.border);
        }
        expect(tester.takeException(), isNull);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        contains('Last'),
      );
    });
  }

  testWidgets(
    'pointer opens, focuses first enabled item, selects and restores',
    (tester) async {
      await pumpMenu(tester);
      await open(tester);
      expect(find.text('Disabled API'), findsOneWidget);
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        contains('Profile'),
      );

      await tester.tap(find.text('Billing'));
      await tester.pumpAndSettle();
      expect(find.text('Billing selected'), findsOneWidget);
      expect(find.text('Disabled API'), findsNothing);
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        contains('trigger'),
      );
    },
  );

  testWidgets('Return opens and arrows/Home/End skip disabled rows', (
    tester,
  ) async {
    await pumpMenu(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('Profile'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('Billing'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('Support'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('Profile'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('Support'),
    );
  });

  testWidgets('Space opens and focuses the first enabled row', (tester) async {
    await pumpMenu(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Disabled API'), findsOneWidget);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('Profile'),
    );
  });

  testWidgets('live labels, enabled state and focus nodes retain row order', (
    tester,
  ) async {
    final revision = ValueNotifier(0);
    final first = FocusNode(debugLabel: 'First original');
    final replacement = FocusNode(debugLabel: 'First replacement');
    final second = FocusNode(debugLabel: 'Second');
    addTearDown(revision.dispose);
    addTearDown(first.dispose);
    addTearDown(replacement.dispose);
    addTearDown(second.dispose);
    await pumpMenu(
      tester,
      child: ValueListenableBuilder<int>(
        valueListenable: revision,
        builder: (context, value, _) => DDropdownMenu(
          content: DDropdownMenuContent(
            children: [
              DDropdownMenuItem(
                focusNode: value < 2 ? first : replacement,
                onPressed: value == 1 ? null : () {},
                child: Text('First $value'),
              ),
              DDropdownMenuItem(
                focusNode: second,
                onPressed: () {},
                child: const Text('Second'),
              ),
            ],
          ),
          child: DDropdownMenuTrigger(
            builder: (context, menu) => DButton(
              focusNode: menu.focusNode,
              label: const Text('Open'),
              onPressed: menu.toggle,
            ),
          ),
        ),
      ),
    );
    await open(tester);
    expect(first.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    revision.value = 1;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    expect(second.hasFocus, isTrue);

    revision.value = 2;
    await tester.pump();
    expect(second.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    expect(replacement.hasFocus, isTrue);
    expect(first.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(second.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    expect(replacement.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('First 2'), findsNothing);
    // Borrowed nodes remain usable after the menu is unmounted.
    await tester.pumpWidget(const SizedBox.shrink());
    replacement.requestFocus();
    expect(tester.takeException(), isNull);
  });

  for (final autofocus in [true, false]) {
    testWidgets('deferred enabled items respect autofocus=$autofocus', (
      tester,
    ) async {
      final revision = ValueNotifier(0);
      final first = FocusNode(debugLabel: 'First');
      final second = FocusNode(debugLabel: 'Second');
      addTearDown(revision.dispose);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await pumpMenu(
        tester,
        child: DDropdownMenu(
          content: DDropdownMenuContent(
            autofocus: autofocus,
            children: [
              ValueListenableBuilder<int>(
                valueListenable: revision,
                builder: (context, value, _) => DDropdownMenuGroup(
                  children: [
                    DDropdownMenuItem(
                      focusNode: first,
                      onPressed: value == 0 ? null : () {},
                      child: Text('First $value'),
                    ),
                    DDropdownMenuItem(
                      focusNode: second,
                      onPressed: value == 0 ? null : () {},
                      child: Text('Second $value'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          child: DDropdownMenuTrigger(
            builder: (context, state) => DButton(
              label: const Text('Open'),
              onPressed: state.toggle,
              focusNode: state.focusNode,
            ),
          ),
        ),
      );
      await open(tester);
      expect(first.hasFocus, isFalse);
      expect(second.hasFocus, isFalse);
      revision.value = 1;
      await tester.pumpAndSettle();
      expect(first.hasFocus, autofocus);
      if (autofocus) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      revision.value = 2;
      await tester.pumpAndSettle();
      expect(first.hasFocus, isFalse);
      expect(second.hasFocus, autofocus);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('typeahead wraps from the active row', (tester) async {
    await pumpMenu(tester);
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('Settings'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('Support'),
    );
  });

  testWidgets('Space activates and disabled item cannot be activated', (
    tester,
  ) async {
    await pumpMenu(tester);
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Profile selected'), findsOneWidget);

    await open(tester);
    await tester.tap(find.text('Disabled API'));
    await tester.pump();
    expect(find.text('Disabled API'), findsOneWidget);
    expect(find.text('Profile selected'), findsOneWidget);
  });

  testWidgets('checkboxes and radio values are controlled and remain open', (
    tester,
  ) async {
    await pumpMenu(tester, child: const _ChoiceHarness());
    await open(tester);
    await tester.tap(find.text('Panel'));
    await tester.pump();
    expect(find.text('Panel: true'), findsOneWidget);
    expect(find.text('Top'), findsOneWidget);

    await tester.tap(find.text('Top'));
    await tester.pump();
    expect(find.text('Position: top'), findsOneWidget);
    expect(find.text('Bottom'), findsOneWidget);
  });

  testWidgets('choice rows reserve indicator space across state changes', (
    tester,
  ) async {
    await pumpMenu(tester, child: const _ChoiceHarness());
    await open(tester);
    final uncheckedWidth = tester.getSize(find.text('Panel')).width;

    await tester.tap(find.text('Panel'));
    await tester.pump();

    expect(tester.getSize(find.text('Panel')).width, uncheckedWidth);
  });

  testWidgets(
    'nested submenu opens directionally and deepest Escape closes first',
    (tester) async {
      await pumpMenu(tester, child: const _SubmenuHarness());
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        contains('Invite users'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Email'), findsOneWidget);
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        contains('Email'),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Email'), findsNothing);
      expect(find.text('Invite users'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Invite users'), findsNothing);
    },
  );

  testWidgets('clicking a hover-open submenu keeps it open', (tester) async {
    await pumpMenu(tester, child: const _SubmenuHarness());
    await open(tester);
    final trigger = find.text('Invite users');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();

    await mouse.moveTo(tester.getCenter(trigger));
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsOneWidget);

    await mouse.down(tester.getCenter(trigger));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsOneWidget);
  });

  testWidgets('nested Escape wins over an ancestor shortcut', (tester) async {
    var ancestorEscapes = 0;
    await pumpMenu(
      tester,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            ancestorEscapes += 1;
          },
        },
        child: const _SubmenuHarness(),
      ),
    );
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsNothing);
    expect(find.text('Invite users'), findsOneWidget);
    expect(ancestorEscapes, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Invite users'), findsNothing);
    expect(ancestorEscapes, 0);
  });

  testWidgets('RTL mirrors submenu directional navigation', (tester) async {
    await pumpMenu(
      tester,
      direction: TextDirection.rtl,
      child: const _SubmenuHarness(),
    );
    await open(tester);
    final chevron = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.size == const Size.square(16) &&
          widget.painter.runtimeType.toString() == '_ChevronPainter',
    );
    expect(chevron, findsOneWidget);
    expect(Directionality.of(tester.element(chevron)), TextDirection.rtl);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsNothing);
  });

  testWidgets('submenu uses the reference 96px minimum width by default', (
    tester,
  ) async {
    await pumpMenu(tester, child: const _SubmenuHarness());
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(find.byType(DPopoverContent), findsNWidgets(2));
    expect(
      tester.getSize(find.byType(DPopoverContent).last).width,
      closeTo(96, 0.1),
    );

    BoxDecoration surfaceDecoration(Finder content) => tester
        .widgetList<DecoratedBox>(
          find.descendant(of: content, matching: find.byType(DecoratedBox)),
        )
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.boxShadow?.isNotEmpty == true);
    final rootShadow = surfaceDecoration(find.byType(DPopoverContent).first);
    final submenuShadow = surfaceDecoration(find.byType(DPopoverContent).last);
    expect(rootShadow.boxShadow!.first.offset, const Offset(0, 4));
    expect(rootShadow.boxShadow!.first.blurRadius, 6);
    expect(submenuShadow.boxShadow!.first.offset, const Offset(0, 10));
    expect(submenuShadow.boxShadow!.first.blurRadius, 15);
  });

  testWidgets('active rows use the paired accent foreground', (tester) async {
    const activeForeground = Color(0xFF006600);
    const restingForeground = Color(0xFF111111);
    const mutedForeground = Color(0xFF666666);
    final base = ThemeData.light();
    final colors = base.colorScheme.copyWith(
      onSurface: restingForeground,
      onSurfaceVariant: mutedForeground,
    );
    final theme = base.copyWith(
      colorScheme: colors,
      extensions: [
        DTokens(
          colors: colors,
          background: Colors.white,
          surface: Colors.white,
          muted: const Color(0xFFF5F5F5),
          border: const Color(0xFFE5E5E5),
          hover: const Color(0xFFEEEEEE),
          selected: const Color(0xFFEEEEEE),
          selectedForeground: activeForeground,
        ),
      ],
    );
    await pumpMenu(tester, theme: theme, child: const _ShortcutColorHarness());
    await open(tester);

    expect(
      DefaultTextStyle.of(tester.element(find.text('Profile'))).style.color,
      activeForeground,
    );
    expect(tester.widget<Text>(find.text('⌘P')).style?.color, activeForeground);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      DefaultTextStyle.of(tester.element(find.text('Profile'))).style.color,
      restingForeground,
    );
    expect(tester.widget<Text>(find.text('⌘P')).style?.color, mutedForeground);
  });

  testWidgets('a fitting menu has no scroll viewport or scrollbar', (
    tester,
  ) async {
    await pumpMenu(tester);
    await open(tester);

    expect(find.byType(DScrollViewport), findsNothing);
    expect(find.byType(DScrollBar), findsNothing);
    final initialTop = tester.getTopLeft(find.text('Profile')).dy;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.text('Profile')),
        scrollDelta: const Offset(0, 60),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Profile')).dy, initialTop);
  });

  testWidgets('menu focus scrolls its popup without moving the host page', (
    tester,
  ) async {
    final pageScroll = ScrollController();
    addTearDown(pageScroll.dispose);
    await pumpMenu(
      tester,
      child: SingleChildScrollView(
        controller: pageScroll,
        child: Column(
          children: [
            const SizedBox(height: 150),
            SizedBox(
              width: 360,
              height: 360,
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => Center(
                    child: DDropdownMenu(
                      content: DDropdownMenuContent(
                        constraints: const BoxConstraints(maxHeight: 120),
                        children: [
                          for (var index = 0; index < 20; index++)
                            DDropdownMenuItem(
                              onPressed: () {},
                              child: Text('Command $index'),
                            ),
                        ],
                      ),
                      child: DDropdownMenuTrigger(
                        builder: (context, state) => DButton(
                          label: const Text('Open'),
                          onPressed: state.toggle,
                          focusNode: state.focusNode,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 1000),
          ],
        ),
      ),
    );
    await open(tester);
    expect(pageScroll.offset, 0);
    expect(find.byType(DScrollViewport), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(pageScroll.offset, 0);
    final menuScroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(DScrollViewport),
        matching: find.byType(Scrollable),
      ),
    );
    expect(menuScroll.position.pixels, greaterThan(0));
    final popup = tester.getRect(find.byType(DPopoverContent));
    final lastItem = tester.getRect(find.text('Command 19'));
    expect(lastItem.top, greaterThanOrEqualTo(popup.top));
    expect(lastItem.bottom, lessThanOrEqualTo(popup.bottom));
  });

  testWidgets(
    'only an overflowing menu gains a draggable scrollbar and wheel input',
    (tester) async {
      await pumpMenu(
        tester,
        child: DDropdownMenu(
          content: DDropdownMenuContent(
            constraints: const BoxConstraints(maxHeight: 120),
            children: [
              for (var index = 0; index < 20; index++)
                DDropdownMenuItem(
                  onPressed: _noop,
                  child: Text('Scrollable command $index'),
                ),
            ],
          ),
          child: DDropdownMenuTrigger(
            builder: (context, state) => DButton(
              label: const Text('Open'),
              onPressed: state.toggle,
              focusNode: state.focusNode,
            ),
          ),
        ),
      );
      await open(tester);

      expect(find.byType(DScrollBar), findsOneWidget);
      expect(find.byType(DScrollViewport), findsOneWidget);
      final scrollbar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
      expect(scrollbar.thumbVisibility, isTrue);
      expect(scrollbar.interactive, isTrue);
      final area = tester.getRect(find.byType(DScrollViewport));
      final initialTop = tester
          .getTopLeft(find.text('Scrollable command 0'))
          .dy;

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: area.center,
          scrollDelta: const Offset(0, 60),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('Scrollable command 0')).dy,
        lessThan(initialTop),
      );
    },
  );

  testWidgets('collision-constrained menus scroll without an explicit height', (
    tester,
  ) async {
    await pumpMenu(
      tester,
      child: DDropdownMenu(
        content: DDropdownMenuContent(
          children: [
            for (var index = 0; index < 14; index++)
              DDropdownMenuItem(
                onPressed: _noop,
                child: Text('Command $index'),
              ),
          ],
        ),
        child: DDropdownMenuTrigger(
          builder: (context, state) => DButton(
            label: const Text('Open'),
            onPressed: state.toggle,
            focusNode: state.focusNode,
          ),
        ),
      ),
    );
    await open(tester);
    expect(find.byType(DScrollViewport), findsOneWidget);
    final viewport = tester.getRect(find.byType(DScrollViewport));
    final firstTop = tester.getTopLeft(find.text('Command 0')).dy;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: viewport.center,
        scrollDelta: const Offset(0, 60),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Command 0')).dy, lessThan(firstTop));

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    final lastItem = tester.getRect(find.text('Command 13'));
    expect(lastItem.top, greaterThanOrEqualTo(viewport.top));
    expect(lastItem.bottom, lessThanOrEqualTo(viewport.bottom));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('pointer movement leaves exactly one row highlighted', (
    tester,
  ) async {
    await pumpMenu(tester);
    await open(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.text('Billing')));
    await tester.pump();

    Color rowColor(String label) {
      final row = tester.widget<Container>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container && widget.decoration is BoxDecoration,
              ),
            )
            .first,
      );
      return (row.decoration! as BoxDecoration).color!;
    }

    expect(rowColor('Profile'), Colors.transparent);
    expect(rowColor('Billing'), isNot(Colors.transparent));

    await mouse.moveTo(tester.getCenter(find.text('Support')));
    await tester.pump();
    expect(rowColor('Support'), isNot(Colors.transparent));

    // Keyboard input takes over even while the mouse stays on another row.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('Billing'));
    expect(rowColor('Billing'), isNot(Colors.transparent));
    expect(rowColor('Support'), Colors.transparent);

    await mouse.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(rowColor('Support'), isNot(Colors.transparent));
    expect(rowColor('Billing'), Colors.transparent);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(rowColor('Support'), Colors.transparent);
    expect(rowColor('Billing'), Colors.transparent);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(rowColor('Profile'), isNot(Colors.transparent));
  });

  testWidgets('hovering a partially visible row keeps scroll position', (
    tester,
  ) async {
    await pumpMenu(
      tester,
      child: DDropdownMenu(
        content: DDropdownMenuContent(
          constraints: const BoxConstraints(maxHeight: 110),
          children: [
            for (var index = 0; index < 10; index++)
              DDropdownMenuItem(
                onPressed: _noop,
                child: Text('Hover command $index'),
              ),
          ],
        ),
        child: DDropdownMenuTrigger(
          builder: (context, state) => DButton(
            label: const Text('Open'),
            onPressed: state.toggle,
            focusNode: state.focusNode,
          ),
        ),
      ),
    );
    await open(tester);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(DScrollViewport),
        matching: find.byType(Scrollable),
      ),
    );
    final viewport = tester.getRect(find.byType(DScrollViewport));
    Finder row(int index) => find
        .ancestor(
          of: find.text('Hover command $index'),
          matching: find.byWidgetPredicate(
            (widget) => widget is MouseRegion && widget.onEnter != null,
          ),
        )
        .first;
    final partialRow = List.generate(10, (index) => row(index)).firstWhere((
      row,
    ) {
      final rect = tester.getRect(row);
      return rect.top < viewport.bottom && rect.bottom > viewport.bottom;
    });
    final partialRect = tester.getRect(partialRow);
    final initialOffset = scrollable.position.pixels;
    final initialFocus = FocusManager.instance.primaryFocus;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();

    await mouse.moveTo(Offset(partialRect.center.dx, viewport.bottom - 2));
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, initialOffset);
    expect(FocusManager.instance.primaryFocus, same(initialFocus));
    final visual = tester.widget<Container>(
      find
          .descendant(
            of: partialRow,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container && widget.decoration is BoxDecoration,
            ),
          )
          .first,
    );
    expect(
      (visual.decoration! as BoxDecoration).color,
      isNot(Colors.transparent),
    );
  });

  testWidgets('opening a sibling submenu closes the previous overlay', (
    tester,
  ) async {
    await pumpMenu(tester, child: const _SiblingSubmenuHarness());
    await open(tester);
    await tester.tap(find.text('Invite users'));
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsOneWidget);
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsNothing);
    expect(find.text('PDF'), findsOneWidget);
  });

  testWidgets('outside pointer dismisses without stealing outside focus', (
    tester,
  ) async {
    final outside = FocusNode(debugLabel: 'Outside');
    addTearDown(outside.dispose);
    await pumpMenu(
      tester,
      child: Stack(
        children: [
          const Center(child: _MenuHarness()),
          Align(
            alignment: Alignment.topLeft,
            child: Listener(
              onPointerDown: (_) => outside.requestFocus(),
              child: TextButton(
                focusNode: outside,
                onPressed: () {},
                child: const Text('Outside'),
              ),
            ),
          ),
        ],
      ),
    );
    await open(tester);
    await tester.tap(find.text('Outside'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Disabled API'), findsNothing);
    expect(outside.hasFocus, isTrue);
  });

  testWidgets('controlled state requests changes without mutating itself', (
    tester,
  ) async {
    final changes = <bool>[];
    await pumpMenu(
      tester,
      child: DDropdownMenu(
        open: false,
        onOpenChange: (open, _) => changes.add(open),
        content: const DDropdownMenuContent(
          children: [DDropdownMenuItem(onPressed: null, child: Text('Item'))],
        ),
        child: DDropdownMenuTrigger(
          builder: (context, state) => DButton(
            label: const Text('Open'),
            onPressed: state.toggle,
            focusNode: state.focusNode,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(changes, [true]);
    expect(find.text('Item'), findsNothing);
  });

  testWidgets('lifecycle suspension dismisses an uncontrolled menu', (
    tester,
  ) async {
    await pumpMenu(tester);
    await open(tester);
    expect(find.text('Disabled API'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Disabled API'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Disabled API'), findsNothing);
  });

  testWidgets('live theme and text scaling preserve open choice state', (
    tester,
  ) async {
    await tester.pumpWidget(const _LiveEnvironment());
    await tester.pump();
    await open(tester);
    await tester.tap(find.text('Panel'));
    await tester.pump();
    await tester.tap(find.text('Theme'));
    await tester.pump();
    expect(find.text('Panel: true'), findsOneWidget);
    expect(find.text('Panel'), findsOneWidget);
    await tester.tap(find.text('Scale'));
    await tester.pump();
    expect(find.text('Panel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop row geometry stays compact', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pumpMenu(tester);
      await open(tester);
      expect(
        tester.getSize(find.text('Profile').first).height,
        closeTo(20, 0.1),
      );
      final profile = tester.getRect(find.text('Profile').first);
      final billing = tester.getRect(find.text('Billing').first);
      expect(billing.top - profile.top, closeTo(28, 0.1));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop items retain the reference default cursor', (
    tester,
  ) async {
    await pumpMenu(tester);
    await open(tester);
    final regions = tester.widgetList<MouseRegion>(
      find.ancestor(
        of: find.text('Profile'),
        matching: find.byType(MouseRegion),
      ),
    );
    final itemRegion = regions.firstWhere((region) => region.onEnter != null);

    expect(itemRegion.cursor, SystemMouseCursors.basic);
  });

  testWidgets('iOS rows expose 48px touch bounds without changing typography', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpMenu(tester);
      await open(tester);
      final profile = tester.getRect(find.text('Profile').first);
      final billing = tester.getRect(find.text('Billing').first);
      expect(billing.top - profile.top, closeTo(48, 0.1));
      expect(profile.height, closeTo(20, 0.1));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('semantics expose popup, enabled, checked, and radio state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpMenu(tester, child: const _ChoiceHarness());
    await open(tester);
    expect(
      tester.getSemantics(find.text('Panel')),
      matchesSemantics(
        label: 'Panel',
        hasEnabledState: true,
        isEnabled: true,
        hasCheckedState: true,
        isChecked: false,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('Bottom')),
      matchesSemantics(
        label: 'Bottom',
        hasEnabledState: true,
        isEnabled: true,
        hasCheckedState: true,
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance() + 0.05;
  final b = second.computeLuminance() + 0.05;
  return a > b ? a / b : b / a;
}

class _MenuHarness extends StatefulWidget {
  const _MenuHarness();

  @override
  State<_MenuHarness> createState() => _MenuHarnessState();
}

class _MenuHarnessState extends State<_MenuHarness> {
  String _status = 'None';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DDropdownMenu(
        content: DDropdownMenuContent(
          children: [
            for (final label in ['Profile', 'Billing', 'Settings', 'Support'])
              DDropdownMenuItem(
                onPressed: () => setState(() => _status = '$label selected'),
                child: Text(label),
              ),
            const DDropdownMenuItem(
              onPressed: null,
              child: Text('Disabled API'),
            ),
          ],
        ),
        child: DDropdownMenuTrigger(
          builder: (context, state) => DButton(
            label: const Text('Open'),
            variant: DButtonVariant.outline,
            hasPopup: true,
            expanded: state.open,
            focusNode: state.focusNode,
            onPressed: state.toggle,
          ),
        ),
      ),
      Text(_status),
    ],
  );
}

class _ChoiceHarness extends StatefulWidget {
  const _ChoiceHarness();

  @override
  State<_ChoiceHarness> createState() => _ChoiceHarnessState();
}

class _ChoiceHarnessState extends State<_ChoiceHarness> {
  bool _panel = false;
  String _position = 'bottom';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DDropdownMenu(
        content: DDropdownMenuContent(
          children: [
            DDropdownMenuCheckboxItem(
              checked: _panel,
              onChanged: (value) => setState(() => _panel = value),
              child: const Text('Panel'),
            ),
            DDropdownMenuRadioGroup<String>(
              value: _position,
              onChanged: (value) => setState(() => _position = value),
              children: const [
                DDropdownMenuRadioItem(value: 'top', child: Text('Top')),
                DDropdownMenuRadioItem(value: 'bottom', child: Text('Bottom')),
              ],
            ),
          ],
        ),
        child: DDropdownMenuTrigger(
          builder: (context, state) => DButton(
            label: const Text('Open'),
            onPressed: state.toggle,
            focusNode: state.focusNode,
          ),
        ),
      ),
      Text('Panel: $_panel'),
      Text('Position: $_position'),
    ],
  );
}

class _SubmenuHarness extends StatelessWidget {
  const _SubmenuHarness();

  @override
  Widget build(BuildContext context) => DDropdownMenu(
    content: const DDropdownMenuContent(
      children: [
        DDropdownMenuItem(onPressed: _noop, child: Text('Team')),
        DDropdownMenuSub(
          trigger: Text('Invite users'),
          children: [
            DDropdownMenuItem(onPressed: _noop, child: Text('Email')),
            DDropdownMenuItem(onPressed: _noop, child: Text('Message')),
          ],
        ),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, state) => DButton(
        label: const Text('Open'),
        onPressed: state.toggle,
        focusNode: state.focusNode,
      ),
    ),
  );
}

class _ShortcutColorHarness extends StatelessWidget {
  const _ShortcutColorHarness();

  @override
  Widget build(BuildContext context) => DDropdownMenu(
    content: const DDropdownMenuContent(
      children: [
        DDropdownMenuItem(
          onPressed: _noop,
          trailing: DDropdownMenuShortcut('⌘P'),
          child: Text('Profile'),
        ),
        DDropdownMenuItem(onPressed: _noop, child: Text('Billing')),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, state) => DButton(
        label: const Text('Open'),
        onPressed: state.toggle,
        focusNode: state.focusNode,
      ),
    ),
  );
}

class _SiblingSubmenuHarness extends StatelessWidget {
  const _SiblingSubmenuHarness();

  @override
  Widget build(BuildContext context) => DDropdownMenu(
    content: const DDropdownMenuContent(
      children: [
        DDropdownMenuSub(
          trigger: Text('Invite users'),
          children: [DDropdownMenuItem(onPressed: _noop, child: Text('Email'))],
        ),
        DDropdownMenuSub(
          trigger: Text('Export'),
          children: [DDropdownMenuItem(onPressed: _noop, child: Text('PDF'))],
        ),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, state) => DButton(
        label: const Text('Open'),
        onPressed: state.toggle,
        focusNode: state.focusNode,
      ),
    ),
  );
}

void _noop() {}

class _LiveEnvironment extends StatefulWidget {
  const _LiveEnvironment();

  @override
  State<_LiveEnvironment> createState() => _LiveEnvironmentState();
}

class _LiveEnvironmentState extends State<_LiveEnvironment> {
  bool _dark = false;
  bool _large = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: _dark ? ThemeData.dark() : ThemeData.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(_large ? 2 : 1)),
      child: child!,
    ),
    home: Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () => setState(() => _dark = !_dark),
            child: const Text('Theme'),
          ),
          TextButton(
            onPressed: () => setState(() => _large = !_large),
            child: const Text('Scale'),
          ),
          const _ChoiceHarness(),
        ],
      ),
    ),
  );
}
