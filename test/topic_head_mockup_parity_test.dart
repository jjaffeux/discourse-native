import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/mobile_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_header_tags.dart';
import 'package:discourse_native/src/ui/foundation/control_artwork.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/button_surface.dart';
import 'support/fakes.dart';
import 'support/phone_sheet.dart';
import 'support/shell_test_harness.dart';

// Reference: discourse-native-mockups 847614e, look A. `toolChip`,
// `toolGroup`, `headPathThatFits`, `headTagsThatFit`, `TopicActionsButton`
// and `TopicView`'s head in App.tsx; `--tool-*`, `.topic-head-compact` and
// the card rules under `[data-variant="a"][data-touch]` in app.css.

const _site = 'https://meta.discourse.org';
const _parent = TopicCategory(
  id: 21,
  name: 'Baking',
  slug: 'baking',
  color: 'E5A33A',
);
const _child = TopicCategory(
  id: 22,
  name: 'Starters',
  slug: 'starters',
  color: '3AB54A',
  parentCategoryId: 21,
);
const _tags = [
  TopicTag(id: 1, name: 'starter'),
  TopicTag(id: 2, name: 'fridge'),
  TopicTag(id: 3, name: 'travel'),
  TopicTag(id: 4, name: 'feeding'),
  TopicTag(id: 5, name: 'hydration'),
];
const _platforms = TargetPlatformVariant({
  TargetPlatform.iOS,
  TargetPlatform.android,
});

final _moreTags = find.byKey(const ValueKey('topic-header-more-tags'));
final _actions = find.byKey(const ValueKey('topic-more-actions'));
final _tools = find.byKey(const ValueKey('topic-header-tools'));
final _ownCategory = find.byKey(const ValueKey('topic-header-category'));
final _parentCategory = find.byKey(
  const ValueKey('topic-header-parent-category'),
);

Finder _tag(String name) => find.byKey(ValueKey(('topic-header-tag', name)));

Finder _surface(Finder control) =>
    find.descendant(of: control, matching: find.byType(DControlArtwork)).first;

Future<ShellController> _openTopic(
  WidgetTester tester, {
  Size size = phone,
  List<TopicTag> tags = _tags,
}) async {
  const user = DiscourseUser(id: 7, username: 'reader', staff: true);
  await pumpShell(
    tester,
    size,
    pluginManifest: bundledWidgetTestManifest,
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
          ),
        ],
      },
      topics: {
        7: topicPayload(
          id: 7,
          title: 'Starter care',
          categoryId: 22,
          tags: tags,
          canCreatePost: true,
          canCloseTopic: true,
          canArchiveTopic: true,
          canDeleteTopic: true,
          canToggleTopicVisibility: true,
          canMovePosts: true,
          stream: [for (var i = 1; i <= 30; i++) 70 + i],
          posts: [
            for (var i = 1; i <= 30; i++)
              Post(
                id: 70 + i,
                postNumber: i,
                username: 'mira',
                cooked:
                    '<p>Mine lives in the fridge and gets fed the night '
                    'before.</p><p>The rise is slower than it used to be.</p>',
              ),
          ],
          plugins: pluginRegistry.readTopic({'can_assign': true}, _site),
        ),
      },
    ),
  );
  // The title, clear of the row's category and tag links.
  await tester.tapAt(
    tester.getTopLeft(find.byKey(const ValueKey('topic-card-7'))) +
        const Offset(24, 16),
  );
  await tester.pumpAndSettle();
  return ShellScope.read(tester.element(find.byType(MobileForumRoot)));
}

