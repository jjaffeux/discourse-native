import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/keyboard_navigation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _topics = [
  Topic(
    id: 1,
    title: 'Welcome to our community',
    slug: 'welcome',
    pinned: true,
    unreadPosts: 4,
    categoryId: 1,
    excerpt:
        'A place to share ideas and help each other build something great.',
    tags: [
      TopicTag(name: 'design'),
      TopicTag(name: 'mobile'),
      TopicTag(name: 'feedback'),
    ],
    lastPosterUsername: 'sam',
    replyCount: 24,
    likeCount: 19,
    posters: [
      TopicPoster(userId: 1, username: 'dave', description: 'Original poster'),
      TopicPoster(userId: 2, username: 'mia', description: 'Frequent poster'),
      TopicPoster(userId: 3, username: 'chris', description: 'Frequent poster'),
      TopicPoster(
        userId: 4,
        username: 'sam',
        description: 'Most recent poster',
        latest: true,
      ),
    ],
  ),
  Topic(
    id: 2,
    title:
        'What small details would make this community feel more welcoming to new members?',
    slug: 'details',
    categoryId: 1,
    closed: true,
    bookmarked: true,
    excerpt:
        'Share your experiences, suggestions and the details you would love to see improved.',
    tags: [TopicTag(name: 'design')],
    lastPosterUsername: 'alex',
    replyCount: 1,
  ),
  Topic(
    id: 3,
    title: 'Thanks for the update',
    slug: 'thanks',
    highestPostNumber: 12,
    lastReadPostNumber: 12,
    postsCount: 12,
    categoryId: 1,
    lastPosterUsername: 'sam',
    replyCount: 11,
  ),
];

