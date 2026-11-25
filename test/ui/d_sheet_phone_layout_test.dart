import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _sample = ValueKey('menu-size-sample');
const _field = ValueKey('menu-field');

void main() {
  for (final (platform, card, full, fieldHeight) in [
    (TargetPlatform.iOS, false, false, 46.0),
    (TargetPlatform.android, false, false, 46.0),
    (TargetPlatform.macOS, false, false, 35.5),
    (TargetPlatform.iOS, true, false, 35.5),
    (TargetPlatform.iOS, false, true, 35.5),
  ]) {
    testWidgets(
      '$platform card=$card full=$full lays out phone fields and accepts taps',
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
        expect(tester.getRect(find.byKey(_sample)).height, 20);
        expect(tester.getRect(find.byKey(_field)).height, fieldHeight);
        await tester.tap(find.text('Choose item'));
        expect(pressed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'choice text uses 17 points with the app and accessibility text scales',
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
                children: [
                  DDropdownMenuContent(
                    children: [DDropdownMenuItem(child: Text('Menu label'))],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final text = find.text('Menu label');
      final paragraph = tester.renderObject<RenderParagraph>(text);
      expect(
        paragraph.textScaler.scale(paragraph.text.style!.fontSize!),
        closeTo(30.6, .001),
      );
      expect(paragraph.getTransformTo(null).getMaxScaleOnAxis(), 1);
      expect(tester.takeException(), isNull);
    },
  );
}
