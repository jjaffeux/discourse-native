import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_compact_head.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

// Reference: discourse-native-mockups 13db54c, `TopicView`'s head in App.tsx,
// and `barTagsThatFit`.

const _site = 'https://meta.discourse.org';
const _parent = TopicCategory(
  id: 21,
  name: 'Bake',
  slug: 'baking',
  color: 'E5A33A',
);
const _child = TopicCategory(
  id: 22,
  name: 'Rise',
  slug: 'starters',
  color: '3AB54A',
  parentCategoryId: 21,
);
const _tags = [TopicTag(id: 1, name: 'a'), TopicTag(id: 2, name: 'b')];
const _desktopOnly = TargetPlatformVariant({TargetPlatform.macOS});

final _full = find.byKey(const ValueKey('topic-content-header'));
final _compact = find.byKey(const ValueKey('topic-compact-head'));
final _compactTitle = find.byKey(const ValueKey('topic-compact-title'));
final _metadata = find.byKey(const ValueKey('topic-compact-metadata'));
final _tools = find.byKey(const ValueKey('topic-header-tools'));
final _viewport = find.descendant(
  of: find.byType(TopicView),
  matching: find.byType(CustomScrollView),
);

ScrollController _scroll(WidgetTester tester) =>
    tester.widget<CustomScrollView>(_viewport).controller!;

Future<void> _openTopic(
  WidgetTester tester, {
  Size size = desktop,
  List<TopicTag> tags = _tags,
  bool closed = false,
  int? lastRead,
}) async {
  const user = DiscourseUser(id: 7, username: 'reader');
  await pumpShell(
    tester,
    size,
    instances: [
      instance('meta.discourse.org', title: 'Meta').copyWith(user: user),
    ],
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    api: FakeDiscourseApi(
      user: user,
      categoryList: const [_parent, _child],
      feeds: {
        '/latest.json': [
          Topic(
            id: 7,
            title: 'Starter care',
            slug: 'starter-care',
            categoryId: 22,
            tags: tags,
            lastReadPostNumber: lastRead,
            highestPostNumber: lastRead == null ? 0 : 40,
          ),
        ],
      },
      topics: {
        7: topicPayload(
          id: 7,
          title: 'Starter care',
          categoryId: 22,
          tags: tags,
          closed: closed,
          stream: [for (var i = 1; i <= 40; i++) 70 + i],
          posts: [
            for (var i = 1; i <= 40; i++)
              Post(
                id: 70 + i,
                postNumber: i,
                username: 'mira',
                cooked:
                    '<p>Mine lives in the fridge and gets fed the night '
                    'before.</p><p>The rise is slower than it used to be.</p>',
              ),
          ],
        ),
      },
    ),
  );
  await tester.tap(topicListTitle('Starter care'));
  await tester.pumpAndSettle();
}

