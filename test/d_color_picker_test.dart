import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'plane and keyboard update color; Escape closes only the picker',
    (tester) async {
      var color = const Color(0xff39845b);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DCard(
            child: StatefulBuilder(
              builder: (context, setState) => Center(
                child: DColorPicker(
                  value: color,
                  semanticLabel: 'Choose accent',
                  onChanged: (value) => setState(() => color = value),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Choose accent'));
      await tester.pumpAndSettle();
      final plane = find.byKey(const ValueKey('color-picker-plane'));
      await tester.tapAt(tester.getTopLeft(plane) + const Offset(80, 40));
      await tester.pumpAndSettle();
      expect(color, isNot(const Color(0xff39845b)));
      final hue = find.bySemanticsLabel('Choose accent Hue');
      await tester.tap(hue);
      await tester.pumpAndSettle();
      final before = color;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(color, isNot(before));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(plane, findsNothing);
      expect(find.byType(DColorPicker), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('near-red hues open and rejected changes reset', (tester) async {
    const accepted = Color(0xffff0001);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DCard(
          child: DColorPicker(
            value: accepted,
            semanticLabel: 'Choose red',
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Choose red'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final plane = find.byKey(const ValueKey('color-picker-plane'));
    await tester.tapAt(tester.getCenter(plane));
    await tester.pumpAndSettle();
    final sliders = tester.widgetList<DSlider>(find.byType(DSlider)).toList();
    expect(sliders[0].value, closeTo(HSVColor.fromColor(accepted).hue, .001));
    expect(sliders[1].value, 100);
    expect(sliders[2].value, 100);
  });

  testWidgets('disabled picker does not open', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const DCard(
          child: DColorPicker(
            value: Colors.white,
            semanticLabel: 'Choose color',
            onChanged: null,
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Choose color'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('color-picker-plane')), findsNothing);
  });
}