void main() {
  setUpAll(() async {
    await (FontLoader('TopicCardTest')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
        .load();
  });

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    for (final width in [320.0, 390.0, 590.0, 1200.0]) {
      testWidgets('mockup card geometry on $platform at $width', (
        tester,
      ) async {
        await _pump(tester, width: width, platform: platform);
        final card = find.byKey(const ValueKey('topic-card-1'));
        Finder within(Finder finder) =>
            find.descendant(of: card, matching: finder);
        final title = within(find.byType(TopicTitle));
        final excerpt = within(find.text(_topics[0].excerpt!));
        final time = within(find.byKey(const ValueKey('inbox-row-time-1')));
        final posters = within(find.byType(DAvatarGroup));
        final activity = within(
          find.byKey(const ValueKey('topic-card-activity-1')),
        );
        final bounds = tester.getRect(card);
        expect(bounds.left, 16);
        expect(bounds.right, width - 16);
        expect(tester.getTopLeft(title).dy - bounds.top, 12);
        expect(
          tester.getTopLeft(excerpt).dy - tester.getBottomLeft(title).dy,
          5,
        );
        expect(
          tester.getTopLeft(posters).dy - tester.getBottomLeft(excerpt).dy,
          7,
        );
        expect(
          tester.getCenter(time).dy,
          closeTo(tester.getCenter(posters).dy, .01),
        );
        expect(tester.getRect(time).right, width - 16);
        expect(tester.getSize(posters), const Size(59, 20));
        expect(tester.getSize(title).width, lessThanOrEqualTo(760));
        expect(tester.getSize(excerpt).width, lessThanOrEqualTo(760));
        expect(
          tester.getRect(activity).bottom,
          lessThanOrEqualTo(bounds.bottom - 12),
        );
        expect(
          within(find.byType(DBadge)).evaluate().length,
          1,
          reason: 'Only the unread count is a badge.',
        );
        final avatarWidgets = tester
            .widgetList<DAvatar>(within(find.byType(DAvatar)))
            .toList();
        expect(avatarWidgets.where((a) => a.ring).length, 1);
        expect(avatarWidgets.last.ringStyle, DAvatarRingStyle.outside);
        expect(within(find.text('24')), findsOneWidget);
        expect(within(find.text('19')), findsOneWidget);
        expect(within(find.textContaining('Last post by')), findsNothing);
        final status = within(
          find.byKey(const ValueKey('topic-card-status-1')),
        );
        expect(tester.getRect(status).right, width < 811 ? width - 16 : 795);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final width in [390.0, 1200.0]) {
    testWidgets('selection preserves text alignment at $width', (tester) async {
      await _pump(tester, width: width);
      final title = find.text(_topics[1].title);
      final before = tester.getRect(title);
      await _pump(tester, width: width, selected: 2);
      expect(tester.getRect(title).left, before.left);
      expect(tester.getRect(title).size, before.size);
      final card = find.byKey(const ValueKey('topic-card-2'));
      expect(tester.getRect(card).left, 4);
      expect(tester.getRect(card).right, width - 4);
      expect(
        tester.widget<DItem>(card).selectionStyle,
        DItemSelectionStyle.filled,
      );
      expect(find.byType(DSeparator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final direction in TextDirection.values) {
    testWidgets(
      'narrow cards retain links and counts with large text in $direction',
      (tester) async {
        await _pump(tester, width: 280, scale: 2, direction: direction);
        expect(tester.takeException(), isNull);
        expect(find.text('24'), findsOneWidget);
        final title = tester.widget<TopicTitle>(find.byType(TopicTitle).at(1));
        expect(title.maxLines, isNull);
        final activity = find.byKey(const ValueKey('topic-card-activity-2'));
        expect(tester.getRect(activity).left, greaterThanOrEqualTo(16));
        expect(tester.getRect(activity).right, lessThanOrEqualTo(264));
      },
    );
  }

  testWidgets('unread count stays with the final title word', (tester) async {
    await _pump(tester, width: 320);
    final card = find.byKey(const ValueKey('topic-card-1'));
    final tail = find.descendant(of: card, matching: find.text('community'));
    final badge = find.byKey(const ValueKey('inbox-row-unread-1'));
    expect(tester.getCenter(badge).dy, closeTo(tester.getCenter(tail).dy, .01));
    expect(tester.getRect(badge).left - tester.getRect(tail).right, 6);
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets('restricted category keeps counts on one line in $direction', (
      tester,
    ) async {
      for (final (width, scale, styleType, tagCount) in [
        (430.0, 1.25, 'square', 1),
        (390.0, 1.0, 'square', 1),
        (320.0, 1.25, 'square', 1),
        (280.0, 2.0, 'square', 1),
        (390.0, 1.75, 'icon', 12),
        (320.0, 1.25, 'icon', 12),
      ]) {
        await _pump(
          tester,
          width: width,
          scale: scale,
          dark: true,
          direction: direction,
          topics: [
            Topic(
              id: 21,
              title:
                  'Scheduled Topic Timer occasionally fails to move topics to target category',
              excerpt:
                  'Hi team,\nWe’ve been using the Topic Timer to schedule topics for later.',
              slug: 'timer',
              categoryId: 12,
              replyCount: 12,
              likeCount: 3,
              tags: [
                const TopicTag(name: 'in-progress'),
                for (var i = 1; i < tagCount; i++)
                  TopicTag(name: 'long-tag-number-$i'),
              ],
              posters: [
                ..._topics.first.posters,
                const TopicPoster(userId: 5, username: 'fifth'),
              ],
            ),
          ],
          categories: [
            const TopicCategory(id: 11, name: 'Customers', color: 'A787CB'),
            TopicCategory(
              id: 12,
              name: 'HubSpot',
              color: 'FFAACC',
              parentCategoryId: 11,
              readRestricted: true,
              styleType: styleType,
              icon: 'folder',
            ),
          ],
        );
        final category = find.byKey(const ValueKey(('topic-row-category', 12)));
        void expectSingleLine() {
          final y = tester.getCenter(category).dy;
          for (final count in ['12', '3']) {
            expect(
              tester.getCenter(find.text(count)).dy,
              closeTo(y, .01),
              reason: 'Counts must stay beside the category at $width/$scale',
            );
          }
          final activity = tester.getRect(
            find.byKey(const ValueKey('topic-card-activity-21')),
          );
          expect(activity.left, greaterThanOrEqualTo(16));
          expect(activity.right, lessThanOrEqualTo(width - 16));
          expect(tester.takeException(), isNull);
        }

        expectSingleLine();
        if (width == 430 && direction == TextDirection.ltr) {
          await expectLater(
            find.byKey(const ValueKey('mobile-topics')),
            matchesGoldenFile('goldens/topic-card-restricted-taxonomy.png'),
          );
        }
        final overflow = find.byKey(const ValueKey('topic-row-tag-overflow'));
        if (overflow.evaluate().isNotEmpty) {
          await tester.tap(overflow);
          await tester.pumpAndSettle();
          expect(find.text('#in-progress'), findsOneWidget);
          expectSingleLine();
        }
      }
    });
  }

  testWidgets('category links name their category once', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, width: 590);
    final link = tester
        .getSemantics(find.bySemanticsLabel('Category: Community').first)
        .getSemanticsData();
    expect(link.flagsCollection.isLink, isTrue);
    expect(link.tooltip, isEmpty);
    semantics.dispose();
  });

  testWidgets('tag expansion and metadata navigation remain independent', (
    tester,
  ) async {
    final shell = await _pump(tester);
    final card = find.byKey(const ValueKey('topic-card-1'));
    final overflow = find.descendant(
      of: card,
      matching: find.byKey(const ValueKey('topic-row-tag-overflow')),
    );
    expect(overflow, findsOneWidget);
    await tester.tap(overflow);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, isNull);
    expect(
      find.descendant(of: card, matching: find.text('#feedback')),
      findsOneWidget,
    );
    expect(overflow, findsNothing);
    await tester.tap(find.text('#feedback'));
    await tester.pumpAndSettle();
    expect(shell.currentFeedId, contains('feedback'));
    expect(shell.currentContent?.topicId, isNull);
    await tester.tap(find.bySemanticsLabel('Category: Community').first);
    await tester.pumpAndSettle();
    expect(shell.currentFeedId, contains('1'));
    await tester.tap(find.byType(TopicTitle).first);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'muted topic counts and latest-poster semantics follow server state',
    (tester) async {
      const topic = Topic(
        id: 30,
        title: 'Muted conversation',
        slug: 'muted',
        muted: true,
        replyCount: 1500,
        likeCount: 18400,
        pinned: true,
        closed: true,
        bookmarked: true,
        posters: [
          TopicPoster(
            userId: 1,
            username: 'starter',
            description: 'Original poster, most recent poster',
            latest: true,
          ),
          TopicPoster(userId: 2, username: 'frequent'),
        ],
      );
      await _pump(tester, width: 590, topics: [topic]);
      final card = find.byKey(const ValueKey('topic-card-30'));
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: card, matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, .55);
      expect(find.text('1.5k'), findsOneWidget);
      expect(find.text('18k'), findsOneWidget);
      expect(find.byTooltip('Pinned, Closed, Bookmarked'), findsOneWidget);
      final avatars = tester.widgetList<DAvatar>(find.byType(DAvatar)).toList();
      expect(avatars.first.ring, isTrue);
      expect(avatars.last.ring, isFalse);
      expect(
        find.byTooltip('starter — Original poster, most recent poster'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'full category paths collapse and clipped links retain their destinations',
    (tester) async {
      const categories = [
        TopicCategory(id: 10, name: 'Poetry', color: 'A787CB'),
        TopicCategory(
          id: 11,
          name: 'Workshop',
          color: '00AA88',
          parentCategoryId: 10,
        ),
        TopicCategory(
          id: 12,
          name: 'translation-recording-equipment',
          color: '0088CC',
          parentCategoryId: 11,
        ),
      ];
      const topic = Topic(
        id: 20,
        title: 'A taxonomy example',
        slug: 'taxonomy',
        categoryId: 12,
        replyCount: 47,
        likeCount: 19,
        tags: [
          TopicTag(name: 'microphones'),
          TopicTag(name: 'translation-workshop'),
          TopicTag(name: 'haiku'),
        ],
      );
      await _pump(tester, width: 1200, topics: [topic], categories: categories);
      expect(find.text('Poetry'), findsOneWidget);
      expect(find.text('Workshop'), findsOneWidget);
      expect(find.text(categories.last.name), findsOneWidget);

      final shell = await _pump(
        tester,
        width: 390,
        topics: [topic],
        categories: categories,
      );
      expect(find.text('Poetry'), findsNothing);
      expect(find.text('Workshop'), findsNothing);
      final leaf = find.byKey(const ValueKey(('topic-row-category', 12)));
      final label = tester
          .widget<Text>(
            find.descendant(of: leaf, matching: find.byType(Text)).last,
          )
          .data!;
      expect(label, startsWith('trans'));
      expect(label, contains('…'));
      expect(label, endsWith('ment'));
      expect(find.byTooltip(categories.last.name), findsOneWidget);
      await tester.tap(leaf);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.categoryId, 12);
      expect(shell.currentContent?.topicId, isNull);

      var tappedStub = false;
      for (final width in [350.0, 390.0, 430.0, 470.0, 510.0, 550.0]) {
        final shell = await _pump(
          tester,
          width: width,
          topics: [topic],
          categories: categories,
        );
        final stub = find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data?.startsWith('#') ?? false) &&
              (widget.data?.endsWith('…') ?? false),
        );
        if (stub.evaluate().isEmpty) continue;
        final button = find
            .ancestor(of: stub.first, matching: find.byType(DButton))
            .first;
        final fullName = tester
            .widget<DButton>(button)
            .semanticLabel!
            .replaceFirst('Tag: ', '');
        expect(topic.tags.map((tag) => tag.name), contains(fullName));
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(shell.currentContent?.tagName, fullName);
        expect(shell.currentContent?.topicId, isNull);
        tappedStub = true;
        break;
      }
      expect(
        tappedStub,
        isTrue,
        reason: 'At least one width exercises the partial-tag link.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    for (final width in [390.0, 1200.0]) {
      testWidgets('topic mockup in ${dark ? 'dark' : 'light'} at $width', (
        tester,
      ) async {
        await _pump(tester, width: width, selected: 2, dark: dark);
        await expectLater(
          find.byKey(const ValueKey('mobile-topics')),
          matchesGoldenFile(
            'goldens/${width == 390 ? 'mobile' : 'desktop'}-topic-cards-${dark ? 'dark' : 'light'}.png',
          ),
        );
      });
    }
  }
}

Future<ShellController> _pump(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  TargetPlatform platform = TargetPlatform.iOS,
  TextDirection direction = TextDirection.ltr,
  int? selected,
  bool dark = false,
  List<Topic> topics = _topics,
  List<TopicCategory> categories = const [
    TopicCategory(id: 1, name: 'Community', color: 'A787CB'),
  ],
}) async {
  await tester.binding.setSurfaceSize(Size(width, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final site = instance('mobile.example');
  final shell = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: FakeDiscourseApi(
      feeds: {'/latest.json': topics},
      categoryList: categories,
    ),
    authenticator: FakeAuthenticator()..keys[site.url] = 'key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  await shell.loadFeed('latest');
  final base = dark ? AppTheme.dark : AppTheme.light;
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: base.copyWith(
          platform: platform,
          textTheme: base.textTheme.apply(fontFamily: 'TopicCardTest'),
        ),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: direction,
            child: RepaintBoundary(
              key: const ValueKey('mobile-topics'),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < topics.length; i++) ...[
                        KeyboardSelection.scope(
                          selected: topics[i].id == selected,
                          child: TopicListRow(
                            topic: topics[i],
                            siteUrl: site.url,
                          ),
                        ),
                        if (i + 1 < topics.length)
                          TopicListSeparator(
                            besideSelection:
                                topics[i].id == selected ||
                                topics[i + 1].id == selected,
                          ),
                      ],
                    ],
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
  return shell;
}
