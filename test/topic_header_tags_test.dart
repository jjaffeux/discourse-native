import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_header_tags.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'opening every tag inline reaches the last on $platform at $textScale',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final tags = List.generate(
            220,
            (index) => TopicTag(id: index + 1, name: 'tag-$index'),
          );
          final openings = <(TopicTag, bool)>[];
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark.copyWith(platform: platform),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: TopicHeaderTags(
                    siteUrl: 'https://meta.example',
                    topic: TopicDetail(
                      id: 1,
                      title: 'Many tags',
                      stream: const [],
                      tags: tags,
                    ),
                    onTagNavigate: (tag, {newTab = false, panel}) =>
                        openings.add((tag, newTab)),
                  ),
                ),
              ),
            ),
          );
          final more = find.byKey(const ValueKey('topic-header-more-tags'));
          final shownBefore = tags
              .where(
                (tag) => find
                    .byKey(ValueKey(('topic-header-tag', tag.name)))
                    .evaluate()
                    .isNotEmpty,
              )
              .length;
          expect(shownBefore, lessThan(tags.length));
          expect(
            find.descendant(
              of: more,
              matching: find.text('+${tags.length - shownBefore}'),
            ),
            findsOneWidget,
          );
          await tester.tap(more);
          await tester.pumpAndSettle();
          expect(more, findsNothing);
          for (final tag in tags) {
            expect(
              find.byKey(ValueKey(('topic-header-tag', tag.name))),
              findsOneWidget,
              reason: tag.name,
            );
          }
          final last = find.byKey(
            const ValueKey(('topic-header-tag', 'tag-219')),
          );
          await tester.ensureVisible(last);
          await tester.pumpAndSettle();
          await tester.tap(last);
          await tester.pumpAndSettle();
          expect(openings, [(tags.last, false)]);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('tag context menu chooses a panel and tab', (tester) async {
    final openings = <(bool, ForumPanel?)>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: TopicHeaderTags(
            siteUrl: 'https://meta.example',
            topic: const TopicDetail(
              id: 1,
              title: 'Tagged topic',
              stream: [],
              tags: [TopicTag(id: 2, name: 'design')],
            ),
            onTagNavigate: (tag, {newTab = false, panel}) =>
                openings.add((newTab, panel)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey(('topic-header-tag', 'design'))),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in new secondary tab'));
    await tester.pumpAndSettle();
    expect(openings, [(true, ForumPanel.secondary)]);
  });

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
                      onTagNavigate: (_, {newTab = false, panel}) {},
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

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('fits long tag names on $platform at text scale $scale', (
        tester,
      ) async {
        final tags = [
          for (var id = 1; id <= 27; id++)
            TopicTag(id: id, name: 'long-production-region-$id'),
        ];
        for (final width in [72.0, 180.0, 320.0, 700.0]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark.copyWith(platform: platform),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: TopicHeaderTags(
                        siteUrl: 'https://meta.example',
                        onTagNavigate: (_, {newTab = false, panel}) {},
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
          // The line keeps the first tags that fit beside the count.
          expect(visible, tags.take(visible.length));
          expect(
            find.descendant(
              of: overflow,
              matching: find.text('+${tags.length - visible.length}'),
            ),
            findsOneWidget,
          );
          for (final tag in visible) {
            final chip = find.byKey(ValueKey(('topic-header-tag', tag.name)));
            expect(tester.getRect(chip).right, lessThanOrEqualTo(width));
            expect(
              tester.getCenter(chip).dy,
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
}
