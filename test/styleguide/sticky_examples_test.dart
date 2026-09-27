import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/sticky_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sticky preview scrolls at narrow widths and large text in RTL', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Center(
                child: SizedBox(
                  width: 320,
                  child: Builder(
                    builder: stickyExamples.examples.single.builder,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byType(DAvatar).first).dy,
      closeTo(tester.getTopLeft(find.byType(CustomScrollView)).dy + 16, .01),
    );
    expect(tester.takeException(), isNull);
  });
}
