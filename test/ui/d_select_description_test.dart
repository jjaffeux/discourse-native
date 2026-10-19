import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'described options fit, announce their context and select at $scale text',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          String? selected = 'first';
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(320, 640),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: Center(
                    child: StatefulBuilder(
                      builder: (context, setState) =>
                          DSelect<String>.controlled(
                            width: 128,
                            value: selected,
                            entries: const [
                              DSelectItem(
                                value: 'first',
                                textValue: 'First',
                                description: 'Find matching messages first',
                                child: Text('First'),
                              ),
                              DSelectItem(
                                value: 'second',
                                textValue: 'Second',
                                description: 'Show the newest messages first',
                                child: Text('Second'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => selected = value),
                          ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.byType(DSelect<String>));
          await tester.pumpAndSettle();
          expect(
            find.bySemanticsLabel('Second, Show the newest messages first'),
            findsOneWidget,
          );
          final bounds = tester.getRect(find.byType(DPopoverContent));
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(320));
          expect(tester.takeException(), isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(selected, 'second');
          expect(find.byType(DPopoverContent), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
