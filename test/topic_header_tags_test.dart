import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_header_tags.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty tags show a labeled add action only when editable', (
    tester,
  ) async {
    for (final canEditTags in [true, false]) {
      for (final width in [72.0, 180.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: TopicHeaderTags(
                      siteUrl: 'https://meta.example',
                      onTagNavigate: (_, {newTab = false}) {},
                      topic: TopicDetail(
                        id: 1,
                        title: 'No tags',
                        stream: const [],
                        canEditTags: canEditTags,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final add = find.byKey(const ValueKey('topic-header-edit-tags'));
        expect(
          find.text('Add tag'),
          canEditTags ? findsOneWidget : findsNothing,
        );
        expect(add, canEditTags ? findsOneWidget : findsNothing);
        if (canEditTags) {
          expect(tester.getRect(add).right, lessThanOrEqualTo(width));
          expect(tester.getSize(add).height, lessThan(50));
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'width $width, editable $canEditTags',
        );
      }
    }
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('fits long tag names at text scale $scale', (tester) async {
      final tags = [
        for (var id = 1; id <= 27; id++)
          TopicTag(id: id, name: 'long-production-region-$id'),
      ];
      for (final width in [72.0, 180.0, 320.0, 700.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: TopicHeaderTags(
                      siteUrl: 'https://meta.example',
                      onTagNavigate: (_, {newTab = false}) {},
                      topic: TopicDetail(
                        id: 1,
                        title: 'Many tags',
                        stream: const [],
                        tags: tags,
                        canEditTags: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final strip = find.byType(TopicHeaderTags);
        final overflow = find.byKey(const ValueKey('topic-header-more-tags'));
        expect(overflow, findsOneWidget);
        expect(tester.getRect(overflow).right, lessThanOrEqualTo(width));
        expect(tester.getSize(strip).height, lessThan(50));
        final visible = tags
            .where(
              (tag) => find
                  .byKey(ValueKey(('topic-header-tag', tag.name)))
                  .evaluate()
                  .isNotEmpty,
            )
            .toList();
        expect(visible.length, lessThanOrEqualTo(3));
        for (final tag in visible) {
          expect(
            tester
                .getCenter(find.byKey(ValueKey(('topic-header-tag', tag.name))))
                .dy,
            closeTo(tester.getCenter(overflow).dy, 1),
          );
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'width $width, scale $scale',
        );
      }
    });
  }
}
