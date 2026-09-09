import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/empty_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'every example fits narrow large-text RTL and wide dark previews',
    (tester) async {
      addTearDown(tester.view.reset);
      for (final wide in [false, true]) {
        tester.view.physicalSize = Size(wide ? 1000 : 320, 1000);
        tester.view.devicePixelRatio = 1;
        for (final example in emptyExamples.examples) {
          await tester.pumpWidget(
            MaterialApp(
              theme: wide ? ThemeData.dark() : ThemeData.light(),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    size: Size(wide ? 1000 : 320, 1000),
                    textScaler: TextScaler.linear(wide ? 1 : 2),
                    disableAnimations: true,
                  ),
                  child: Directionality(
                    textDirection: wide ? TextDirection.ltr : TextDirection.rtl,
                    child: SingleChildScrollView(
                      child: Builder(
                        key: ValueKey(example.title),
                        builder: example.builder,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${example.title}, wide=$wide',
          );
        }
      }
    },
  );

  testWidgets('search validates submits and exposes local support feedback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: EmptySearchSample())),
    );
    await tester.tap(find.text('Search'));
    await tester.pump();
    expect(find.text('Enter a search query.'), findsOneWidget);
    await tester.enterText(find.byType(DInput), 'guide');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('No local pages match “guide”.'), findsOneWidget);
    await tester.tap(find.text('Contact support'));
    await tester.pump();
    expect(
      find.text('Support is available at help@example.test.'),
      findsOneWidget,
    );
  });
}
