import 'dart:async';

import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/anchored_picker.dart';
import 'package:discourse_native/src/shell/topic_tag_picker.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const design = TopicTag(id: 7, name: 'design');
  const mobile = TopicTag(id: 8, name: 'mobile');
  const support = TopicTag(id: 9, name: 'support');

  Finder option(String name) =>
      find.byKey(ValueKey(('topic-tag-picker-option', name)));

  Future<void> openPicker(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.macOS,
    required ValueChanged<List<TopicTag>?> onClosed,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: platform),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                onClosed(
                  await showTopicTagPicker(
                    context: context,
                    anchorContext: context,
                    selectedTags: const [design, mobile],
                    capabilities: const TopicComposerCapabilities(
                      canTagTopics: true,
                      maxTagsPerTopic: 2,
                    ),
                    search: (_) async =>
                        const TopicTagSearch(tags: [design, mobile, support]),
                  ),
                );
              },
              child: const Text('Open tags'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open tags'));
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets(
      'keeps ${platform.name} picker open while removing all tags and saves on dismissal',
      (tester) async {
        final results = <List<TopicTag>?>[];
        await openPicker(tester, platform: platform, onClosed: results.add);

        for (final tag in [design, mobile]) {
          await tester.tap(option(tag.name));
          await tester.pumpAndSettle();

          expect(find.byType(TopicTagPicker), findsOneWidget);
          expect(
            tester.widget<AnchoredPickerOption>(option(tag.name)).selected,
            isFalse,
          );
          expect(results, isEmpty);
        }

        await tester.tapAt(const Offset(790, 10));
        await tester.pumpAndSettle();

        expect(find.byType(TopicTagPicker), findsNothing);
        expect(results, [<TopicTag>[]]);
      },
    );
  }

  testWidgets('adding after a removal closes with the updated selection', (
    tester,
  ) async {
    final results = <List<TopicTag>?>[];
    await openPicker(tester, onClosed: results.add);
    expect(
      tester.widget<AnchoredPickerOption>(option(support.name)).enabled,
      isFalse,
    );

    await tester.tap(option(design.name));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnchoredPickerOption>(option(support.name)).enabled,
      isTrue,
    );

    await tester.tap(option(support.name));
    await tester.pumpAndSettle();

    expect(find.byType(TopicTagPicker), findsNothing);
    expect(results, [
      [mobile, support],
    ]);
  });

  testWidgets('dismissing without changing tags returns no selection', (
    tester,
  ) async {
    final results = <List<TopicTag>?>[];
    await openPicker(tester, onClosed: results.add);

    await tester.tapAt(const Offset(790, 10));
    await tester.pumpAndSettle();

    expect(find.byType(TopicTagPicker), findsNothing);
    expect(results, [null]);
  });

  testWidgets('keeps the create row mounted while search results refresh', (
    tester,
  ) async {
    final pendingSearch = Completer<TopicTagSearch>();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: TopicTagPicker(
            selectedTags: const [],
            capabilities: const TopicComposerCapabilities(canCreateTag: true),
            search: (term) => term.isEmpty
                ? Future.value(const TopicTagSearch())
                : pendingSearch.future,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('topic-tag-picker-query')),
      'mobile',
    );
    await tester.pump();

    final createRow = find.byKey(const ValueKey('topic-tag-picker-create'));
    expect(createRow, findsOneWidget);
    final createElement = tester.element(createRow);

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AnchoredPickerProgress), findsOneWidget);
    expect(createRow, findsOneWidget);
    expect(tester.element(createRow), same(createElement));

    pendingSearch.complete(const TopicTagSearch());
    await tester.pumpAndSettle();

    expect(find.byType(AnchoredPickerProgress), findsNothing);
    expect(createRow, findsOneWidget);
    expect(tester.element(createRow), same(createElement));
  });
}
