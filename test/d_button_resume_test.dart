import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/button_surface.dart';

const _card = ValueKey('resume');
const _icon = ValueKey('resume-icon');
const _restore = ValueKey('restore-icon');

void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final dark in [false, true]) {
      testWidgets(
        'resume card scales and has one exact target $platform $dark',
        (tester) async {
          var presses = 0;
          final semantics = tester.ensureSemantics();
          try {
            for (final scale in [1.0, 2.0]) {
              await _pump(
                tester,
                platform: platform,
                dark: dark,
                scale: scale,
                onPressed: () => presses++,
              );
              final card = find.byKey(_card);
              final bounds = tester.getRect(card);
              expect(bounds.size, Size(320, scale == 1 ? 52 : 85));
              expect(tester.getSize(find.byType(FilledButton)), bounds.size);
              expect(tester.getSemantics(card).rect.size, bounds.size);
              expect(
                buttonSurface(tester).borderRadius,
                BorderRadius.circular(16),
              );
              final title = tester.getRect(
                find.text('A long topic title to resume'),
              );
              final metadata = tester.getRect(find.text('12 words'));
              expect(title.left, bounds.left + 56);
              expect(metadata.top, greaterThanOrEqualTo(title.bottom));
              expect(metadata.bottom, lessThanOrEqualTo(bounds.bottom - 8));
              await tester.tapAt(bounds.centerLeft - const Offset(1, 0));
              expect(presses, scale == 1 ? 0 : 3);
              for (final target in [
                find.byKey(_icon),
                find.text('12 words'),
                find.byKey(_restore),
              ]) {
                await tester.tap(target);
              }
              expect(presses, scale == 1 ? 3 : 6);
              expect(tester.takeException(), isNull);
            }
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  testWidgets('whole-card hover and keyboard focus reveal restore artwork', (
    tester,
  ) async {
    var presses = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await _pump(tester, focusNode: focus, onPressed: () => presses++);
    final artwork = find
        .ancestor(
          of: find.byKey(_restore),
          matching: find.byType(AnimatedContainer),
        )
        .first;
    Color tint() =>
        (tester.widget<AnimatedContainer>(artwork).decoration! as BoxDecoration)
            .color!;
    expect(tint().a, 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('12 words')));
    await tester.pump();
    expect(tint().a, greaterThan(0));
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(tint().a, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    expect(buttonSurface(tester).ringWidth, greaterThan(0));
    expect(tint().a, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled resume card neither reveals restore nor activates', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(tester);
      final artwork = find
          .ancestor(
            of: find.byKey(_restore),
            matching: find.byType(AnimatedContainer),
          )
          .first;
      Color tint() =>
          (tester.widget<AnimatedContainer>(artwork).decoration!
                  as BoxDecoration)
              .color!;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('12 words')));
      await tester.pump();
      expect(tint().a, 0);
      await mouse.down(tester.getCenter(find.byKey(_restore)));
      await tester.pump();
      expect(tint().a, 0);
      await mouse.up();
      expect(
        tester.getSemantics(find.byKey(_card)),
        isSemantics(
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
        ),
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> _pump(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.macOS,
  bool dark = false,
  double scale = 1,
  VoidCallback? onPressed,
  FocusNode? focusNode,
}) => tester.pumpWidget(
  MaterialApp(
    theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(platform: platform),
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(scale),
        disableAnimations: true,
      ),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: DButton(
              key: _card,
              variant: DButtonVariant.resume,
              icon: const Icon(Icons.edit, key: _icon),
              label: const Text('A long topic title to resume'),
              description: const Text('12 words'),
              trailing: const DLayoutGlyph(
                key: _restore,
                mainVisible: true,
                secondaryVisible: false,
                changingPanel: 0,
                dock: DLayoutGlyphDock.right,
              ),
              focusNode: focusNode,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    ),
  ),
);
