import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_header_tags.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tag actions separate editing, navigation, and filtering', (
    tester,
  ) async {
    const tag = TopicTag(id: 1, name: 'community');
    var edits = 0;
    final opened = <({TopicTag tag, bool newTab})>[];
    final filtered = <TopicTag>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: TopicHeaderTags(
            siteUrl: 'https://meta.example',
            topic: const TopicDetail(
              id: 1,
              title: 'A topic',
              stream: [],
              tags: [tag],
              canEditTags: true,
            ),
            onEdit: () => edits++,
            onTagNavigate: (tag, {newTab = false}) =>
                opened.add((tag: tag, newTab: newTab)),
            onTagFilter: filtered.add,
          ),
        ),
      ),
    );
    final badge = find.byKey(const ValueKey(('topic-header-tag', 'community')));
    await tester.tap(badge);
    expect(edits, 1);
    expect(opened, isEmpty);
    await tester.tap(
      badge,
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await tester.pumpAndSettle();
    expect(opened, [(tag: tag, newTab: true)]);
    for (final action in ['open', 'open-new-tab', 'filter']) {
      await tester.tap(
        badge,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Open in new tab'), findsOneWidget);
      expect(find.text('Use as filter'), findsOneWidget);
      await tester.tap(
        find.byKey(ValueKey(('topic-header-tag-$action', tag.name))),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DContextMenuContent), findsNothing);
    }
    expect(edits, 1);
    expect(opened, [
      (tag: tag, newTab: true),
      (tag: tag, newTab: false),
      (tag: tag, newTab: true),
    ]);
    expect(filtered, [tag]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tag keyboard menus restore focus without another tab stop', (
    tester,
  ) async {
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: TopicHeaderTags(
            siteUrl: 'https://meta.example',
            topic: const TopicDetail(
              id: 1,
              title: 'A topic',
              stream: [],
              tags: [
                TopicTag(name: 'community'),
                TopicTag(name: 'mobile'),
              ],
              canEditTags: true,
            ),
            onEdit: () => edits++,
            onTagNavigate: (_, {newTab = false}) {},
          ),
        ),
      ),
    );
    FocusNode tagFocus(String name) => tester
        .widget<FocusableActionDetector>(
          find.descendant(
            of: find.byKey(ValueKey(('topic-header-tag', name))),
            matching: find.byType(FocusableActionDetector),
          ),
        )
        .focusNode!;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(tagFocus('community').hasPrimaryFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.byType(DContextMenuContent), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tagFocus('community').hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(edits, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(tagFocus('mobile').hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty tags show a compact accessible add action only when editable',
    (tester) async {
      for (final canEditTags in [true, false]) {
        for (final width in [72.0, 180.0]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark,
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Align(
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
            ),
          );
          await tester.pumpAndSettle();
          final add = find.byKey(const ValueKey('topic-header-edit-tags'));
          expect(
            find.byTooltip('Add tag'),
            canEditTags ? findsOneWidget : findsNothing,
          );
          expect(add, canEditTags ? findsOneWidget : findsNothing);
          expect(find.text('Add tag'), findsNothing);
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
    },
  );

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
                body: SingleChildScrollView(
                  child: Align(
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
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('topic-header-more-tags')),
          findsNothing,
        );
        for (final tag in tags) {
          final tagFinder = find.byKey(
            ValueKey(('topic-header-tag', tag.name)),
          );
          expect(tagFinder, findsOneWidget);
          expect(tester.getRect(tagFinder).right, lessThanOrEqualTo(width));
          expect(tester.getRect(tagFinder).left, greaterThanOrEqualTo(0));
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
