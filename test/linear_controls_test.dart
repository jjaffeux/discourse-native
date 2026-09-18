import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/linear_controls_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings selectors retain rich content and keyboard ownership', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
        home: const Scaffold(
          body: SingleChildScrollView(child: LinearControlsExample()),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Interface theme'));
    await tester.pumpAndSettle();
    expect(find.byType(DPopoverContent), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(DPopoverContent), findsNothing);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Interface theme')).value,
      'Dark',
    );
    await tester.tap(find.bySemanticsLabel('Branch format').last);
    await tester.pumpAndSettle();
    expect(find.byType(DPopoverContent), findsNothing);
    await tester.tap(find.text('Enable'));
    await tester.pump();
    expect(find.text('Enabled'), findsOneWidget);
  });

  testWidgets('settings reflow at 320px, 200% text and RTL in every palette', (
    tester,
  ) async {
    for (final palette in [
      StyleguideTheme.light,
      StyleguideTheme.dark,
      StyleguideTheme.forest,
      StyleguideTheme.plum,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: palette.resolve(AppTheme.light),
          home: const MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: SizedBox(width: 320, child: LinearControlsExample()),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: palette.name);
      await tester.ensureVisible(find.bySemanticsLabel('Interface theme'));
      await tester.tap(find.bySemanticsLabel('Interface theme'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${palette.name} popup');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
  });
}
