import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/topic_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'placeholders stay transparent and still through the grace period',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: TopicSkeletonReveal(
              child: DSkeletonRegion(
                semanticsLabel: 'Loading topic',
                child: DSkeleton(key: ValueKey('shape'), width: 80, height: 10),
              ),
            ),
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      try {
        double opacity() => tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity))
            .opacity;
        bool ticking() => TickerMode.valuesOf(
          tester.element(find.byKey(const ValueKey('shape'))),
        ).enabled;

        expect(
          tester.getSize(find.byKey(const ValueKey('shape'))),
          const Size(80, 10),
        );
        expect(opacity(), 0);
        expect(ticking(), isFalse);
        expect(find.bySemanticsLabel('Loading topic'), findsOneWidget);

        await tester.pump(
          TopicSkeletonReveal.delay - const Duration(milliseconds: 1),
        );
        expect(opacity(), 0);

        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(DMotion.enter);
        expect(opacity(), 1);
        expect(ticking(), isTrue);
      } finally {
        handle.dispose();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