void main() {
  group('the reference head arithmetic', () {
    double count(int hidden) => 30;

    test('keeps the whole path while it and a count of every tag fit', () {
      final fit = fitTopicHead(
        available: 200,
        path: [60, 60],
        own: 1,
        tags: [70],
        count: count,
      );
      // 60 + 8 + 60 + 8 + 30 + 8 = 174 fits in 200.
      expect(fit.wholePath, isTrue);
      expect(fit.tags, 0);
    });

    test('leaves the own category alone when the path will not fit', () {
      final fit = fitTopicHead(
        available: 160,
        path: [60, 60],
        own: 1,
        tags: [70],
        count: count,
      );
      // 174 > 160: only the second step, 68, and then the tag, 78, fit.
      expect(fit.wholePath, isFalse);
      expect(fit.tags, 1);
    });

    test('shows the tags that fit beside a count of the rest', () {
      final fit = fitTopicHead(
        available: 230,
        path: [60],
        own: 0,
        tags: [50, 50, 50, 50],
        count: count,
      );
      // 68 + 58 + 58 + 38 = 222 fits; a third tag needs 68 + 3 * 58 + 38.
      expect(fit.tags, 2);
    });

    test('a last tag needs no count after it', () {
      final fit = fitTopicHead(
        available: 126,
        path: [60],
        own: 0,
        tags: [50],
        count: count,
      );
      expect(fit.tags, 1);
    });
  });

  testWidgets('a phone topic head is one line: path, tags, count, tools', (
    tester,
  ) async {
    await _openTopic(tester);
    final tools = tester.getRect(_tools);
    final line = tester.getRect(
      find.byKey(const ValueKey('topic-header-taxonomy')),
    );
    // 16 from the card's edges, the tools at the line's end.
    expect(line.left, 16);
    expect(tools.right, 390 - 16);
    final shown = _tags.where((t) => _tag(t.name).evaluate().isNotEmpty);
    expect(
      tester.widget<DButton>(_moreTags).label,
      isA<Text>().having(
        (text) => text.data,
        'label',
        '+${_tags.length - shown.length}',
      ),
    );
    for (final control in [
      _ownCategory,
      for (final tag in shown) _tag(tag.name),
      _moreTags,
      _actions,
    ]) {
      expect(tester.getCenter(control).dy, closeTo(tools.center.dy, .5));
    }
    expect(tester.getRect(_surface(_moreTags)).right, lessThan(tools.left));
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets('a path that will not fit leaves the own category alone', (
    tester,
  ) async {
    await _openTopic(tester, size: const Size(1000, 844));
    // Wide enough for the whole path: the parent is context, unfilled.
    expect(_parentCategory, findsOneWidget);
    expect(_ownCategory, findsOneWidget);
    final parent = buttonSurface(tester, of: _parentCategory);
    expect(parent.color, Colors.transparent);

    tester.view.physicalSize = phone;
    await tester.pumpAndSettle();
    expect(_parentCategory, findsNothing);
    expect(_ownCategory, findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets('the count opens every tag and the run wraps, tools at its end', (
    tester,
  ) async {
    await _openTopic(tester);
    expect(_moreTags, findsOneWidget);
    await tester.tap(_moreTags);
    await tester.pumpAndSettle();
    expect(_moreTags, findsNothing);
    final rects = [for (final tag in _tags) tester.getRect(_tag(tag.name))];
    final lines = {for (final rect in rects) rect.top};
    expect(lines.length, greaterThan(1));
    final tools = tester.getRect(_tools);
    expect(tools.right, 390 - 16);
    expect(tools.top, greaterThanOrEqualTo(rects.last.top));
    // Still the path that fit before: the own category alone.
    expect(_parentCategory, findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets('the head controls are flat pills of a 5% fill', (tester) async {
    await _openTopic(tester);
    final tokens = DTokens.of(tester.element(_actions));
    final scaler = MediaQuery.textScalerOf(tester.element(_actions));
    final fill = tokens.foreground.withValues(alpha: .05);
    // BAND_H and the chips' 12.5px, before the phone's text baseline.
    expect(DControlStyle.height(DControlSize.filter), 30);
    expect(DControlStyle.fontSize(DControlSize.filter), 12.5);
    final height = DControlStyle.scaledHeight(DControlSize.filter, scaler);
    await tester.tap(_moreTags);
    await tester.pumpAndSettle();
    for (final control in [_actions, _tag(_tags.first.name)]) {
      final surface = buttonSurface(tester, of: control);
      expect(surface.color, fill);
      expect(surface.borderColor, Colors.transparent);
      // A pill: the corner is the whole of half the height.
      expect(surface.borderRadius.topLeft.x, greaterThanOrEqualTo(height / 2));
      expect(tester.getSize(_surface(control)).height, height);
    }
    final own = buttonSurface(tester, of: _ownCategory);
    expect(own.borderColor, Colors.transparent);
    expect(own.borderRadius.topLeft.x, greaterThanOrEqualTo(height / 2));

    // Bookmark and bell share one pill, split by the fill at 12%.
    final bookmark = find.byKey(const ValueKey('topic-header-bookmark-button'));
    final bell = find.byKey(const ValueKey('topic-header-notification-button'));
    final group = find.ancestor(
      of: bookmark,
      matching: find.byType(DButtonGroup),
    );
    final pill = find
        .descendant(of: group, matching: find.byType(DecoratedBox))
        .first;
    final decoration = tester.widget<DecoratedBox>(pill).decoration;
    expect(decoration, isA<BoxDecoration>());
    expect((decoration as BoxDecoration).color, fill);
    expect(buttonSurface(tester, of: bookmark).color, Colors.transparent);
    final split = find
        .ancestor(of: bell, matching: find.byType(CustomPaint))
        .first;
    final splitHeight = tester.getSize(split).height;
    expect(
      tester.renderObject(split),
      paints..rect(
        rect: Rect.fromLTWH(0, 1, 1, splitHeight - 2),
        color: tokens.foreground.withValues(alpha: .12),
      ),
    );
    expect(
      tester.getRect(_surface(bookmark)).right,
      tester.getRect(_surface(bell)).left,
    );
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets('a phone gathers assigning, the topic and staff in one sheet', (
    tester,
  ) async {
    await _openTopic(tester);
    expect(find.byKey(const Key('assign-topic-header')), findsNothing);
    expect(find.byKey(const ValueKey('topic-status-button')), findsNothing);
    await tester.tap(_actions);
    await tester.pumpAndSettle();
    final content = tester.widget<DDropdownMenuContent>(
      find.byType(DDropdownMenuContent),
    );
    final order = [
      for (final child in content.children)
        if (child is DDropdownMenuSeparator)
          '|'
        else
          (child.key! as ValueKey<String>).value,
    ];
    expect(order, [
      'assign-topic-action',
      '|',
      'topic-share-action',
      ?(order.contains('topic-flag-button') ? 'topic-flag-button' : null),
      'topic-mark-unread',
      '|',
      'topic-select-posts',
      '|',
      'topic-status-closed',
      'topic-status-archived',
      'topic-status-visible',
      '|',
      'topic-status-delete',
    ]);
    await tester.tap(find.byKey(const Key('assign-topic-action')));
    await tester.pumpAndSettle();
    expectPhoneSheet(tester, title: 'Assign topic');
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets('the page card and the topic sheet are 31 round at their top', (
    tester,
  ) async {
    await _openTopic(tester);
    final card = tester.widget<DPageSurface>(
      find
          .descendant(
            of: find.byKey(const ValueKey('mobile-content-panel')),
            matching: find.byType(DPageSurface),
          )
          .first,
    );
    expect(
      card.borderRadius,
      const BorderRadius.vertical(
        top: Radius.circular(31),
        bottom: Radius.circular(22),
      ),
    );
    final sheet = tester.widget<DPageSurface>(
      find
          .descendant(
            of: find.byType(DSheetContent),
            matching: find.byType(DPageSurface),
          )
          .first,
    );
    expect(
      sheet.borderRadius,
      const BorderRadius.vertical(
        top: Radius.circular(31),
        bottom: Radius.circular(22),
      ),
    );
    expect(find.byKey(const ValueKey('sheet-drag-handle')), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets('the condensed head is a band the card squares under', (
    tester,
  ) async {
    await _openTopic(tester);
    final sheet = find
        .descendant(
          of: find.byType(DSheetContent),
          matching: find.byType(DPageSurface),
        )
        .first;
    Future<void> wheel(double dy) async {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: const Offset(195, 600),
          scrollDelta: Offset(0, dy),
        ),
      );
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
    }

    await wheel(900);
    await wheel(-120);
    final band = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('topic-header-band')),
    );
    expect(
      band.decoration,
      BoxDecoration(
        color: DTokens.of(tester.element(sheet)).wellFill,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(31)),
      ),
    );
    expect(
      tester.widget<DPageSurface>(sheet).borderRadius,
      const BorderRadius.vertical(
        top: Radius.zero,
        bottom: Radius.circular(22),
      ),
    );
    expect(find.byKey(const ValueKey('sheet-drag-handle')), findsNothing);
    expect(tester.widget<DPageSurface>(sheet).depth, isNull);

    // Rounded again, and the grabber back, once the head has gone.
    await wheel(400);
    expect(
      tester.widget<DPageSurface>(sheet).borderRadius,
      const BorderRadius.vertical(
        top: Radius.circular(31),
        bottom: Radius.circular(22),
      ),
    );
    expect(find.byKey(const ValueKey('sheet-drag-handle')), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _platforms);
}
