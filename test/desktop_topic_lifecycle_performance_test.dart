import 'dart:convert';

import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_test_harness.dart';
import 'support/tab_switch_fixture.dart';

void main() {
  setUp(() {
    const channel = MethodChannel('org.discourse.native/notification_opens');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  });

  testWidgets(
    'desktop topic opening and closing work',
    (tester) async {
      final shell = await pumpTabSwitchFixture(tester);
      shell.closeTab('reader-a');
      shell.closeTab('list-b');
      shell.selectTab('list-a');
      await tester.pumpAndSettle();
      final source = tester.state(find.byType(TopicListView));
      final scrollable = find
          .descendant(
            of: find.byType(TopicListView),
            matching: find.byWidgetPredicate(
              (widget) => widget is Scrollable && widget.axis == Axis.vertical,
            ),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(20);
      await tester.pumpAndSettle();
      final counts = <String, Map<String, int>>{};
      final lists = tester
          .elementList(find.byType(TopicListView, skipOffstage: false))
          .toSet();
      var phase = '';
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (phase.isEmpty) return;
        final work = counts.putIfAbsent(phase, () => {});
        work.update('total', (n) => n + 1, ifAbsent: () => 1);
        if (element.widget is TopicView) {
          work.update('readerBuilds', (n) => n + 1, ifAbsent: () => 1);
        }
        if (element.widget is TopicListView && lists.add(element)) {
          work.update('sourceMounts', (n) => n + 1, ifAbsent: () => 1);
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      for (var round = 0; round < 3; round++) {
        phase = 'open-$round';
        await tester.tap(
          topicListTitle('Discussion 1 about fast navigation and reading'),
        );
        await tester.pumpAndSettle();
        final opened = shell.activeTabId!;
        expect(shell.visibleTopicContext?.topicId, 1);
        expect(
          find.byWidgetPredicate(
            (widget) => widget is TopicView && widget.route?.topicId == 1,
          ),
          findsOneWidget,
        );
        expect(shell.tabContext(opened).currentPostIds, hasLength(60));
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is RichText &&
                widget.text.toPlainText().contains('Reply 1 with'),
          ),
          findsWidgets,
        );
        const expectRetention = bool.fromEnvironment(
          'EXPECT_RETAINED_LIST',
          defaultValue: true,
        );
        expect(source.mounted, expectRetention);
        if (expectRetention) {
          expect(TickerMode.valuesOf(source.context).enabled, isFalse);
          expect(Focus.of(source.context).descendantsAreFocusable, isFalse);
        }
        final reader = tester.state(
          find.byWidgetPredicate(
            (widget) => widget is TopicView && widget.route?.topicId == 1,
          ),
        );
        phase = 'close-$round';
        await tester.tap(
          find.descendant(
            of: find.byWidgetPredicate(
              (widget) => widget is TopicView && widget.route?.topicId == 1,
            ),
            matching: find.byKey(const ValueKey('topic-close-reader')),
          ),
        );
        await tester.pumpAndSettle();
        expect(shell.tabContext(opened).currentContent?.isTopicList, isTrue);
        expect(shell.activeTabId, 'list-a');
        if (expectRetention) {
          expect(tester.state(find.byType(TopicListView)), same(source));
          expect(position.pixels, closeTo(20, 1));
          expect(TickerMode.valuesOf(source.context).enabled, isTrue);
        }
        expect(reader.mounted, isFalse);
        expect(find.byKey(const ValueKey('forum-tabs-bar')), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      }
      phase = '';
      debugPrint(
        'TOPIC_LIFECYCLE_WORK ${jsonEncode({'platform': defaultTargetPlatform.name, 'counts': counts, 'errors': 0})}',
      );
      if (const bool.fromEnvironment(
        'EXPECT_RETAINED_LIST',
        defaultValue: true,
      )) {
        for (final entry in counts.entries.where(
          (entry) => entry.key.startsWith('close'),
        )) {
          expect(entry.value['sourceMounts'] ?? 0, 0);
        }
        for (final entry in counts.entries.where(
          (entry) => entry.key.startsWith('open'),
        )) {
          expect(entry.value['readerBuilds'], 1);
        }
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );

  testWidgets('hidden desktop source survives resizing and topic replacement', (
    tester,
  ) async {
    final shell = await pumpTabSwitchFixture(tester);
    shell.closeTab('reader-a');
    shell.selectTab('list-a');
    await tester.pumpAndSettle();
    final source = tester.state(find.byType(TopicListView));
    final sourceSize = tester.getSize(find.byType(TopicListView));
    await tester.tap(
      topicListTitle('Discussion 1 about fast navigation and reading'),
    );
    await tester.pumpAndSettle();
    final firstReader = tester.state(
      find.byWidgetPredicate(
        (widget) => widget is TopicView && widget.route?.topicId == 1,
      ),
    );
    tester.view.physicalSize = const Size(1600, 1000);
    await shell.forumSettings.setThemeMode(
      shell.currentInstance!.url,
      AppThemeMode.dark,
    );
    await shell.appSettings.setTextScale(AppTextScale.percent150);
    await tester.pumpAndSettle();
    shell.openTopicUrl('/t/discussion-2/2');
    await tester.pumpAndSettle();
    expect(firstReader.mounted, isFalse);
    expect(source.mounted, isTrue);
    final secondReader = find.descendant(
      of: primaryMainContent,
      matching: find.byWidgetPredicate(
        (widget) => widget is TopicView && widget.route?.topicId == 2,
      ),
    );
    await tester.tap(
      find.descendant(
        of: secondReader,
        matching: find.byKey(const ValueKey('topic-close-reader')),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(TopicListView)), same(source));
    expect(Theme.of(source.context).brightness, Brightness.dark);
    expect(tester.getSize(find.byType(TopicListView)), isNot(sourceSize));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
