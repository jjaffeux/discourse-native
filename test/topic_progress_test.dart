import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/topic_progress.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
            find.descendant(
              of: find.text(label),
              matching: find.byType(RichText),
            ),
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
          final touch =
              Theme.of(tester.element(button)).platform ==
              TargetPlatform.android;
          expect(
            bounds.height,
            touch
                ? 48
                : DControlStyle.scaledHeight(
                    DControlSize.regular,
                    TextScaler.linear(scenario.scale),
                  ),
          );
          expect(
            tester.widget<DButton>(button).variant,
            DButtonVariant.outline,
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
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'progress trigger supports keyboard activation and popup semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Center(
              child: TopicProgressButton(
                position: 0,
                total: 0,
                expanded: true,
                onPressed: () => presses++,
              ),
            ),
          ),
        ),
      );
      final trigger = find.byKey(const ValueKey('topic-progress-button'));
      expect(find.text('1 / 1'), findsOneWidget);
      expect(
        tester
            .getSemantics(trigger)
            .getSemanticsData()
            .flagsCollection
            .isExpanded,
        Tristate.isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(presses, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
