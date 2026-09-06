import 'package:discourse_native/src/shell/topic_progress.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'large progress counts remain complete on one line and clickable',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var presses = 0;
        for (final scenario in [
          (position: 5150, total: 5188, width: 260.0, scale: 1.0),
          (position: 5150, total: 5188, width: 110.0, scale: 1.0),
          (position: 99999, total: 125000, width: 400.0, scale: 1.5),
          (position: 99999, total: 125000, width: 96.0, scale: 1.5),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark,
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(scenario.scale),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: scenario.width),
                      child: TopicProgressButton(
                        position: scenario.position,
                        total: scenario.total,
                        onPressed: () => presses++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final button = find.byKey(const ValueKey('topic-progress-button'));
          final bounds = tester.getRect(button);
          final label = '${scenario.position} / ${scenario.total}';
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: button, matching: find.byType(RichText)),
          );
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: label.length),
          );
          expect(find.text(label), findsOneWidget);
          expect(boxes.map((box) => box.top).toSet(), hasLength(1));
          expect(paragraph.didExceedMaxLines, isFalse);
          for (final box in boxes) {
            expect(
              bounds
                  .inflate(.01)
                  .contains(paragraph.localToGlobal(Offset(box.left, box.top))),
              isTrue,
            );
            expect(
              bounds
                  .inflate(.01)
                  .contains(
                    paragraph.localToGlobal(Offset(box.right, box.bottom)),
                  ),
              isTrue,
            );
          }
          expect(bounds.width, lessThanOrEqualTo(scenario.width));
          expect(bounds.height, 32);
          final fill = tester.getRect(
            find.byKey(const ValueKey('topic-progress-fill')),
          );
          expect(
            fill.width / bounds.width,
            closeTo(scenario.position / scenario.total, .001),
          );
          expect(
            find.bySemanticsLabel(
              RegExp(
                'Topic progress, post ${scenario.position} of ${scenario.total}',
              ),
            ),
            findsOneWidget,
          );
          final before = presses;
          await tester.tap(button);
          await tester.pump();
          expect(presses, before + 1);
          expect(tester.takeException(), isNull);
        }
      } finally {
        semantics.dispose();
      }
    },
  );
}