Future<void> _wheel(WidgetTester tester, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(_viewport),
      scrollDelta: Offset(0, delta),
    ),
  );
  await tester.pumpAndSettle();
  // The layout change waits out a head that had already left.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  group('topicCompactTagsThatFit', () {
    double eachLetterSix(String text) => text.length * 6.0;

    test('names every tag while the line has room', () {
      expect(
        topicCompactTagsThatFit(
          width: 400,
          path: const ['Baking'],
          tags: const ['starter', 'fridge'],
          measure: eachLetterSix,
        ),
        2,
      );
    });

    test('counts each piece with its gap and leaves room for the count', () {
      // Baking: 9 mark + 6 + 36 name + 6 = 57. #starter: 48 + 6 = 54, and
      // with one tag still to come, +1: 12 + 6 = 18. 57 + 54 + 18 = 129.
      const path = ['Baking'];
      const tags = ['starter', 'fridge'];
      expect(
        topicCompactTagsThatFit(
          width: 129,
          path: path,
          tags: tags,
          measure: eachLetterSix,
        ),
        1,
      );
      expect(
        topicCompactTagsThatFit(
          width: 128,
          path: path,
          tags: tags,
          measure: eachLetterSix,
        ),
        0,
      );
    });

    test('pays for the caret between path steps', () {
      // Baking 57, then 6 caret + 6 + 9 + 6 + 48 Starters + 6 = 81: 138.
      expect(
        topicCompactTagsThatFit(
          width: 138 + 42 - 1,
          path: const ['Baking', 'Starters'],
          tags: const ['ferment'],
          measure: eachLetterSix,
        ),
        0,
      );
      expect(
        topicCompactTagsThatFit(
          width: 138 + 54,
          path: const ['Baking', 'Starters'],
          tags: const ['ferment'],
          measure: eachLetterSix,
        ),
        1,
      );
    });

    test('names every tag before the line has been measured', () {
      expect(
        topicCompactTagsThatFit(
          width: 0,
          path: const ['Baking'],
          tags: const ['starter', 'fridge'],
          measure: eachLetterSix,
        ),
        2,
      );
    });
  });

  testWidgets(
    'scrolling under the head changes it to the compact layout and back',
    (tester) async {
      await _openTopic(tester, closed: true);
      expect(_full, findsOneWidget);
      expect(_compact, findsNothing);
      expect(
        find.byKey(const ValueKey('topic-header-taxonomy')),
        findsOneWidget,
      );

      await _wheel(tester, 900);
      await _wheel(tester, -300);
      expect(_compactTitle.hitTestable(), findsOneWidget);
      expect(_full, findsNothing);
      expect(find.byKey(const ValueKey('topic-header-taxonomy')), findsNothing);

      final title = tester.widget<TopicTitle>(_compactTitle);
      expect(title.title, 'Starter care');
      expect(title.maxLines, 1);
      expect(title.style!.fontSize, 14);
      expect(title.style!.fontWeight, FontWeight.w700);

      final head = tester.getRect(_compact);
      expect(tester.getTopLeft(_compactTitle).dy, closeTo(head.top + 10, 1));
      expect(tester.getTopLeft(_compactTitle).dx, closeTo(head.left + 16, 1));

      final line = tester.widget<Text>(
        find.descendant(of: _metadata, matching: find.byType(Text)).first,
      );
      expect(line.style!.fontSize, 11);
      expect(
        find.descendant(
          of: _metadata,
          matching: find.textContaining('#a', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _metadata,
          matching: find.textContaining('Bake', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(_metadata).dy -
            tester.getBottomLeft(_compactTitle).dy,
        closeTo(3, 1),
      );

      expect(tester.getRect(_tools).right, closeTo(head.right - 16, 1));
      expect(tester.getCenter(_tools).dy, closeTo(head.center.dy, 1));
      expect(
        tester.getRect(_compactTitle).right,
        lessThanOrEqualTo(tester.getRect(_tools).left),
      );

      final mark = tester.widget<DIcon>(
        find.descendant(of: _compact, matching: find.byType(DIcon)).first,
      );
      expect(mark.size, 11);
      expect(mark.semanticLabel, 'Closed');

      _scroll(tester).jumpTo(0);
      await tester.pumpAndSettle();
      expect(_compact, findsNothing);
      expect(_full, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: _desktopOnly,
  );

  testWidgets('the title and tools travel from where the full head had them', (
    tester,
  ) async {
    await _openTopic(tester);
    await _wheel(tester, 4);
    final fullTitle = tester.getTopLeft(
      find.byKey(const ValueKey('topic-header-compact-title')),
    );
    final fullTools = tester.getTopLeft(_tools);
    final fullMeta = tester.getTopLeft(
      find.byKey(const ValueKey('topic-header-taxonomy')),
    );

    _scroll(tester).jumpTo(600);
    await tester.pump();
    await tester.pump();
    expect(_compact, findsOneWidget);
    final firstTitle = tester.getRect(_compactTitle);
    final firstTools = tester.getTopLeft(_tools);
    final firstMeta = tester.getTopLeft(_metadata);

    await tester.pumpAndSettle();
    final restTitle = tester.getRect(_compactTitle);
    expect(firstTitle.left, closeTo(fullTitle.dx, 1));
    expect(firstTitle.top, closeTo(fullTitle.dy, 1));
    expect(firstTitle.width / restTitle.width, closeTo(22 / 14, .02));
    expect(firstTitle.height / restTitle.height, closeTo(22 / 14, .02));
    expect(firstTools.dx, closeTo(fullTools.dx, 1));
    expect(firstTools.dy, closeTo(fullTools.dy, 1));
    expect(firstMeta.dx, closeTo(fullMeta.dx, 1));
    expect(firstMeta.dy, closeTo(fullMeta.dy, 1));
    expect(tester.getTopLeft(_metadata).dy, lessThan(firstMeta.dy));
    expect(tester.takeException(), isNull);
  }, variant: _desktopOnly);

  testWidgets('a resumed topic changes on the reader\'s first scroll', (
    tester,
  ) async {
    await _openTopic(tester, lastRead: 12);
    expect(_full, findsOneWidget);
    expect(_compact, findsNothing);

    await _wheel(tester, 4);
    expect(_compact, findsOneWidget);
    expect(_full, findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: _desktopOnly);

  testWidgets('tags past the line wait behind a count naming them', (
    tester,
  ) async {
    final many = [
      for (var i = 0; i < 30; i++) TopicTag(id: i + 1, name: 't$i'),
    ];
    await _openTopic(tester, tags: many);
    await _wheel(tester, 900);
    await _wheel(tester, -300);

    final more = find.byKey(const ValueKey('topic-compact-more-tags'));
    final count = tester.widget<Text>(
      find.descendant(of: more, matching: find.byType(Text)),
    );
    final hidden = int.parse(count.data!.substring(1));
    expect(hidden, greaterThan(0));
    expect(tester.widget<DTooltip>(more).message, endsWith('t29'));
    expect(
      tester.getRect(more).right,
      lessThanOrEqualTo(tester.getRect(_tools).left),
    );
    expect(tester.takeException(), isNull);
  }, variant: _desktopOnly);

  testWidgets('a phone keeps its one head', (tester) async {
    const user = DiscourseUser(id: 7, username: 'reader');
    await pumpShell(
      tester,
      phone,
      instances: [
        instance('meta.discourse.org', title: 'Meta').copyWith(user: user),
      ],
      authenticator: FakeAuthenticator()..keys[_site] = 'key',
      api: FakeDiscourseApi(
        user: user,
        categoryList: const [_parent, _child],
        feeds: {
          '/latest.json': [
            const Topic(
              id: 7,
              title: 'Starter care',
              slug: 'starter-care',
              categoryId: 22,
            ),
          ],
        },
        topics: {
          7: topicPayload(
            id: 7,
            title: 'Starter care',
            categoryId: 22,
            stream: [for (var i = 1; i <= 40; i++) 70 + i],
            posts: [
              for (var i = 1; i <= 40; i++)
                Post(
                  id: 70 + i,
                  postNumber: i,
                  username: 'mira',
                  cooked: '<p>${List.filled(40, 'Fed nightly.').join(' ')}</p>',
                ),
            ],
          ),
        },
      ),
    );
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const ValueKey('topic-card-7'))) +
          const Offset(24, 16),
    );
    await tester.pumpAndSettle();

    final morph = find.byKey(const ValueKey('topic-header-morph'));
    expect(tester.widget<DHeaderMorph>(morph).compact, isFalse);
    await tester.drag(_viewport, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(_compact, findsNothing);
    expect(tester.widget<DHeaderMorph>(morph).compact, isFalse);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
}
