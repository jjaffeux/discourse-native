import 'dart:ui' show ImageByteFormat, SemanticsValidationResult;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/button_surface.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    ThemeData? theme,
    TextDirection direction = TextDirection.ltr,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light.copyWith(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: Directionality(
          textDirection: direction,
          child: Center(child: child),
        ),
      ),
    ),
  );

  Future<TestGesture> hover(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(target));
    await tester.pump();
    return mouse;
  }

  DTokens tokensOf(WidgetTester tester) =>
      DTokens.of(tester.element(find.byType(FilledButton)));

  for (final iconOnly in [false, true]) {
    testWidgets(
      'custom ${iconOnly ? 'icon' : 'text'} colors preserve alpha through hover and expanded states',
      (tester) async {
        const fill = Color(0x1aed1681);
        const border = Color(0x40ed1681);
        const interactiveFill = Color(0x2ded1681);
        Widget button({Color? interactive, bool expanded = false}) => iconOnly
            ? DButton.iconOnly(
                icon: const Icon(Icons.open_in_new),
                tooltip: 'Browse sales',
                variant: DButtonVariant.outline,
                backgroundColor: fill,
                borderColor: border,
                interactiveBackgroundColor: interactive,
                hasPopup: true,
                expanded: expanded,
                onPressed: () {},
              )
            : DButton(
                label: const Text('sales'),
                variant: DButtonVariant.outline,
                backgroundColor: fill,
                borderColor: border,
                interactiveBackgroundColor: interactive,
                hasPopup: true,
                expanded: expanded,
                onPressed: () {},
              );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);

        for (final theme in [AppTheme.light, AppTheme.dark]) {
          final desktop = theme.copyWith(platform: TargetPlatform.macOS);
          await pump(tester, button(), theme: desktop);
          expect(buttonSurface(tester).color, fill);
          expect(buttonSurface(tester).borderColor, border);

          await mouse.moveTo(tester.getCenter(find.byType(FilledButton)));
          await tester.pump();
          expect(buttonSurface(tester).color, fill, reason: 'default hover');

          await pump(
            tester,
            button(interactive: interactiveFill),
            theme: desktop,
          );
          expect(buttonSurface(tester).color, interactiveFill);
          expect(buttonSurface(tester).borderColor, border);
          await mouse.down(tester.getCenter(find.byType(FilledButton)));
          await tester.pump();
          expect(buttonSurface(tester).color, interactiveFill);
          await mouse.up();
          await mouse.moveTo(Offset.zero);
          await pump(
            tester,
            button(interactive: interactiveFill, expanded: true),
            theme: desktop,
          );
          expect(buttonSurface(tester).color, fill, reason: 'expanded fill');
          expect(buttonSurface(tester).borderColor, border);
        }
      },
    );
  }

  testWidgets(
    'custom borders retain focus rings and yield to invalid styling',
    (tester) async {
      final highlightStrategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy = highlightStrategy,
      );
      final focus = FocusNode();
      addTearDown(focus.dispose);
      const fill = Color(0x1aed1681);
      const border = Color(0x40ed1681);
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        for (final invalid in [false, true]) {
          await pump(
            tester,
            DButton(
              label: const Text('sales'),
              focusNode: focus,
              variant: DButtonVariant.outline,
              backgroundColor: fill,
              borderColor: border,
              invalid: invalid,
              onPressed: () {},
            ),
            theme: theme.copyWith(platform: TargetPlatform.macOS),
          );
          focus.requestFocus();
          await tester.pumpAndSettle();
          final tokens = tokensOf(tester);
          final surface = buttonSurface(tester);
          expect(surface.color, fill);
          expect(surface.ringWidth, 3);
          expect(
            surface.borderColor,
            invalid
                ? tokens.destructive.withValues(
                    alpha: theme.brightness == Brightness.dark ? .5 : 1,
                  )
                : border,
          );
          expect(
            surface.ringColor,
            invalid
                ? tokens.destructive.withValues(
                    alpha: theme.brightness == Brightness.dark ? .4 : .2,
                  )
                : tokens.focusRing.withValues(alpha: tokens.focusRing.a * .5),
          );
        }
      }
    },
  );

  testWidgets(
    'custom colors update live and removing them restores the variant',
    (tester) async {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        for (final color in <Color?>[
          const Color(0xffed1681),
          const Color(0xff0088cc),
          Colors.transparent,
          null,
        ]) {
          await pump(
            tester,
            DButton(
              label: const Text('Category'),
              variant: DButtonVariant.outline,
              backgroundColor: color?.withValues(alpha: color.a * .1),
              borderColor: color?.withValues(alpha: color.a * .25),
              onPressed: () {},
            ),
            theme: theme.copyWith(platform: TargetPlatform.macOS),
          );
          await tester.pumpAndSettle();
          final tokens = tokensOf(tester);
          final dark = theme.brightness == Brightness.dark;
          expect(
            buttonSurface(tester).color,
            color?.withValues(alpha: color.a * .1) ??
                (dark
                    ? tokens.colors.outlineVariant.withValues(
                        alpha: tokens.colors.outlineVariant.a * .3,
                      )
                    : tokens.background),
          );
          expect(
            buttonSurface(tester).borderColor,
            color?.withValues(alpha: color.a * .25) ??
                (dark ? tokens.colors.outlineVariant : tokens.border),
          );
        }
      }
    },
  );

  testWidgets(
    'custom disabled and loading buttons keep their fill and block activation',
    (tester) async {
      var presses = 0;
      const fill = Color(0x1aed1681);
      const border = Color(0x40ed1681);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      for (final loading in [false, true]) {
        await pump(
          tester,
          DButton(
            label: const Text('sales'),
            backgroundColor: fill,
            borderColor: border,
            interactiveBackgroundColor: Colors.green,
            variant: DButtonVariant.outline,
            loading: loading,
            onPressed: loading ? () => presses++ : null,
          ),
        );
        await mouse.moveTo(tester.getCenter(find.byType(FilledButton)));
        await tester.pump();
        await tester.tap(find.byType(DButton));
        expect(buttonSurface(tester).color, fill);
        expect(buttonSurface(tester).borderColor, border);
        expect(presses, 0);
        final opacity = find.ancestor(
          of: find.byType(FilledButton),
          matching: find.byType(Opacity),
        );
        expect(tester.widget<Opacity>(opacity).opacity, .5);
      }
    },
  );

  testWidgets(
    'disabled opacity follows the scoped theme without enabling activation',
    (tester) async {
      final base = AppTheme.light;
      expect(base.discourseButtons.disabledOpacity, .5);
      var presses = 0;
      for (final opacity in [.5, 1.0, .25]) {
        final theme = base.copyWith(
          extensions: [
            ...base.extensions.values.where(
              (value) => value is! DiscourseButtonTheme,
            ),
            base.discourseButtons.copyWith(disabledOpacity: opacity),
          ],
        );
        for (final loading in [false, true]) {
          await pump(
            tester,
            DButton(
              label: const Text('Choose file'),
              loading: loading,
              onPressed: loading ? () => presses++ : null,
            ),
            theme: theme,
          );
          await tester.pump(const Duration(milliseconds: 300));
          final surfaceOpacity = find.ancestor(
            of: find.byType(FilledButton),
            matching: find.byType(Opacity),
          );
          expect(tester.widget<Opacity>(surfaceOpacity).opacity, opacity);
          expect(
            tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNull,
          );
          await tester.tap(find.byType(DButton));
          expect(presses, 0);
        }
      }
    },
  );

  testWidgets('small radii scale proportionally with size-specific caps', (
    tester,
  ) async {
    for (final (baseRadius, xsRadius, smRadius) in [
      (0.0, 0.0, 0.0),
      (4.0, 3.2, 3.2),
      (10.0, 8.0, 8.0),
      (14.0, 10.0, 11.2),
      (20.0, 10.0, 12.0),
    ]) {
      final base = AppTheme.light;
      final tokens = base.extension<DTokens>()!.copyWith(radius: baseRadius);
      final theme = base.copyWith(
        extensions: [
          ...base.extensions.values.where((value) => value is! DTokens),
          tokens,
        ],
      );
      for (final size in DButtonSize.values) {
        for (final iconOnly in [false, true]) {
          await pump(
            tester,
            iconOnly
                ? DButton.iconOnly(
                    icon: const Icon(Icons.add),
                    tooltip: 'Add',
                    size: size,
                    onPressed: () {},
                  )
                : DButton(
                    label: const Text('Button'),
                    size: size,
                    onPressed: () {},
                  ),
            theme: theme,
          );
          await tester.pumpAndSettle();
          final shape =
              tester
                      .widget<FilledButton>(find.byType(FilledButton))
                      .style!
                      .shape!
                      .resolve({})!
                  as RoundedRectangleBorder;
          final expected = switch (size) {
            DButtonSize.extraSmall => xsRadius,
            DButtonSize.small => smRadius,
            _ => baseRadius,
          };
          final radius = shape.borderRadius.resolve(TextDirection.ltr);
          expect(radius.topLeft.x, closeTo(expected, .000001));
          expect(radius, BorderRadius.circular(radius.topLeft.x));
          expect(buttonSurface(tester).borderRadius, radius);
        }
      }
    }
  });

  testWidgets(
    'small leading and loading icon padding match rendered reference',
    (tester) async {
      await pump(
        tester,
        DButton(
          label: const Text('Small'),
          size: DButtonSize.small,
          onPressed: () {},
        ),
      );
      final smallStyle = tester
          .widget<FilledButton>(find.byType(FilledButton))
          .style!;
      expect(smallStyle.textStyle!.resolve({})!.height, 22.4 / 12.8);
      expect(tester.getSize(find.byType(FilledButton)).height, 28);
      for (final position in DButtonIconPosition.values) {
        await pump(
          tester,
          DButton(
            label: const Text('Generate'),
            loading: true,
            loadingLabel: const Text('Generating'),
            iconPosition: position,
            onPressed: () {},
          ),
        );
        final padding =
            tester
                    .widget<FilledButton>(find.byType(FilledButton))
                    .style!
                    .padding!
                    .resolve({})!
                as EdgeInsetsDirectional;
        expect(padding.start, position == DButtonIconPosition.start ? 9 : 11);
        expect(padding.end, position == DButtonIconPosition.end ? 9 : 11);
      }
    },
  );

  testWidgets('dark outline preserves input token alpha through its overlays', (
    tester,
  ) async {
    final base = AppTheme.dark;
    const input = Color(0x26ffffff);
    final tokens = base.extension<DTokens>()!.copyWith(
      colors: base.colorScheme.copyWith(outlineVariant: input),
    );
    await pump(
      tester,
      DButton(
        label: const Text('Outline'),
        variant: DButtonVariant.outline,
        onPressed: () {},
      ),
      theme: base.copyWith(
        extensions: [
          ...base.extensions.values.where((x) => x is! DTokens),
          tokens,
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(buttonSurface(tester).color.a, closeTo(input.a * .3, .0001));
    expect(buttonSurface(tester).borderColor, input);
    await hover(tester, find.byType(FilledButton));
    expect(buttonSurface(tester).color.a, closeTo(input.a * .5, .0001));
  });

  testWidgets(
    'the ring paints outside and transparent-border fills reach the bounds',
    (tester) async {
      final highlightStrategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy = highlightStrategy,
      );
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final boundary = GlobalKey();
      await pump(
        tester,
        RepaintBoundary(
          key: boundary,
          child: ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: 120,
                child: DButton(
                  focusNode: focus,
                  label: const Text('Save'),
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final bounds = tester
          .getRect(find.byType(FilledButton))
          .shift(-tester.getTopLeft(find.byKey(boundary)));
      expect(bounds, const Rect.fromLTWH(8, 8, 120, 32));
      Future<Color> pixel(double x, double y) async {
        final color = await tester.runAsync(() async {
          final box =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await box.toImage();
          final bytes = (await image.toByteData(
            format: ImageByteFormat.rawRgba,
          ))!;
          final index = (y.floor() * image.width + x.floor()) * 4;
          image.dispose();
          return Color.fromARGB(
            bytes.getUint8(index + 3),
            bytes.getUint8(index),
            bytes.getUint8(index + 1),
            bytes.getUint8(index + 2),
          );
        });
        return color!;
      }

      final middle = bounds.center.dy;
      final primary = tokensOf(tester).primary;
      // Filled and outlined controls share the same visible outer bounds.
      expect(await pixel(bounds.right - 1, middle), primary);
      expect(await pixel(bounds.right - 2, middle), primary);
      expect(await pixel(bounds.center.dx, bounds.top), primary);
      expect(await pixel(bounds.center.dx, bounds.top + 1), primary);
      expect(await pixel(bounds.right + 1, middle), Colors.white);

      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(buttonSurface(tester).ringWidth, 3);
      expect(await pixel(bounds.right + 1, middle), isNot(Colors.white));
      expect(await pixel(bounds.right + 3, middle), Colors.white);
    },
  );

  testWidgets(
    'expanded triggers keep the reference surface per variant and brightness',
    (tester) async {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final dark = theme.brightness == Brightness.dark;
        for (final variant in [
          DButtonVariant.outline,
          DButtonVariant.secondary,
          DButtonVariant.ghost,
          DButtonVariant.primary,
        ]) {
          await pump(
            tester,
            DButton(
              label: const Text('Options'),
              variant: variant,
              hasPopup: true,
              expanded: true,
              onPressed: () {},
            ),
            theme: theme,
          );
          await tester.pumpAndSettle();
          final tokens = tokensOf(tester);
          final input = tokens.colors.outlineVariant;
          // A dark outline trigger keeps its resting input fill because
          // dark:bg-input/30 outranks aria-expanded:bg-muted.
          final expected = switch (variant) {
            DButtonVariant.outline when dark => input.withValues(
              alpha: input.a * .3,
            ),
            DButtonVariant.outline ||
            DButtonVariant.secondary ||
            DButtonVariant.ghost => tokens.muted,
            _ => tokens.primary,
          };
          expect(
            buttonSurface(tester).color,
            expected,
            reason: '${theme.brightness.name} ${variant.name}',
          );
        }
      }
      // aria-expanded:bg-secondary outranks the secondary hover mix.
      await pump(
        tester,
        DButton(
          label: const Text('Options'),
          variant: DButtonVariant.secondary,
          hasPopup: true,
          expanded: true,
          onPressed: () {},
        ),
      );
      await hover(tester, find.byType(FilledButton));
      expect(buttonSurface(tester).color, tokensOf(tester).muted);
    },
  );

  testWidgets('a focused dark outline keeps its input border under the ring', (
    tester,
  ) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final dark = theme.brightness == Brightness.dark;
      final focus = FocusNode();
      await pump(
        tester,
        DButton(
          focusNode: focus,
          label: const Text('Outline'),
          variant: DButtonVariant.outline,
          onPressed: () {},
        ),
        theme: theme,
      );
      focus.requestFocus();
      await tester.pumpAndSettle();
      final tokens = tokensOf(tester);
      final surface = buttonSurface(tester);
      expect(surface.ringWidth, 3, reason: theme.brightness.name);
      expect(
        surface.ringColor,
        tokens.focusRing.withValues(alpha: tokens.focusRing.a * .5),
      );
      expect(
        surface.borderColor,
        dark ? tokens.colors.outlineVariant : tokens.focusRing,
        reason: theme.brightness.name,
      );
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
    }
  });

  testWidgets(
    'a touch press keeps the reference fill including legacy aliases',
    (tester) async {
      for (final (variant, pressedFill) in [
        (DButtonVariant.primary, false),
        (DButtonVariant.standard, false),
      ]) {
        await pump(
          tester,
          DButton(
            label: const Text('Press'),
            variant: variant,
            onPressed: () {},
          ),
        );
        final rest = buttonSurface(tester).color;
        final origin = tester.getTopLeft(find.text('Press'));
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Press')),
        );
        await tester.pumpAndSettle();
        final theme = Theme.of(tester.element(find.byType(FilledButton)));
        expect(
          buttonSurface(tester).color,
          pressedFill ? theme.shell.hover : rest,
          reason: variant.name,
        );
        expect(tester.getTopLeft(find.text('Press')).dy, origin.dy + 1);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(buttonSurface(tester).color, rest);
        expect(tester.getTopLeft(find.text('Press')).dy, origin.dy);
      }
    },
  );

  testWidgets('surface changes transition over 150ms unless motion is off', (
    tester,
  ) async {
    AnimatedContainer container() => tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is AnimatedContainer &&
              widget.decoration is DButtonDecoration,
        ),
      ),
    );
    DButtonDecoration painted() =>
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byType(FilledButton),
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is DecoratedBox &&
                          widget.decoration is DButtonDecoration,
                    ),
                  ),
                )
                .decoration
            as DButtonDecoration;

    await pump(tester, DButton(label: const Text('Save'), onPressed: () {}));
    expect(container().duration, const Duration(milliseconds: 150));
    expect(container().curve, Curves.ease);
    final primary = tokensOf(tester).primary;
    await hover(tester, find.byType(FilledButton));
    await tester.pump(const Duration(milliseconds: 75));
    final midway = painted().color.a;
    expect(midway, greaterThan(primary.a * .8));
    expect(midway, lessThan(primary.a));
    await tester.pumpAndSettle();
    expect(painted().color, primary.withValues(alpha: primary.a * .8));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(
              child: DButton(label: const Text('Save'), onPressed: () {}),
            ),
          ),
        ),
      ),
    );
    expect(container().duration, Duration.zero);
  });

  testWidgets('popup and invalid triggers expose expanded and validity', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      for (final expanded in [false, true]) {
        await pump(
          tester,
          DButton(
            label: const Text('Options'),
            hasPopup: true,
            expanded: expanded,
            onPressed: () {},
          ),
        );
        expect(
          tester.getSemantics(find.byType(DButton)),
          isSemantics(
            label: 'Options',
            isButton: true,
            hasExpandedState: true,
            isExpanded: expanded,
            validationResult: SemanticsValidationResult.none,
          ),
        );
      }
      await pump(
        tester,
        DButton(
          label: const Text('Selected'),
          expanded: true,
          onPressed: () {},
        ),
      );
      expect(
        tester.getSemantics(find.byType(DButton)),
        isSemantics(label: 'Selected', hasExpandedState: false),
      );
      await pump(
        tester,
        DButton(
          label: const Text('Required choice'),
          invalid: true,
          variant: DButtonVariant.outline,
          onPressed: () {},
        ),
      );
      expect(
        tester.getSemantics(find.byType(DButton)),
        isSemantics(
          label: 'Required choice',
          validationResult: SemanticsValidationResult.invalid,
        ),
      );
      final tokens = tokensOf(tester);
      final surface = buttonSurface(tester);
      expect(surface.ringWidth, 3);
      expect(
        surface.ringColor,
        tokens.destructive.withValues(alpha: tokens.destructive.a * .2),
      );
      expect(surface.borderColor, tokens.destructive);
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
    'small app icons use the shared surface size and native touch targets',
    (tester) async {
      final semantics = tester.ensureSemantics();
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.iOS,
        TargetPlatform.android,
      ]) {
        for (final variant in [
          DButtonVariant.flat,
          DButtonVariant.flatClose,
          DButtonVariant.outline,
        ]) {
          var presses = 0;
          await pump(
            tester,
            DButton.iconOnly(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              semanticLabel: 'Close',
              size: DButtonSize.small,
              variant: variant,
              onPressed: () => presses++,
            ),
            theme: AppTheme.light.copyWith(platform: platform),
          );
          await tester.pumpAndSettle();
          final target = tester.getRect(find.byType(FilledButton));
          final surface = tester.getRect(
            find.descendant(
              of: find.byType(FilledButton),
              matching: find.byType(Material),
            ),
          );
          expect(surface.size, const Size.square(28));
          expect(
            target.size,
            Size.square(platform == TargetPlatform.macOS ? 28 : 48),
          );
          expect(
            tester.getSemantics(find.byType(DButton)).rect.size,
            target.size,
          );
          final edge = target.topLeft + const Offset(2, 2);
          expect(surface.contains(edge), platform == TargetPlatform.macOS);
          await tester.tapAt(edge);
          expect(
            presses,
            1,
            reason: '${platform.name} ${variant.name} inset edge',
          );
        }
      }
      semantics.dispose();
    },
  );

  testWidgets(
    'all icon sizes have reference visual dimensions and iOS touch bounds',
    (tester) async {
      for (final size in DButtonSize.values) {
        for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
          var count = 0;
          await pump(
            tester,
            DButton.iconOnly(
              icon: const Icon(Icons.add),
              tooltip: 'Add',
              size: size,
              onPressed: () => count++,
            ),
            theme: AppTheme.light.copyWith(platform: platform),
          );
          await tester.pumpAndSettle();
          final material = find.descendant(
            of: find.byType(FilledButton),
            matching: find.byType(Material),
          );
          expect(
            tester.getSize(material),
            Size.square(DButton.visualDimensionFor(size)),
          );
          final target = tester.getRect(find.byType(FilledButton));
          expect(
            target.height,
            platform == TargetPlatform.iOS
                ? 48
                : DButton.visualDimensionFor(size),
          );
          await tester.tapAt(target.topLeft + const Offset(2, 2));
          expect(count, 1);
        }
      }
    },
  );

  testWidgets(
    'navigation exposes only a link role with its rich accessible name',
    (tester) async {
      final handle = tester.ensureSemantics();
      var count = 0;
      await pump(
        tester,
        DButton(
          isLink: true,
          label: const Text.rich(TextSpan(text: 'Login')),
          onPressed: () => count++,
        ),
      );
      final node = tester.getSemantics(find.byType(DButton));
      expect(
        node,
        isSemantics(
          label: 'Login',
          isLink: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.text('Login'));
      expect(count, 1);
      handle.dispose();
    },
  );

  testWidgets(
    'keyboard activation and disabled changes retain borrowed focus ownership',
    (tester) async {
      final focus = FocusNode();
      var count = 0;
      for (final disabled in [false, true, false]) {
        await pump(
          tester,
          DButton(
            label: const Text('Save'),
            focusNode: focus,
            onPressed: disabled ? null : () => count++,
          ),
        );
        focus.requestFocus();
        await tester.pump();
        final before = count;
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(count, before + (disabled ? 0 : 2));
      }
      await tester.pumpWidget(const SizedBox());
      expect(() => focus.addListener(() {}), returnsNormally);
      focus.dispose();
    },
  );

  testWidgets(
    'directional icon position mirrors and palette changes restyle surfaces',
    (tester) async {
      for (final direction in TextDirection.values) {
        for (final position in DButtonIconPosition.values) {
          await pump(
            tester,
            DButton(
              label: const Text('Send'),
              icon: const Icon(Icons.add),
              iconPosition: position,
              variant: DButtonVariant.destructive,
              onPressed: () {},
            ),
            direction: direction,
          );
          final iconX = tester.getCenter(find.byIcon(Icons.add)).dx;
          final textX = tester.getCenter(find.text('Send')).dx;
          expect(
            iconX < textX,
            (direction == TextDirection.ltr) ==
                (position == DButtonIconPosition.start),
          );
        }
      }
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        await pump(
          tester,
          DButton(
            label: const Text('Delete'),
            variant: DButtonVariant.destructive,
            onPressed: () {},
          ),
          theme: theme,
        );
        await tester.pumpAndSettle();
        expect(
          buttonSurface(tester).color,
          theme.colorScheme.error.withValues(
            alpha: theme.brightness == Brightness.dark ? .2 : .1,
          ),
        );
      }
    },
  );

  testWidgets('link hover underlines and popup press retains its origin', (
    tester,
  ) async {
    await pump(
      tester,
      DButton(
        label: const Text('Link'),
        variant: DButtonVariant.link,
        onPressed: () {},
      ),
    );
    await hover(tester, find.text('Link'));
    await tester.pumpAndSettle();
    final style = tester.widget<FilledButton>(find.byType(FilledButton)).style!;
    expect(
      style.textStyle!.resolve({WidgetState.hovered})!.decoration,
      TextDecoration.underline,
    );
    for (final popup in [false, true]) {
      await pump(
        tester,
        DButton(label: const Text('Press'), hasPopup: popup, onPressed: () {}),
      );
      final origin = tester.getTopLeft(find.text('Press'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Press')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Press')).dy,
        origin.dy + (popup ? 0 : 1),
      );
      await gesture.up();
      await tester.pumpAndSettle();
    }
  });
}
