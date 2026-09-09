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
