import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compact grid clamps edges and keeps its colour ring visible', (
    tester,
  ) async {
    var color = Colors.white;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              child: StatefulBuilder(
                builder: (context, setState) => DColorPicker.inline(
                  value: color,
                  size: DColorPickerSize.compact,
                  semanticLabel: 'Compact colour',
                  onChanged: (next) => setState(() => color = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final grid = find.byType(DColorPicker);
    expect(tester.getSize(grid).height, 58);
    await tester.tapAt(tester.getTopLeft(grid) + const Offset(1, 1));
    await tester.pump();
    final hsl = HSLColor.fromColor(color);
    expect(hsl.hue, closeTo(7.2, 1));
    expect(hsl.lightness, closeTo(.98, .003));
    await tester.tapAt(tester.getBottomRight(grid) - const Offset(1, 1));
    await tester.pump();
    expect(HSLColor.fromColor(color).lightness, closeTo(.02, .003));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'presets support recent colors, keyboard activation, reset and disabled state',
    (tester) async {
      const red = DColorPreset(color: Colors.red, label: 'Red text');
      const green = DColorPreset(
        color: Colors.green,
        label: 'Green background',
        appearance: DColorPresetAppearance.background,
      );
      DColorPreset? selected;
      final recent = <DColorPreset>[];
      var enabled = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: DCard(
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return DColorPickerPresets(
                  semanticLabel: 'Text color',
                  presets: const [red, green],
                  selected: selected,
                  recentColors: recent,
                  onReset: () => setState(() => selected = null),
                  onChanged: enabled
                      ? (color) => setState(() {
                          selected = color;
                          recent.remove(color);
                          recent.insert(0, color);
                        })
                      : null,
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Red text'));
      await tester.pumpAndSettle();
      expect(selected, red);
      expect(find.text('Recently used'), findsOneWidget);
      expect(find.byTooltip('Red text'), findsNWidgets(2));
      final greenButton = find.descendant(
        of: find.byType(DColorPickerPresets),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DButton && widget.semanticLabel == 'Green background',
        ),
      );
      Focus.of(
        tester.element(
          find
              .descendant(of: greenButton, matching: find.byType(SizedBox))
              .last,
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, green);
      expect(recent, [green, red]);
      expect(find.byIcon(Icons.check), findsNWidgets(2));
      await tester.tap(find.byTooltip('Text color: Default'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      update(() => enabled = false);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Red text').last);
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(tester.takeException(), isNull);
    },
  );

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
