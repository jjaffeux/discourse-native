import 'dart:async';

import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/anchored_picker.dart';
import 'package:discourse_native/src/shell/topic_tag_picker.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
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
    List<TopicTag> selectedTags = const [design, mobile],
    TopicTagNavigationCallback? onTagNavigate,
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
                    selectedTags: selectedTags,
                    onTagNavigate: onTagNavigate,
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

  for (final tag in [design, support]) {
    for (final target in ['option', 'open']) {
      testWidgets(
        'middle-clicking the $target for ${tag.name} opens a tab without selecting',
        (tester) async {
          final results = <List<TopicTag>?>[];
          final opened = <({TopicTag tag, bool newTab})>[];
          await openPicker(
            tester,
            onClosed: results.add,
            onTagNavigate: (tag, {newTab = false}) =>
                opened.add((tag: tag, newTab: newTab)),
          );

          await tester.tap(
            find.byKey(ValueKey(('topic-tag-picker-$target', tag.name))),
            kind: PointerDeviceKind.mouse,
            buttons: kMiddleMouseButton,
          );
          await tester.pumpAndSettle();

          expect(opened, [(tag: tag, newTab: true)]);
          expect(results, [null]);
          expect(find.byType(TopicTagPicker), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'middle-button drags and cancelled presses do not open or select tags',
    (tester) async {
      final results = <List<TopicTag>?>[];
      final opened = <TopicTag>[];
      await openPicker(
        tester,
        onClosed: results.add,
        onTagNavigate: (tag, {newTab = false}) => opened.add(tag),
      );

      for (final target in ['option', 'open']) {
        final position = tester.getCenter(
          find.byKey(ValueKey(('topic-tag-picker-$target', design.name))),
        );
        final drag = await tester.startGesture(
          position,
          kind: PointerDeviceKind.mouse,
          buttons: kMiddleMouseButton,
        );
        await drag.moveBy(const Offset(100, 0));
        await drag.up();
        final cancelled = await tester.startGesture(
          position,
          kind: PointerDeviceKind.mouse,
          buttons: kMiddleMouseButton,
        );
        await cancelled.cancel();
        await tester.pumpAndSettle();
      }

      expect(opened, isEmpty);
      expect(results, isEmpty);
      expect(find.byType(TopicTagPicker), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final tag in [design, support]) {
      testWidgets(
        'opens ${tag.name} on ${platform.name} without changing the selection at the tag limit',
        (tester) async {
          final results = <List<TopicTag>?>[];
          final opened = <TopicTag>[];
          await openPicker(
            tester,
            platform: platform,
            onClosed: results.add,
            onTagNavigate: (tag, {newTab = false}) => opened.add(tag),
          );

          expect(
            tester.getTopLeft(option(mobile.name)).dy -
                tester.getBottomLeft(option(design.name)).dy,
            greaterThanOrEqualTo(4),
          );
          await tester.tap(
            find.byKey(ValueKey(('topic-tag-picker-open', tag.name))),
          );
          await tester.pumpAndSettle();

          expect(opened, [tag]);
          expect(results, [null]);
          expect(find.byType(TopicTagPicker), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('applies each ${platform.name} tag removal on selection', (
      tester,
    ) async {
      final results = <List<TopicTag>?>[];
      await openPicker(tester, platform: platform, onClosed: results.add);

      await tester.tap(option(design.name));
      await tester.pumpAndSettle();
      expect(find.byType(TopicTagPicker), findsNothing);
      expect(results, [
        [mobile],
      ]);

      await openPicker(
        tester,
        platform: platform,
        selectedTags: results.last!,
        onClosed: results.add,
      );
      await tester.tap(option(mobile.name));
      await tester.pumpAndSettle();
      expect(find.byType(TopicTagPicker), findsNothing);
      expect(results.last, isEmpty);
    });
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
    expect(results.last, [mobile]);
    await openPicker(
      tester,
      selectedTags: results.last!,
      onClosed: results.add,
    );
    expect(
      tester.widget<AnchoredPickerOption>(option(support.name)).enabled,
      isTrue,
    );

    await tester.tap(option(support.name));
    await tester.pumpAndSettle();

    expect(find.byType(TopicTagPicker), findsNothing);
    expect(results.last, [mobile, support]);
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

  testWidgets('search finds selected tags and Enter can remove a match', (
    tester,
  ) async {
    List<TopicTag>? selection;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TopicTagPicker(
            selectedTags: const [design, mobile],
            capabilities: const TopicComposerCapabilities(canTagTopics: true),
            search: (_) async => const TopicTagSearch(),
            onSelected: (tags) => selection = tags,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('topic-tag-picker-query')),
      'MOBILE',
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(option('design'), findsNothing);
    expect(option('mobile'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(selection, [design]);
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
