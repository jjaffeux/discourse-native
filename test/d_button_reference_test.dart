import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
    final style = tester.widget<FilledButton>(find.byType(FilledButton)).style!;
    expect(style.backgroundColor!.resolve({})!.a, closeTo(input.a * .3, .0001));
    expect(
      style.backgroundColor!.resolve({WidgetState.hovered})!.a,
      closeTo(input.a * .5, .0001),
    );
    expect(style.side!.resolve({})!.color, input);
  });

  testWidgets(
    'small inset app icons keep touch targets outside their painted surface',
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
              insetSurface: variant == DButtonVariant.outline,
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
          expect(surface.size, const Size.square(32));
          expect(
            target.size,
            Size.square(platform == TargetPlatform.macOS ? 40 : 48),
          );
          expect(
            tester.getSemantics(find.byType(DButton)).rect.size,
            target.size,
          );
          final edge = target.topLeft + const Offset(2, 2);
          expect(surface.contains(edge), isFalse);
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
        final style = tester
            .widget<FilledButton>(find.byType(FilledButton))
            .style!;
        expect(
          style.backgroundColor!.resolve({}),
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
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Link')));
    await tester.pumpAndSettle();
    final style = tester.widget<FilledButton>(find.byType(FilledButton)).style!;
    expect(
      style.textStyle!.resolve({WidgetState.hovered})!.decoration,
      TextDecoration.underline,
    );
    await mouse.removePointer();
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
