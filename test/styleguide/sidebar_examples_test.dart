import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/sidebar_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'all Sidebar examples render narrow RTL large text and mobile content',
    (tester) async {
      for (final example in sidebarExamples.examples) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                  size: Size(360, 600),
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SizedBox(
                    width: 360,
                    child: SingleChildScrollView(
                      child: Builder(builder: example.builder),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: example.title);
        if (example.title != 'Documentation') {
          await tester.tap(find.byType(DSidebarTrigger));
          await tester.pump();
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: '${example.title} mobile open',
          );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: '${example.title} removed',
        );
      }
    },
  );
}
