import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/button_surface.dart';

void main() {
  testWidgets('chat message action matches compact mockup geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Center(
            child: DButton.iconOnly(
              density: DButtonDensity.chatMessageAction,
              variant: DButtonVariant.transparentBackground,
              icon: const Icon(Icons.add_reaction),
              tooltip: 'Add reaction',
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    final surface = find.byWidgetPredicate(
      (widget) =>
          widget is AnimatedContainer && widget.decoration is DButtonDecoration,
    );
    expect(tester.getSize(surface), const Size.square(26));
    expect(
      tester.getSize(find.byIcon(Icons.add_reaction)),
      const Size.square(16),
    );
    expect(buttonSurface(tester).borderRadius, BorderRadius.circular(6));
  });

  testWidgets('dashed tile fills its row and keeps one button target', (
    tester,
  ) async {
    var presses = 0;
    Future<void> pump(double scale) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SizedBox(
              width: 320,
              child: DButton(
                label: const Text('New theme'),
                icon: const Icon(Icons.add),
                variant: DButtonVariant.dashedTile,
                alignment: AlignmentDirectional.centerStart,
                onPressed: () => presses++,
              ),
            ),
          ),
        ),
      ),
    );
    await pump(1);
    final button = find.byType(DButton);
    expect(tester.getSize(button), const Size(320, 50));
    expect(buttonSurface(tester).dashed, isTrue);
    final iconFrame = find.descendant(
      of: button,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is DButtonDecoration &&
            (widget.decoration as DButtonDecoration).dashed,
      ),
    );
    expect(tester.getSize(iconFrame.last), const Size(34, 34));
    await tester.tapAt(tester.getRect(button).centerRight - const Offset(2, 0));
    await tester.pump();
    expect(presses, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 2);
    await pump(2);
    expect(tester.getSize(button).height, greaterThan(50));
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    for (final iconOnly in [true, false]) {
      testWidgets(
        'compact toolbar retains touch targets ($platform, icon: $iconOnly)',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            var presses = 0;
            Future<void> pump({
              double scale = 1,
              bool loading = false,
              bool disabled = false,
            }) => tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.dark.copyWith(platform: platform),
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: Center(
                      child: iconOnly
                          ? DButton.iconOnly(
                              icon: const Icon(Icons.bookmark),
                              tooltip: 'Bookmark',
                              density: DButtonDensity.compactToolbar,
                              variant: DButtonVariant.outline,
                              loading: loading,
                              onPressed: disabled ? null : () => presses++,
                            )
                          : DButton(
                              icon: const Icon(Icons.bookmark),
                              label: const Text('Bookmark'),
                              density: DButtonDensity.compactToolbar,
                              variant: DButtonVariant.outline,
                              loading: loading,
                              onPressed: disabled ? null : () => presses++,
                            ),
                    ),
                  ),
                ),
              ),
            );
            await pump();
            final button = find.byType(DButton);
            final surface = find.byWidgetPredicate(
              (widget) =>
                  widget is AnimatedContainer &&
                  widget.decoration is DButtonDecoration,
            );
            final target = tester.getRect(button);
            expect(target.height, 48);
            expect(target.width, greaterThanOrEqualTo(48));
            expect(tester.getSize(surface).height, 24);
            if (iconOnly) expect(tester.getSize(surface).width, 32);
            expect(
              tester.getSize(find.byIcon(Icons.bookmark)),
              const Size(14, 14),
            );
            expect(tester.getSemantics(button).rect.size, target.size);
            final edge = target.topLeft + const Offset(2, 2);
            expect(tester.getRect(surface).contains(edge), isFalse);
            await tester.tapAt(edge);
            await tester.pump();
            expect(presses, 1);
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pump();
            expect(presses, 2);
            await pump(scale: 2);
            expect(tester.getSize(surface).height, greaterThan(24));
            expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
            expect(tester.takeException(), isNull);
            await pump(disabled: true);
            await tester.tap(button);
            await tester.pump();
            expect(presses, 2);
            await pump(loading: true);
            await tester.tap(button);
            await tester.pump();
            expect(presses, 2);
            expect(find.byType(DSpinner), findsOneWidget);
            expect(tester.getSize(surface).height, 24);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets(
      'composer density preserves icons and limits only desktop width $platform',
      (tester) async {
        var presses = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: platform),
            home: Scaffold(
              body: Center(
                child: DButton.iconOnly(
                  density: DButtonDensity.composerBlock,
                  icon: const Icon(Icons.add),
                  tooltip: 'Add block',
                  onPressed: () => presses++,
                ),
              ),
            ),
          ),
        );
        final button = find.byType(DButton);
        final desktop = platform == TargetPlatform.macOS;
        expect(
          tester.getSize(button),
          desktop ? const Size(20, 34) : const Size(48, 48),
        );
        expect(tester.getSize(find.byIcon(Icons.add)), const Size(14, 14));
        final rect = tester.getRect(button);
        await tester.tapAt(rect.centerLeft + const Offset(1, 0));
        await tester.pump();
        expect(presses, 1);
        await tester.tapAt(rect.centerLeft - const Offset(1, 0));
        await tester.pump();
        expect(presses, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(presses, 2);
      },
    );
  }

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'icon shape retargets smoothly with reduced motion $reducedMotion',
      (tester) async {
        var selected = false;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reducedMotion),
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return Center(
                    child: DButton.iconOnly(
                      density: DButtonDensity.mobileNavigation,
                      shape: selected
                          ? DButtonShape.rounded
                          : DButtonShape.pill,
                      borderRadius: selected ? BorderRadius.circular(14) : null,
                      variant: DButtonVariant.ghost,
                      animationDuration: const Duration(milliseconds: 240),
                      icon: const Icon(Icons.forum),
                      tooltip: 'Topics',
                      onPressed: () {},
                    ),
                  );
                },
              ),
            ),
          ),
        );
        final painted = find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox && widget.decoration is DButtonDecoration,
        );
        double radius() =>
            (tester.widget<DecoratedBox>(painted).decoration
                    as DButtonDecoration)
                .borderRadius
                .topLeft
                .x;
        expect(radius(), 22);
        update(() => selected = true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        if (reducedMotion) {
          expect(radius(), 14);
        } else {
          expect(radius(), inExclusiveRange(14, 22));
        }
        final interruptedRadius = radius();
        update(() => selected = false);
        await tester.pump();
        if (reducedMotion) {
          expect(radius(), 22);
        } else {
          expect(radius(), closeTo(interruptedRadius, .001));
          await tester.pump(const Duration(milliseconds: 60));
          expect(radius(), inExclusiveRange(interruptedRadius, 22));
        }
        await tester.pumpAndSettle();
        expect(radius(), 22);
      },
    );
  }

  testWidgets('an icon-only dock action fills its slot around a centred icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              child: DButton.iconOnly(
                density: DButtonDensity.mobileDockAction,
                shape: DButtonShape.pill,
                icon: const Icon(Icons.add),
                tooltip: 'New topic',
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
    final surface = find.byWidgetPredicate(
      (widget) =>
          widget is AnimatedContainer && widget.decoration is DButtonDecoration,
    );
    final icon = find.byIcon(Icons.add);
    expect(tester.getSize(surface), const Size(160, 44));
    expect(tester.getSize(icon), const Size(20, 20));
    expect(tester.getCenter(icon), tester.getCenter(surface));
    expect(tester.getSemantics(find.byType(DButton)).label, 'New topic');
  });

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    testWidgets('mobile navigation geometry and activation on $platform', (
      tester,
    ) async {
      var presses = 0;
      Future<void> pump(double scale) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: platform),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Center(
                child: DButton.iconOnly(
                  density: DButtonDensity.mobileNavigation,
                  icon: const Icon(Icons.forum),
                  tooltip: 'Topics',
                  onPressed: () => presses++,
                ),
              ),
            ),
          ),
        ),
      );
      await pump(1);
      final surface = find.byWidgetPredicate(
        (widget) =>
            widget is AnimatedContainer &&
            widget.decoration is DButtonDecoration,
      );
      expect(tester.getSize(surface), const Size(44, 44));
      expect(tester.getSize(find.byIcon(Icons.forum)), const Size(18, 18));
      expect(tester.getSize(find.byType(DButton)), const Size(48, 48));
      // The padded target outside the painted surface must still activate.
      await tester.tapAt(
        tester.getTopLeft(find.byType(DButton)) + const Offset(1, 24),
      );
      await tester.pump();
      expect(presses, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(presses, 2);
      await pump(3);
      expect(tester.getSize(surface).height, greaterThan(44));
      expect(tester.takeException(), isNull);
    });
  }

  for (final direction in TextDirection.values) {
    testWidgets('inline actions align with surrounding text in $direction', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Topic content'),
                  DButton(
                    label: const Text('Replies'),
                    variant: DButtonVariant.inline,
                    size: DButtonSize.small,
                    onPressed: () => presses++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final content = tester.getRect(find.text('Topic content'));
      final label = tester.getRect(find.text('Replies'));
      expect(
        direction == TextDirection.ltr ? label.left : label.right,
        direction == TextDirection.ltr ? content.left : content.right,
      );
      expect(tester.getSize(find.byType(DButton)).height, 24);
      expect(buttonSurface(tester).color, Colors.transparent);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(presses, 1);
    });
  }

  for (final dark in [false, true]) {
    for (final variant in DButtonVariant.values) {
      testWidgets(
        'hover fill is stable from its first frame ($dark, $variant)',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
                platform: TargetPlatform.macOS,
              ),
              home: Scaffold(
                body: Center(
                  child: DButton(
                    variant: variant,
                    label: const Text('Personal'),
                    onPressed: _noop,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          Color paintedFill() => tester
              .widgetList<DecoratedBox>(find.byType(DecoratedBox))
              .map((box) => box.decoration)
              .whereType<DButtonDecoration>()
              .single
              .color;
          for (var visit = 0; visit < 2; visit++) {
            await mouse.moveTo(tester.getCenter(find.byType(DButton)));
            await tester.pump();
            final hover = buttonSurface(tester).color;
            for (final elapsed in [0, 16, 32, 75, 150]) {
              await tester.pump(Duration(milliseconds: elapsed));
              expect(paintedFill(), hover, reason: 'entry frame +$elapsed ms');
            }
            await mouse.moveTo(Offset.zero);
            await tester.pump();
            expect(paintedFill(), buttonSurface(tester).color);
            await tester.pump(const Duration(milliseconds: 16));
          }
        },
      );
    }
  }

  for (final dark in [false, true]) {
    for (final grouped in [false, true]) {
      testWidgets(
        'adjacent buttons clear hover independently (dark: $dark, grouped: $grouped)',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
                platform: TargetPlatform.macOS,
              ),
              home: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (context) {
                      final children = [
                        for (var i = 0; i < 3; i++)
                          DButton.iconOnly(
                            key: ValueKey('button-$i'),
                            tooltip: 'Button $i',
                            variant: DButtonVariant.ghost,
                            onPressed: _noop,
                            icon: const Icon(Icons.settings),
                          ),
                      ];
                      return grouped
                          ? DButtonGroup(children: children)
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final child in children)
                                  Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: child,
                                  ),
                              ],
                            );
                    },
                  ),
                ),
              ),
            ),
          );
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          for (var active = 0; active < 3; active++) {
            await mouse.moveTo(
              tester.getCenter(find.byKey(ValueKey('button-$active'))),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 16));
            for (var i = 0; i < 3; i++) {
              final painted = tester
                  .widgetList<DecoratedBox>(
                    find.descendant(
                      of: find.byKey(ValueKey('button-$i')),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .map((box) => box.decoration)
                  .whereType<DButtonDecoration>()
                  .single;
              expect(
                painted.color.a,
                i == active ? greaterThan(0) : 0,
                reason: 'hover $active, button $i',
              );
            }
            await tester.pumpAndSettle();
          }
          await mouse.removePointer();
          await tester.pumpAndSettle();
        },
      );
    }
  }

  testWidgets('Native text sizes retain compact surfaces', (tester) async {
    for (final (size, height, font, icon) in [
      (DButtonSize.small, 24.0, 12.5, 12.0),
      (DButtonSize.regular, 34.0, 13.0, 14.0),
      (DButtonSize.large, 40.0, 14.0, 16.0),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Center(
              child: DButton(
                label: const Text('Action'),
                icon: const Icon(Icons.add),
                onPressed: _noop,
                size: size,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rendered = find.byType(FilledButton);
      expect(tester.getSize(rendered).height, height);
      expect(tester.getSize(find.byIcon(Icons.add)), Size.square(icon));
      expect(DButton.fontSizeFor(size), font);
      expect(
        tester
            .widget<FilledButton>(rendered)
            .style!
            .textStyle!
            .resolve({})!
            .fontSize,
        font,
      );
    }
  });

  testWidgets(
    'primary actions use the pill radius and ordinary buttons use 8px',
    (tester) async {
      for (final (variant, expected) in [
        (DButtonVariant.primary, DRadius.pill),
        (DButtonVariant.outline, DRadius.control),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: DButton(
                label: const Text('Action'),
                variant: variant,
                onPressed: _noop,
              ),
            ),
          ),
        );
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        final shape =
            button.style!.shape!.resolve({})! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(expected));
      }
    },
  );

  testWidgets(
    'flat icon buttons use the fixed control radius and standard sizes',
    (tester) async {
      for (final (radius, size) in [
        (0.0, DButtonSize.small),
        (13.0, DButtonSize.regular),
        (0.0, DButtonSize.large),
      ]) {
        final base = AppTheme.light.copyWith(platform: TargetPlatform.macOS);
        final theme = base.copyWith(
          extensions: [
            ...base.extensions.values.where((value) => value is! DTokens),
            DTokens.fromTheme(base).copyWith(radius: radius),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            themeAnimationDuration: Duration.zero,
            home: Scaffold(
              body: Center(
                child: DButton.iconOnly(
                  tooltip: 'Action',
                  onPressed: _noop,
                  variant: DButtonVariant.flat,
                  size: size,
                  icon: const Icon(Icons.add),
                ),
              ),
            ),
          ),
        );

        final rendered = find.byType(FilledButton);
        final surface = find.descendant(
          of: rendered,
          matching: find.byType(Material),
        );
        final style = tester.widget<FilledButton>(rendered).style!;
        final shape = style.shape!.resolve({WidgetState.hovered});
        final targetDimension = DButton.iconOnlyDimensionFor(size);

        expect(tester.getSize(rendered), Size.square(targetDimension));
        expect(surface, findsOneWidget);
        expect(tester.getSize(surface), Size.square(targetDimension));
        expect(shape, isA<RoundedRectangleBorder>());
        expect(
          (shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(DRadius.control),
        );
        expect(buttonSurface(tester).color, Colors.transparent);
        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await pointer.addPointer(location: Offset.zero);
        await pointer.moveTo(tester.getCenter(surface));
        await tester.pump();
        expect(
          buttonSurface(tester).color,
          DTokens.of(tester.element(rendered)).buttonTheme.accent.hover,
        );
        await pointer.removePointer();
      }
    },
  );

  testWidgets('touch target outside the compact surface remains interactive', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: DButton.iconOnly(
              tooltip: 'Action',
              onPressed: () => presses++,
              variant: DButtonVariant.flat,
              icon: const Icon(Icons.add),
            ),
          ),
        ),
      ),
    );

    final rendered = find.byType(FilledButton);
    final surface = find.descendant(
      of: rendered,
      matching: find.byType(Material),
    );
    final targetRect = tester.getRect(rendered);
    final surfaceRect = tester.getRect(surface);
    final paddedPoint = Offset(targetRect.left + 1, targetRect.center.dy);

    expect(surfaceRect.contains(paddedPoint), isFalse);
    expect(buttonSurface(tester).color, Colors.transparent);

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer();
    await pointer.moveTo(paddedPoint);
    await tester.pump();

    expect(
      buttonSurface(tester).color,
      DTokens.of(tester.element(rendered)).buttonTheme.accent.hover,
    );

    await tester.tapAt(paddedPoint);
    await tester.pump();
    expect(presses, 1);
  });

  testWidgets('buttons can override the radius for joined controls', (
    tester,
  ) async {
    const radius = BorderRadius.horizontal(left: Radius.circular(8));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(
            child: DButton(
              label: Text('Action'),
              onPressed: _noop,
              borderRadius: radius,
            ),
          ),
        ),
      ),
    );

    final rendered = tester.widget<FilledButton>(find.byType(FilledButton));
    final shape = rendered.style!.shape!.resolve({});

    expect(shape, isA<RoundedRectangleBorder>());
    expect((shape! as RoundedRectangleBorder).borderRadius, radius);
  });

  testWidgets('buttons use pointer and default cursors by enabled state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Column(
            children: [
              DButton(label: Text('Action'), onPressed: _noop),
              DButton.iconOnly(
                tooltip: 'Icon action',
                onPressed: _noop,
                icon: Icon(Icons.add),
              ),
            ],
          ),
        ),
      ),
    );

    for (final button in tester.widgetList<FilledButton>(
      find.byType(FilledButton),
    )) {
      expect(button.style!.mouseCursor!.resolve({}), SystemMouseCursors.click);
      expect(
        button.style!.mouseCursor!.resolve({WidgetState.disabled}),
        SystemMouseCursors.basic,
      );
    }
  });

  testWidgets('interactive background can stay transparent', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: DButton.iconOnly(
              tooltip: 'Action',
              onPressed: _noop,
              variant: DButtonVariant.flat,
              interactiveBackgroundColor: Colors.transparent,
              focusNode: focus,
              icon: const Icon(Icons.add),
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(FilledButton));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(center);
    await tester.pump();
    expect(buttonSurface(tester).color, Colors.transparent, reason: 'hover');
    await mouse.down(center);
    await tester.pump();
    expect(buttonSurface(tester).color, Colors.transparent, reason: 'press');
    await mouse.up();
    await mouse.moveTo(Offset.zero);
    focus.requestFocus();
    await tester.pump();
    expect(buttonSurface(tester).color, Colors.transparent, reason: 'focus');
  });

  testWidgets('the loading spinner keeps the reference 16px in every size', (
    tester,
  ) async {
    for (final size in DButtonSize.values) {
      for (final iconOnly in [false, true]) {
        await _pumpButton(
          tester,
          iconOnly
              ? DButton.iconOnly(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add',
                  size: size,
                  loading: true,
                  onPressed: _noop,
                )
              : DButton(
                  label: const Text('Save'),
                  loadingLabel: const Text('Saving'),
                  size: size,
                  loading: true,
                  onPressed: _noop,
                ),
        );
        expect(
          tester.getSize(find.byType(DSpinner)),
          const Size.square(16),
          reason: '${size.name} ${iconOnly ? 'icon' : 'text'}',
        );
      }
    }
  });

  testWidgets('shortcut tooltips render platform keycaps', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
        home: const Scaffold(
          body: Center(
            child: DButton(
              label: Text('Reply'),
              tooltip: 'Reply to this topic',
              tooltipSide: DTooltipSide.right,
              shortcut: DShortcut(
                SingleActivator(LogicalKeyboardKey.keyR, shift: true),
              ),
              onPressed: _noop,
            ),
          ),
        ),
      ),
    );

    final tooltip = find.byType(DTooltip);
    expect(
      tester.widget<DTooltip>(tooltip).semanticsTooltip,
      'Reply to this topic',
    );

    tester.state<DTooltipState>(tooltip).ensureTooltipVisible();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final message = find.text('Reply to this topic');
    expect(
      tester.getRect(message).left,
      greaterThan(tester.getRect(find.byType(DButton)).right),
    );
    expect(DefaultTextStyle.of(tester.element(message)).style.fontSize, 12);
    expect(find.byType(DKbd), findsNWidgets(2));
    expect(find.text('⇧'), findsOneWidget);
    expect(find.text('R'), findsOneWidget);

    DKbd keycap(int index) =>
        tester.widget<DKbd>(find.byKey(ValueKey('shortcut-key-0-$index')));

    expect(keycap(0).highlighted, isFalse);
    expect(keycap(1).highlighted, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(keycap(0).highlighted, isTrue);
    expect(keycap(1).highlighted, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(keycap(0).highlighted, isTrue);
    expect(keycap(1).highlighted, isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(keycap(0).highlighted, isFalse);
    expect(keycap(1).highlighted, isFalse);
  });

  testWidgets('shortcut sequences retain completed key highlights', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Center(
            child: DTooltip(
              message: 'Open projects',
              shortcut: DShortcut.sequence(
                SingleActivator(LogicalKeyboardKey.keyP),
                [SingleActivator(LogicalKeyboardKey.keyK)],
              ),
              child: Text('Projects'),
            ),
          ),
        ),
      ),
    );

    final tooltip = find.byType(DTooltip);
    tester.state<DTooltipState>(tooltip).ensureTooltipVisible();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    DKbd keycap(int step) =>
        tester.widget<DKbd>(find.byKey(ValueKey('shortcut-key-$step-0')));

    expect(find.byType(DKbd), findsNWidgets(2));
    expect(keycap(0).highlighted, isFalse);
    expect(keycap(1).highlighted, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(keycap(0).highlighted, isTrue);
    expect(keycap(1).highlighted, isFalse);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(keycap(0).highlighted, isTrue);
    expect(keycap(1).highlighted, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(keycap(0).highlighted, isTrue);
    expect(keycap(1).highlighted, isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(keycap(0).highlighted, isFalse);
    expect(keycap(1).highlighted, isFalse);
  });

  for (final (description, label, name) in [
    ('text', const Text('Save changes'), 'Save changes'),
    (
      'rich text',
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text.rich(
          TextSpan(
            text: 'Save ',
            children: [
              TextSpan(text: 'changes', semanticsLabel: 'preferences'),
            ],
          ),
        ),
      ),
      'Save preferences',
    ),
    (
      'custom widget',
      Semantics(
        label: 'Save preferences',
        excludeSemantics: true,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text('Save'), Text(' changes')],
        ),
      ),
      'Save preferences',
    ),
  ]) {
    testWidgets('$description button keeps its name while loading', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        var presses = 0;
        var expectedPresses = 0;
        for (final loading in [false, true, false]) {
          await _pumpButton(
            tester,
            DButton(label: label, onPressed: () => presses++, loading: loading),
          );

          _expectButtonSemantics(tester, label: name, loading: loading);
          await tester.tap(find.byType(DButton));
          if (!loading) expectedPresses++;
          expect(presses, expectedPresses);

          if (loading) {
            final rendered = find.byType(FilledButton);
            expect(tester.getSize(rendered).width, moreOrLessEquals(48));
            expect(tester.getSize(rendered).height, moreOrLessEquals(48));
            expect(rendered, paintsExactlyCountTimes(#drawParagraph, 0));
            expect(find.byType(DSpinner), findsOneWidget);
          }
        }
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('loading text does not replace or duplicate the button name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final loadingText in ['Saving changes…', 'Save changes']) {
        for (final loading in [false, true, false]) {
          await _pumpButton(
            tester,
            DButton(
              label: const Text('Save changes'),
              icon: const Icon(Icons.save, semanticLabel: 'Decorative icon'),
              loadingLabel: Text(loadingText),
              onPressed: _noop,
              loading: loading,
            ),
          );

          _expectButtonSemantics(
            tester,
            label: 'Save changes',
            loading: loading,
          );
          if (loading) {
            expect(
              find.byType(FilledButton),
              paintsExactlyCountTimes(#drawParagraph, 1),
            );
            expect(find.byType(DSpinner), findsOneWidget);
          }
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('retained names do not affect loading geometry or baselines', (
    tester,
  ) async {
    for (final loadingLabel in [null, const Text('Saving changes…')]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  for (final semanticLabel in [null, 'Save preferences'])
                    IntrinsicWidth(
                      child: DButton(
                        label: const Text('Save changes to all preferences'),
                        semanticLabel: semanticLabel,
                        loadingLabel: loadingLabel,
                        loading: true,
                        onPressed: _noop,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      final buttons = find.byType(FilledButton);
      final retainedNameRect = tester.getRect(buttons.at(0));
      final explicitNameRect = tester.getRect(buttons.at(1));
      expect(retainedNameRect.size, explicitNameRect.size);
      expect(retainedNameRect.top, explicitNameRect.top);
    }
  });

  testWidgets('explicit button names override labels and tooltips while busy', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final loadingLabel in [null, const Text('Saving changes…')]) {
        for (final loading in [false, true, false]) {
          await _pumpButton(
            tester,
            DButton(
              label: const Text.rich(TextSpan(text: 'Save changes')),
              icon: const Icon(Icons.save, semanticLabel: 'Decorative icon'),
              tooltip: 'Save these settings',
              semanticLabel: 'Save preferences',
              loadingLabel: loadingLabel,
              onPressed: _noop,
              loading: loading,
            ),
          );

          _expectButtonSemantics(
            tester,
            label: 'Save preferences',
            loading: loading,
          );
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('icon buttons retain their tooltip or explicit name while busy', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final semanticLabel in [null, 'Add an item']) {
        for (final loading in [false, true, false]) {
          await _pumpButton(
            tester,
            DButton.iconOnly(
              icon: const Icon(Icons.add, semanticLabel: 'Decorative icon'),
              tooltip: 'Add',
              semanticLabel: semanticLabel,
              onPressed: _noop,
              loading: loading,
            ),
          );

          _expectButtonSemantics(
            tester,
            label: semanticLabel ?? 'Add',
            tooltip: '',
            loading: loading,
          );
          expect(
            tester.getSize(find.byType(FilledButton)),
            const Size.square(48),
          );
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('loading labels keep progress visible on text buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(
            child: DButton(
              label: Text('Save changes'),
              loadingLabel: Text('Saving changes…'),
              semanticLabel: 'Saving preferences',
              onPressed: _noop,
              loading: true,
              variant: DButtonVariant.primary,
            ),
          ),
        ),
      ),
    );

    final rendered = find.byType(FilledButton);
    final semantics = tester.ensureSemantics();
    try {
      expect(find.text('Save changes'), findsNothing);
      expect(find.text('Saving changes…'), findsOneWidget);
      expect(find.byType(DSpinner), findsOneWidget);
      expect(
        tester.getSize(rendered).width,
        greaterThan(tester.getSize(rendered).height),
      );
      expect(tester.widget<FilledButton>(rendered).onPressed, isNull);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Saving preferences')),
        isSemantics(
          label: 'Saving preferences',
          value: 'Loading',
          isButton: true,
          isEnabled: false,
          isLiveRegion: true,
        ),
      );
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> _pumpButton(WidgetTester tester, DButton button) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Center(child: button)),
      ),
    );

void _expectButtonSemantics(
  WidgetTester tester, {
  required String label,
  required bool loading,
  String tooltip = '',
}) {
  expect(
    tester.getSemantics(find.byType(DButton)),
    isSemantics(
      label: label,
      tooltip: tooltip,
      value: loading ? 'Loading' : '',
      isButton: true,
      hasEnabledState: true,
      isEnabled: !loading,
      hasTapAction: !loading,
      isLiveRegion: loading,
    ),
  );
}

void _noop() {}
