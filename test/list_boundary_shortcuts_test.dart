import 'package:discourse_native/src/shell/list_boundary_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a press on an exempt child leaves a focused field its keyboard',
    (tester) async {
      final harness = await _pumpHarness(tester);
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.log.clear();

      await tester.tap(find.byKey(_exemptKey));
      await tester.pump();

      expect(harness.fieldFocus.hasPrimaryFocus, isTrue);
      expect(
        tester.testTextInput.log.map((call) => call.method),
        everyElement(isNot(isIn(['TextInput.clearClient', 'TextInput.hide']))),
      );

      await tester.tap(find.byKey(_listBodyKey));
      await tester.pump();

      expect(
        harness.fieldFocus.hasFocus,
        isFalse,
        reason: 'Any other press in the list still takes focus from the field.',
      );
    },
  );

  testWidgets('an exempt press still makes its list the keyboard owner', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);
    await tester.showKeyboard(find.byType(TextField));

    await tester.tap(find.byKey(_exemptKey));
    await tester.pump();
    harness.fieldFocus.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);

    expect(harness.exemptListStarts, 1);
    expect(harness.otherListStarts, 0);
  });
}

const _exemptKey = ValueKey('exempt-child');
const _listBodyKey = ValueKey('list-body');

final class _Harness {
  _Harness(this.fieldFocus);

  final FocusNode fieldFocus;
  var exemptListStarts = 0;
  var otherListStarts = 0;
}

Future<_Harness> _pumpHarness(WidgetTester tester) async {
  final fieldFocus = FocusNode();
  final otherScroll = ScrollController();
  final exemptScroll = ScrollController();
  addTearDown(fieldFocus.dispose);
  addTearDown(otherScroll.dispose);
  addTearDown(exemptScroll.dispose);
  final harness = _Harness(fieldFocus);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            TextField(focusNode: fieldFocus),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: ListBoundaryShortcuts(
                      initiallyActive: true,
                      scrollController: otherScroll,
                      onStart: () => harness.otherListStarts++,
                      onEnd: () {},
                      child: ListView(
                        controller: otherScroll,
                        children: const [SizedBox(height: 400)],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListBoundaryShortcuts(
                      scrollController: exemptScroll,
                      onStart: () => harness.exemptListStarts++,
                      onEnd: () {},
                      child: ListView(
                        controller: exemptScroll,
                        children: const [
                          ListBoundaryFocusExempt(
                            child: SizedBox(
                              key: _exemptKey,
                              height: 48,
                              child: ColoredBox(color: Colors.transparent),
                            ),
                          ),
                          SizedBox(
                            key: _listBodyKey,
                            height: 48,
                            child: ColoredBox(color: Colors.transparent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return harness;
}
