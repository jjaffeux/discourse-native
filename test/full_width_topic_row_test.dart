import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/keyboard_navigation.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('TopicGolden')
          ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Bold.ttf')))
        .load();
  });

  testWidgets('sortable fields announce their value with the sort state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    final sorted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: TopicListRow(
            siteUrl: 'https://example.invalid',
            topic: Topic(
              id: 1,
              title: 'Welcome to our community',
              slug: 'welcome',
              lastPosterUsername: 'sam',
              replyCount: 24,
              views: 310,
              bumpedAt: DateTime.now().subtract(const Duration(hours: 3)),
            ),
            showViews: true,
            onSort: sorted.add,
            order: 'views',
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final (key, label) in [
      ('topic-sort-posts', '24 replies, sort by Replies, unsorted'),
      ('topic-sort-views', '310 views, sort by Views, descending'),
      ('topic-sort-activity', '3h, sort by Activity, unsorted'),
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
      final node = tester.getSemantics(find.byKey(ValueKey(key)));
      expect(node.label, label);
      expect(node.flagsCollection.isButton, isTrue);
    }
    // Separators are visual only; the row names the last poster once.
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('topic-card-1')))
          .getSemanticsData()
          .label,
      'Welcome to our community\nLast post by sam',
    );
    await tester.tap(find.byKey(const ValueKey('topic-sort-posts')));
    expect(sorted, ['posts']);
    semantics.dispose();
  });

  for (final (count, replies, views) in [
    (1, '1 reply', '1 view'),
    (2, '2 replies', '2 views'),
  ]) {
    testWidgets('a topic with $replies and $views counts them in agreement', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: TopicListRow(
              siteUrl: 'https://example.invalid',
              topic: Topic(
                id: 1,
                title: 'Welcome to our community',
                slug: 'welcome',
                replyCount: count,
                views: count,
              ),
              showViews: true,
              onSort: (_) {},
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(replies), findsOneWidget);
      expect(find.text(views), findsOneWidget);
    });
  }

  for (final dark in [false, true]) {
    testWidgets('full-width topic states in ${dark ? 'dark' : 'light'}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(680, 580));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final base = dark ? AppTheme.dark : AppTheme.light;
      final titles = [
        'Normal topic',
        'Read topic',
        'Hovered topic',
        'Selected topic',
      ];
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('topic-states'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: base.copyWith(
              platform: TargetPlatform.macOS,
              textTheme: base.textTheme.apply(fontFamily: 'TopicGolden'),
            ),
            home: Scaffold(
              body: Column(
                children: [
                  for (var i = 0; i < titles.length; i++) ...[
                    KeyboardSelection.scope(
                      selected: i == 3,
                      child: TopicListRow(
                        siteUrl: 'https://example.invalid',
                        topic: Topic(
                          id: i,
                          title: titles[i],
                          slug: 'topic-$i',
                          lastReadPostNumber: i == 1 ? 12 : null,
                          highestPostNumber: 12,
                          postsCount: 12,
                          lastPosterUsername: 'sam',
                          tags: const [TopicTag(name: 'design')],
                          excerpt:
                              'A conversation about the details that make a community feel welcoming. Share what has worked for you.',
                        ),
                        onTap: () {},
                      ),
                    ),
                    const DSeparator(),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final normal = tester.widget<TopicTitle>(find.byType(TopicTitle).at(0));
      final read = tester.widget<TopicTitle>(find.byType(TopicTitle).at(1));
      expect(normal.style!.fontWeight, FontWeight.w700);
      expect(read.style!.fontWeight, FontWeight.w500);
      expect(normal.style!.color, isNot(read.style!.color));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(
        location: tester.getCenter(find.text('Hovered topic')),
      );
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const ValueKey('topic-card-2'))).width,
        680,
      );
      expect(
        tester
            .widget<DItem>(find.byKey(const ValueKey('topic-card-3')))
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('topic-states')),
        matchesGoldenFile('goldens/topic-rows-${dark ? 'dark' : 'light'}.png'),
      );
    });
  }
}
