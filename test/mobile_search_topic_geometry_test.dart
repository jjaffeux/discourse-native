import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/topic_post_list.dart';
import 'support/topic_sheet_scroll_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/notification_opens');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets(
    'search words keep the scrolled topic below the app header',
    (tester) async {
      final shell = await pumpTopicSheetScrollFixture(tester);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      final viewport = find.byType(DSheetViewport);
      final header = find.byKey(const ValueKey('mobile-header'));
      final edge = DSheetPageBand.edgeOf(
        tester.element(topicPostListFinder()),
      )!;
      final scroll = topicPostList(tester).controller!;
      scroll.jumpTo(800);
      await tester.pumpAndSettle();
      final expectedTop = tester.getRect(header).bottom + 6;
      final before = tester.getRect(viewport).top + edge.value;
      expect(before, closeTo(expectedTop, 1));

      shell.search.setPageWords(
        shell.currentInstance!.url,
        shell.activeTabId,
        shell.currentContent!.id,
        'scrolling',
      );
      await tester.pumpAndSettle();
      final after = tester.getRect(viewport).top + edge.value;
      expect(
        after,
        closeTo(expectedTop, 1),
        reason:
            'Search highlighting must not reserve a second gap below the app header.',
      );
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      final clear = find.byKey(const ValueKey('topic-search-words'));
      expect(clear.hitTestable(), findsOneWidget);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(
        shell.search.wordsFor(
          shell.currentInstance!.url,
          shell.activeTabId,
          shell.currentContent!.id,
        ),
        isEmpty,
      );
      expect(clear, findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  for (final postNumber in [1, 2]) {
    testWidgets(
      'search result at post $postNumber keeps the topic edge aligned',
      (tester) async {
        final shell = await pumpTopicSheetScrollFixture(tester);
        shell.handleBack();
        await tester.pumpAndSettle();
        shell.openSearchResult(
          SearchPostHit(
            postId: postNumber,
            topicId: 7,
            postNumber: postNumber,
            topicTitle: 'Reading a rich discussion in a sheet',
            topicSlug: 'topic-7',
            username: 'reader',
            excerpt: const SearchExcerpt([]),
          ),
          words: 'scrolling',
        );
        await tester.pumpAndSettle();
        expect(shell.currentContent?.topicId, 7);
        expect(
          shell.search.wordsFor(
            shell.currentInstance!.url,
            shell.activeTabId,
            shell.currentContent!.id,
          ),
          'scrolling',
        );
        final target = tester.getRect(find.byKey(ValueKey(postNumber)));
        final readingArea = topicReadingViewportRect(tester);
        expect(target.bottom, greaterThan(readingArea.top));
        expect(target.top, lessThan(readingArea.bottom));
        final scroll = topicPostList(tester).controller!;
        final initialOffset = scroll.offset;
        final viewport = find.byType(DSheetViewport);
        final header = find.byKey(const ValueKey('mobile-header'));
        final edge = DSheetPageBand.edgeOf(
          tester.element(topicPostListFinder()),
        )!;
        if (postNumber == 2) {
          expect(
            tester.getRect(viewport).top + edge.value,
            closeTo(tester.getRect(header).bottom + 6, 1),
          );
        }
        await tester.drag(topicPostListFinder(), const Offset(0, -800));
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(initialOffset));
        expect(
          tester.getRect(viewport).top + edge.value,
          closeTo(tester.getRect(header).bottom + 6, 1),
        );
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }
}
