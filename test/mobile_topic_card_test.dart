import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/keyboard_navigation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final width in [320.0, 390.0, 590.0]) {
      testWidgets('mockup spacing on $platform at $width', (tester) async {
        await _pump(tester, width: width, platform: platform);
        final card = find.byKey(const ValueKey('topic-card-1'));
        Finder within(Finder finder) =>
            find.descendant(of: card, matching: finder);
        final title = within(find.byType(TopicTitle));
        final excerpt = within(find.text(_topics[0].excerpt!));
        final tag = within(
          find.byWidgetPredicate(
            (w) => w is DBadge && w.size == DBadgeSize.tag,
          ),
        ).first;
        final time = within(find.byKey(const ValueKey('inbox-row-time-1')));
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
        expect(tester.getTopLeft(tag).dy - tester.getBottomLeft(excerpt).dy, 7);
        expect(
          bounds.bottom -
              [
                tester.getBottomLeft(activity).dy,
                tester.getBottomLeft(tag).dy,
              ].reduce((a, b) => a > b ? a : b),
          12,
        );
        expect(tester.getRect(time).top, tester.getRect(title).top);
        expect(tester.getRect(time).right, width - 16);
        expect(tester.getSize(time).height, lessThan(24));
        expect(tester.getSize(tag).height, lessThan(24));
        expect(within(find.text('feedback')), findsOneWidget);
        expect(
          within(find.byKey(const ValueKey('topic-row-tag-overflow'))),
          findsNothing,
        );
        expect(
          within(find.byKey(const ValueKey('topic-sort-activity'))),
          findsNothing,
        );
        expect(find.text('Pinned'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'activity shares the footer when it fits and wraps when it does not',
    (tester) async {
      for (final width in [320.0, 590.0]) {
        await _pump(tester, width: width);
        final card = find.byKey(const ValueKey('topic-card-1'));
        final tag = find.descendant(of: card, matching: find.text('feedback'));
        final activity = find.byKey(const ValueKey('topic-card-activity-1'));
        if (width == 590) {
          expect(
            tester.getCenter(activity).dy,
            closeTo(tester.getCenter(tag).dy, .01),
          );
          expect(tester.getRect(activity).right, width - 16);
        } else {
          expect(
            tester.getRect(activity).top,
            greaterThan(tester.getRect(tag).bottom),
          );
          expect(tester.getRect(activity).left, 16);
        }
      }
    },
  );

  testWidgets('selecting a mobile row keeps its text in place', (tester) async {
    await _pump(tester);
    final title = find.text(_topics[1].title);
    final before = tester.getRect(title);
    await _pump(tester, selected: 2);
    expect(tester.getRect(title).left, before.left);
    expect(tester.getRect(title).width, before.width);
    expect(tester.getRect(title).height, before.height);
    final card = find.byKey(const ValueKey('topic-card-2'));
    expect(tester.getRect(card).left, 4);
    expect(tester.getRect(card).right, 386);
    expect(
      tester.widget<DItem>(card).selectionStyle,
      DItemSelectionStyle.filled,
    );
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets('narrow mobile rows grow with large text in $direction', (
      tester,
    ) async {
      await _pump(tester, width: 280, scale: 2, direction: direction);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('1 reply'), findsOneWidget);
      final title = tester.widget<TopicTitle>(find.byType(TopicTitle).at(1));
      expect(title.maxLines, isNull);
      final activity = find.byKey(const ValueKey('topic-card-activity-2'));
      expect(tester.getRect(activity).left, greaterThanOrEqualTo(16));
      expect(tester.getRect(activity).right, lessThanOrEqualTo(264));
    });
  }

  testWidgets(
    'wrapped title lines return to the card edge after status icons',
    (tester) async {
      await _pump(tester, width: 320);
      final title = find.byType(TopicTitle).at(1);
      final paragraphFinder = find
          .descendant(of: title, matching: find.byType(RichText))
          .first;
      final paragraph = tester.renderObject<RenderParagraph>(paragraphFinder);
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: _topics[1].title.length),
      );
      final laterLines = boxes.where(
        (box) => box.top >= 20 && box.right - box.left > 25,
      );
      expect(laterLines.length, greaterThanOrEqualTo(2));
      for (final line in laterLines) {
        expect(paragraph.localToGlobal(Offset(line.left, line.top)).dx, 16);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('metadata links activate independently of the topic row', (
    tester,
  ) async {
    final shell = await _pump(tester);
    await tester.tap(find.text('design').first);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, isNull);
    expect(shell.currentFeedId, contains('design'));
    await tester.tap(find.text('Community').first);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, isNull);
    expect(shell.currentFeedId, contains('1'));
    await tester.tap(find.text(_topics.first.title));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, 1);
  });

  for (final dark in [false, true]) {
    testWidgets('mobile topic mockup in ${dark ? 'dark' : 'light'}', (
      tester,
    ) async {
      await _pump(tester, selected: 2, dark: dark);
      await expectLater(
        find.byKey(const ValueKey('mobile-topics')),
        matchesGoldenFile(
          'goldens/mobile-topic-cards-${dark ? 'dark' : 'light'}.png',
        ),
      );
    });
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
}) async {
  await tester.binding.setSurfaceSize(Size(width, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final site = instance('mobile.example');
  final shell = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: FakeDiscourseApi(
      feeds: {'/latest.json': _topics},
      categoryList: const [
        TopicCategory(id: 1, name: 'Community', color: 'A787CB'),
      ],
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
                      for (var i = 0; i < _topics.length; i++) ...[
                        KeyboardSelection.scope(
                          selected: _topics[i].id == selected,
                          child: TopicListRow(
                            topic: _topics[i],
                            siteUrl: site.url,
                          ),
                        ),
                        if (i + 1 < _topics.length)
                          TopicListSeparator(
                            besideSelection:
                                _topics[i].id == selected ||
                                _topics[i + 1].id == selected,
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
