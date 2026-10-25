import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {ThemeData? theme, double scale = 1}) => MaterialApp(
  theme: theme ?? AppTheme.light.copyWith(platform: TargetPlatform.macOS),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);

BoxDecoration _previewPaint(WidgetTester tester) =>
    tester
            .widget<AnimatedContainer>(
              find.descendant(
                of: find.byType(DCard),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .decoration!
        as BoxDecoration;

void main() {
  for (final brightness in Brightness.values) {
    {
      testWidgets(
        'nested preview retains hover focus and press in $brightness flat',
        (tester) async {
          final focus = FocusNode();
          addTearDown(focus.dispose);
          final theme =
              (brightness == Brightness.dark ? AppTheme.dark : AppTheme.light)
                  .copyWith(platform: TargetPlatform.macOS);
          var activations = 0;
          await tester.pumpWidget(
            _host(
              SizedBox(
                width: 320,
                child: DItem.preview(
                  focusNode: focus,
                  onPressed: () => activations++,
                  builder: (_, _) =>
                      (header: null, preview: const SizedBox(height: 60)),
                ),
              ),
              theme: theme,
            ),
          );
          final resting = theme.colorScheme.surfaceContainerHighest;
          final emphasized = Color.alphaBlend(
            theme.colorScheme.onSurface.withValues(
              alpha: brightness == Brightness.dark ? .055 : .035,
            ),
            resting,
          );
          expect(_previewPaint(tester).color, resting);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          addTearDown(mouse.removePointer);
          await mouse.addPointer(location: const Offset(600, 500));
          final target = tester.getCenter(find.byType(DItem));
          await mouse.moveTo(target);
          await tester.pumpAndSettle();
          expect(_previewPaint(tester).color, emphasized);
          expect(
            (_previewPaint(tester).border! as Border).top.color,
            theme.colorScheme.onSurface.withValues(alpha: .1),
          );
          await mouse.down(target);
          await tester.pump();
          expect(
            DItemInteraction.of(tester.element(find.byType(DCard))).pressed,
            isTrue,
          );
          expect(_previewPaint(tester).color, emphasized);
          await mouse.cancel();
          await mouse.moveTo(const Offset(600, 500));
          await tester.pumpAndSettle();
          expect(_previewPaint(tester).color, resting);
          expect(activations, 0);
          focus.requestFocus();
          await tester.pumpAndSettle();
          expect(_previewPaint(tester).color, emphasized);
          expect(
            (_previewPaint(tester).border! as Border).top.color,
            theme.colorScheme.primary.withValues(alpha: .7),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(activations, 1);
          focus.unfocus();
          await tester.pumpAndSettle();
          expect(_previewPaint(tester).color, resting);
        },
      );
    }
  }

  testWidgets('nested Native links retain their own action and semantics', (
    tester,
  ) async {
    var rows = 0;
    var profiles = 0;
    final personFocus = FocusNode();
    addTearDown(personFocus.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 320,
            child: DItem.preview(
              semanticLabel: 'Open thread',
              onPressed: () => rows++,
              builder: (_, _) => (
                header: null,
                preview: DButton(
                  label: const Text('Open person'),
                  isLink: true,
                  focusNode: personFocus,
                  onPressed: () => profiles++,
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Open person'))
            .getSemanticsData()
            .flagsCollection
            .isLink,
        isTrue,
      );
      await tester.tap(find.text('Open person'));
      expect(profiles, 1);
      expect(rows, 0);
      personFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(profiles, 2);
      expect(rows, 0);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('artwork receives its bounded grid cell without row insets', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 120,
          height: 80,
          child: DItem(
            size: DItemSize.artwork,
            shape: DItemShape.menu,
            clipBehavior: Clip.antiAlias,
            onPressed: () => activations++,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  expect(constraints.biggest, const Size(120, 80));
                  return const SizedBox.expand(key: ValueKey('artwork'));
                },
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.getRect(find.byType(DItem)),
      tester.getRect(find.byKey(const ValueKey('artwork'))),
    );
    await tester.tapAt(const Offset(125, 40));
    expect(activations, 0);
    await tester.tap(find.byType(DItem));
    expect(activations, 1);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('rail action matches visible bounds and scales on $platform', (
      tester,
    ) async {
      for (final scale in [1.0, 2.0]) {
        var activations = 0;
        await tester.pumpWidget(
          _host(
            Padding(
              padding: const EdgeInsets.all(6),
              child: DButton.iconOnly(
                tooltip: 'Update',
                density: DButtonDensity.rail,
                variant: DButtonVariant.ghost,
                backgroundColor: Colors.red,
                onPressed: () => activations++,
                icon: const DIcon(DIcons.download),
              ),
            ),
            theme: AppTheme.light.copyWith(platform: platform),
            scale: scale,
          ),
        );
        final target = find.byType(DButton);
        final bounds = tester.getRect(target);
        expect(bounds.size, Size.square(32 + (scale - 1) * 14));
        await tester.tapAt(Offset(bounds.left - 3, bounds.center.dy));
        expect(activations, 0);
        await tester.tap(target);
        expect(activations, 1);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
