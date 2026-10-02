import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/topic_post_sliver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final policy in ScrollPositionAlignmentPolicy.values) {
    testWidgets('reveals post content below the header with $policy', (
      tester,
    ) async {
      late DPageHeaderGeometry header;
      final scroll = TopicPostScrollController(
        () => null,
        anchorOffset: () => null,
        topInset: () => header.visibleExtent,
      );
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: DPageSurface.scrollable(
            framed: false,
            header: const SizedBox(height: 80),
            bodyBuilder: (_, geometry) {
              header = geometry;
              return CustomScrollView(
                controller: scroll,
                slivers: [
                  SliverToBoxAdapter(child: header.spacer),
                  SliverList.list(
                    children: [
                      for (var index = 0; index < 20; index++)
                        SizedBox(
                          key: ValueKey(index),
                          height: 100,
                          child: Text('Post $index'),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      );
      // Start with the row behind the header, or past the bottom when revealing
      // at the end. Each policy should keep its own visibility contract.
      scroll.jumpTo(
        policy == ScrollPositionAlignmentPolicy.keepVisibleAtEnd ? 0 : 600,
      );
      await tester.pump();
      final post = find.byKey(const ValueKey(5));
      await Scrollable.ensureVisible(
        tester.element(post),
        alignmentPolicy: policy,
      );
      await tester.pump();
      final rect = tester.getRect(post);
      if (policy == ScrollPositionAlignmentPolicy.keepVisibleAtEnd) {
        expect(rect.bottom, scroll.position.viewportDimension);
      } else {
        expect(rect.top, 80);
      }
      expect(post.hitTestable(), findsOneWidget);

      await Scrollable.ensureVisible(tester.element(post), alignment: .5);
      await tester.pump();
      expect(
        tester.getCenter(post).dy,
        (80 + scroll.position.viewportDimension) / 2,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
