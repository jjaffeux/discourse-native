import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final direction in TextDirection.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'filter token bounds and actions $platform $direction $scale',
          (tester) async {
            var edits = 0;
            var removals = 0;
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(platform: platform),
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Directionality(
                    textDirection: direction,
                    child: Scaffold(
                      body: Center(
                        child: SizedBox(
                          width: 300,
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: DFilterToken(
                              label: 'Category',
                              value: 'Design',
                              editLabel: 'Change category',
                              removeLabel: 'Remove category',
                              editKey: const ValueKey('edit'),
                              removeKey: const ValueKey('remove'),
                              onEdited: () => edits++,
                              onRemoved: () => removals++,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final edit = find.byKey(const ValueKey('edit'));
            final remove = find.byKey(const ValueKey('remove'));
            final pill = tester.getRect(find.byType(DFilterToken));
            final editBounds = tester.getRect(edit);
            final removeBounds = tester.getRect(remove);
            expect(pill.height, closeTo(18 * scale + 6, .01));
            expect(editBounds.top, pill.top);
            expect(removeBounds.top, pill.top);
            expect(editBounds.bottom, pill.bottom);
            expect(removeBounds.bottom, pill.bottom);
            expect(
              editBounds.width + removeBounds.width,
              closeTo(pill.width, .01),
            );
            expect(
              direction == TextDirection.ltr
                  ? editBounds.right
                  : removeBounds.right,
              direction == TextDirection.ltr
                  ? removeBounds.left
                  : editBounds.left,
            );
            await tester.tap(edit);
            await tester.tap(remove);
            expect(edits, 1);
            expect(removals, 1);
            Focus.of(
              tester.element(find.text('Category: Design')),
            ).requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            expect(edits, 2);
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            expect(removals, 2);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
