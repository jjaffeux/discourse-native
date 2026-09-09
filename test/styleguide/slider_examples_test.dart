import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/slider_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'all actual slider examples tolerate narrow RTL large-text previews in light and dark',
    (tester) async {
      for (final dark in [false, true]) {
        for (final example in sliderExamples.examples) {
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey('${example.title}-$dark'),
              theme: dark ? ThemeData.dark() : ThemeData.light(),
              home: MediaQuery(
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: Center(
                        child: SizedBox(
                          width: 220,
                          child: Builder(builder: example.builder),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(
            find.byType(DMultiSlider),
            findsWidgets,
            reason: example.title,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '${example.title} dark=$dark',
          );
        }
      }
    },
  );

  testWidgets('controlled temperature updates its visible label by keyboard', (
    tester,
  ) async {
    final example = sliderExamples.examples.firstWhere(
      (e) => e.title == 'Controlled',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: example.builder)),
      ),
    );
    final slider = find.byType(DMultiSlider);
    final rect = tester.getRect(slider);
    await tester.tapAt(
      Offset(rect.left + 6 + (rect.width - 12) * 0.3, rect.center.dy),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('0.4, 0.7'), findsOneWidget);
  });
}
