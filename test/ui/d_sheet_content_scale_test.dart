import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _sample = ValueKey('menu-size-sample');
const _field = ValueKey('menu-field');

void main() {
  for (final (platform, card, full, expectedScale) in [
    (TargetPlatform.iOS, false, false, 17 / 13),
    (TargetPlatform.android, false, false, 17 / 13),
    (TargetPlatform.macOS, false, false, 1.0),
    (TargetPlatform.iOS, true, false, 1.0),
    (TargetPlatform.iOS, false, true, 1.0),
  ]) {
    testWidgets(
      '$platform card=$card full=$full scales menu artwork and taps',
      (tester) async {
        var pressed = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (_, child) => DTouchTargets(child: child!),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: 390,
                  child: DSheetContent(
                    side: DSheetSide.bottom,
                    variant: DSheetVariant.menu,
                    card: card,
                    fillAvailableHeight: full,
                    showCloseButton: false,
                    children: [
                      const SizedBox(key: _sample, width: 100, height: 20),
                      DInput(key: _field, size: DControlSize.field),
                      DButton(
                        label: const Text('Choose item'),
                        onPressed: () => pressed = true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(_sample)).height,
          closeTo(20 * expectedScale, .01),
        );
        expect(
          tester.getRect(find.byKey(_field)).height,
          closeTo(35.5 * expectedScale, .01),
        );
        await tester.tap(find.text('Choose item'));
        expect(pressed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'menu text applies app and accessibility scale without reading uplift twice',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(390, 844),
              textScaler: AppTextScaler(
                platformScaler: TextScaler.linear(1.5),
                appScale: 1.2,
                baselineScale: 17 / 14,
              ),
            ),
            child: Scaffold(
              body: DSheetContent(
                side: DSheetSide.bottom,
                variant: DSheetVariant.menu,
                showCloseButton: false,
                children: [Text('Menu label', style: TextStyle(fontSize: 13))],
              ),
            ),
          ),
        ),
      );
      final text = find.text('Menu label');
      final paragraph = tester.renderObject<RenderParagraph>(text);
      expect(
        MediaQuery.textScalerOf(tester.element(text)).scale(13),
        closeTo(23.4, .001),
      );
      expect(
        paragraph.getTransformTo(null).getMaxScaleOnAxis(),
        closeTo(17 / 13, .001),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
