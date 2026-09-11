import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_tag_picker.dart';
import 'package:discourse_native/src/shell/topic_taxonomy_picker.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    TopicTagSearchCallback? search,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: platform),
        home: Scaffold(
          body: TopicTaxonomyPickerAnchor(
            child: Builder(
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
                      search:
                          search ??
                          (_) async => const TopicTagSearch(
                            tags: [design, mobile, support],
                          ),
                    ),
                  );
                },
                child: const Text('Open tags'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open tags'));
    await tester.pumpAndSettle();
  }

  testWidgets('enabled tag rows highlight only while hovered', (tester) async {
    final strategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
    await openPicker(tester, selectedTags: const [design], onClosed: (_) {});
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    Finder row(String name) =>
        find.ancestor(of: option(name), matching: find.byType(DItem));
    Color? background(String name) =>
        (tester
                    .widget<AnimatedContainer>(
                      find
                          .descendant(
                            of: row(name),
                            matching: find.byType(AnimatedContainer),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration)
            .color;

    for (final tag in [design, support]) {
      expect(background(tag.name), Colors.transparent);
      await mouse.moveTo(tester.getCenter(option(tag.name)));
      await tester.pumpAndSettle();
      expect(
        background(tag.name),
        DTokens.of(tester.element(row(tag.name))).muted,
      );
      expect(tester.widget<DCheckbox>(option(tag.name)).value, tag == design);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(background(tag.name), Colors.transparent);
    }
  });

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
    expect(tester.widget<DCheckbox>(option(support.name)).enabled, isFalse);

    await tester.tap(option(design.name));
    await tester.pumpAndSettle();
    expect(results.last, [mobile]);
    await openPicker(
      tester,
      selectedTags: results.last!,
      onClosed: results.add,
    );
    expect(tester.widget<DCheckbox>(option(support.name)).enabled, isTrue);

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

  testWidgets(
    'keyboard traversal keeps browse separate from disabled selection',
    (tester) async {
      final results = <List<TopicTag>?>[];
      final opened = <TopicTag>[];
      await openPicker(
        tester,
        onClosed: results.add,
        onTagNavigate: (tag, {newTab = false}) => opened.add(tag),
      );
      // Input → selected checkbox/link pairs → the unselected tag's link.
      // Its checkbox is disabled because the topic is already at its tag limit.
      for (var index = 0; index < 5; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened, [support]);
      expect(results, [null]);
      expect(find.byType(TopicTagPicker), findsNothing);
    },
  );

  testWidgets('long results scroll independently of the search field', (
    tester,
  ) async {
    final tags = [
      for (var index = 0; index < 40; index++)
        TopicTag(id: 100 + index, name: 'region-$index'),
    ];
    final results = <List<TopicTag>?>[];
    await openPicker(tester, selectedTags: tags, onClosed: results.add);
    final query = find.byKey(const ValueKey('topic-tag-picker-query'));
    final queryBounds = tester.getRect(query);
    final popupBounds = tester.getRect(find.byType(DPopoverContent));
    await tester.ensureVisible(option('region-39'));
    await tester.pumpAndSettle();
    expect(tester.getRect(query), queryBounds);
    expect(tester.getRect(find.byType(DPopoverContent)), popupBounds);
    expect(option('region-39').hitTestable(), findsOneWidget);
    await tester.tap(option('region-39'));
    await tester.pumpAndSettle();
    expect(results.single, tags.take(39).toList());
    expect(tester.takeException(), isNull);
  });

  testWidgets('popup fits short results and shrinks with the search', (
    tester,
  ) async {
    final results = <List<TopicTag>?>[];
    await openPicker(
      tester,
      selectedTags: const [],
      onClosed: results.add,
      onTagNavigate: (_, {newTab = false}) {},
      search: (term) async => TopicTagSearch(
        tags: [
          design,
          mobile,
          support,
        ].where((tag) => tag.name.contains(term)).toList(),
      ),
    );

    final query = find.byKey(const ValueKey('topic-tag-picker-query'));
    final popup = find.byType(DPopoverContent);
    final initialBounds = tester.getRect(popup);
    final queryBounds = tester.getRect(query);
    expect(
      initialBounds.bottom - tester.getBottomLeft(option('support')).dy,
      inInclusiveRange(0, 16),
    );

    await tester.enterText(query, 'mobile');
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(option('design'), findsNothing);
    expect(option('support'), findsNothing);
    expect(tester.getRect(query), queryBounds);
    expect(tester.getSize(popup).height, lessThan(initialBounds.height));
    expect(
      tester.getBottomLeft(popup).dy -
          tester.getBottomLeft(option('mobile')).dy,
      inInclusiveRange(0, 16),
    );

    await tester.tap(option('mobile'));
    await tester.pumpAndSettle();
    expect(results, [
      [mobile],
    ]);
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

    expect(find.byType(TopicTaxonomyPickerProgress), findsOneWidget);
    expect(createRow, findsOneWidget);
    expect(tester.element(createRow), same(createElement));

    pendingSearch.complete(const TopicTagSearch());
    await tester.pumpAndSettle();

    expect(find.byType(TopicTaxonomyPickerProgress), findsNothing);
    expect(createRow, findsOneWidget);
    expect(tester.element(createRow), same(createElement));
  });
}
