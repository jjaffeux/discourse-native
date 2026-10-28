import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/boards/boards_data.dart';
import 'package:discourse_native/src/plugins/boards/boards_directory.dart';
import 'package:discourse_native/src/plugins/boards/boards_navigation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../mobile_shell_test.dart' show pumpMobileShellFixture;
import '../../support/boards_fixture.dart';
import '../../support/fakes.dart';

final _sheet = find.byType(DSheetContent);
final _dock = find.byKey(const ValueKey('mobile-bottom-bar'));
final _title = find.byKey(const ValueKey('board-title'));
final _dots = find.byType(DCarouselDot);
Finder _dot(int index) => find.byKey(ValueKey('board-column-dot-$index'));
Finder _column(int id) => find.byKey(ValueKey('board-column-$id'));
final _columnScrollbar = find.ancestor(
  of: find.byKey(const ValueKey('board-column-10')),
  matching: find.byWidgetPredicate(
    (widget) => widget is DScrollBar && widget.axis == Axis.horizontal,
  ),
);

Future<ShellController> _openBoard(
  WidgetTester tester, {
  String name = 'Product roadmap',
  List<String> tags = const ['roadmap'],
  Size size = const Size(390, 844),
  int extraCards = 30,
  bool fromDirectory = true,
  double homeIndicator = 34,
  List<Map<String, Object?>> doneCards = const [],
  void Function(FakeDiscourseApi api)? onApi,
  FakeForumTabStore? forumTabs,
}) async {
  tester.view.padding = FakeViewPadding(top: 44, bottom: homeIndicator);
  tester.view.viewPadding = FakeViewPadding(top: 44, bottom: homeIndicator);
  final board = boardFixtureJson(extraCards: extraCards);
  (board['board'] as Map)
    ..['name'] = name
    ..['tag_names'] = tags;
  ((board['columns'] as List).last as Map)['cards'] = doneCards;
  final shell = await pumpMobileShellFixture(
    tester,
    size: size,
    board: board,
    pluginResponses: {
      'PUT /boards/api/boards/1/cards/102': {
        'card': {'id': 102},
      },
    },
    onApi: onApi,
    forumTabs: forumTabs,
  );
  if (!fromDirectory) {
    shell.pushContent(
      ContentRoute(
        destination: const ExtensionDestination('boards/1'),
        title: name,
        icon: boardsIcon,
      ),
    );
    await tester.pumpAndSettle();
    return shell;
  }
  shell.pushContent(
    const ContentRoute(
      destination: ExtensionDestination('boards'),
      title: 'Boards',
      icon: boardsIcon,
    ),
  );
  await tester.pumpAndSettle();
  expect(_sheet, findsNothing);
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
  expect(shell.currentContent?.id, 'boards/1');
  return shell;
}

void main() {
  const platforms = TargetPlatformVariant({
    TargetPlatform.iOS,
    TargetPlatform.android,
  });

  for (final (label, distance, scrollBoard) in [
    ('at the top', 0.0, false),
    ('partway through a row', 333.0, false),
    ('deep in the list', 1800.0, false),
    ('after scrolling the board', 333.0, true),
  ]) {
    testWidgets('dismissing a board pill sheet preserves topics $label', (
      tester,
    ) async {
      final shell = await pumpMobileShellFixture(
        tester,
        board: boardFixtureJson(extraCards: 30),
        topics: [
          for (var id = 1; id <= 50; id++)
            Topic(
              id: id,
              title: id.isEven
                  ? 'Topic $id with a longer title that wraps onto another line'
                  : 'Topic $id',
              slug: 'topic-$id',
              plugins: PluginData.none.withValue(
                boardsMembershipKey,
                const BoardMemberships([
                  BoardMembership(
                    1,
                    'Product roadmap',
                    'roadmap',
                    101,
                    'Backlog',
                  ),
                ]),
              ),
            ),
        ],
      );
      if (distance > 0) {
        await tester.timedDrag(
          find.byType(TopicListView),
          Offset(0, -distance),
          const Duration(seconds: 1),
        );
        await tester.pumpAndSettle();
      }
      final pill = find.text('Product roadmap · Backlog').hitTestable().first;
      final visibleTitle = find
          .textContaining(RegExp(r'^Topic \d+'))
          .hitTestable()
          .first;
      final title = find.text(tester.widget<Text>(visibleTitle).data!);
      final before = tester.getTopLeft(title).dy;
      await tester.tap(pill);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.id, 'boards/1/cards/101');
      if (scrollBoard) {
        final column = find.byKey(const PageStorageKey('board-column-list-10'));
        await tester.timedDrag(
          column,
          const Offset(0, -250),
          const Duration(seconds: 1),
        );
        await tester.pumpAndSettle();
        final position = tester
            .state<ScrollableState>(
              find.descendant(of: column, matching: find.byType(Scrollable)),
            )
            .position;
        final scrolled = position.pixels;
        expect(scrolled, greaterThan(0));
        await tester.timedDrag(
          column,
          const Offset(0, 100),
          const Duration(seconds: 1),
        );
        await tester.pumpAndSettle();
        expect(position.pixels, lessThan(scrolled));
      }
      await tester.dragFrom(
        tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
        const Offset(0, 300),
      );
      // Check the first revealed frame as well as the settled page.
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (_sheet.evaluate().isEmpty) {
          expect(tester.getTopLeft(title).dy, closeTo(before, 0.1));
        }
      }
      expect(_sheet, findsNothing);
      expect(shell.currentContent?.isTopicList, isTrue);
      expect(tester.takeException(), isNull);
    }, variant: platforms);
  }

  testWidgets('a board opens from the directory as a page sheet', (
    tester,
  ) async {
    final shell = await _openBoard(tester);
    expect(shell.currentContent?.id, 'boards/1');
    expect(tester.widget<DSheetContent>(_sheet).variant, DSheetVariant.page);
    expect(find.descendant(of: _sheet, matching: _title), findsOneWidget);
    final pull = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
    );
    await pull.moveBy(const Offset(0, 20));
    await pull.moveBy(const Offset(0, 220));
    await pull.up();
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'boards');
    expect(_sheet, findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('the fixed page header dismisses a board sheet', (tester) async {
    final shell = await _openBoard(tester);
    final header = find.byKey(const ValueKey('mobile-header'));
    final headerDrag = find
        .ancestor(of: header, matching: find.byType(DSheetDragRegion))
        .first;
    await tester.drag(headerDrag, const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'boards');
    expect(_sheet, findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('going back from a board shows the directory already loaded', (
    tester,
  ) async {
    final shell = await _openBoard(tester);
    shell.handleBack();
    await tester.pump();
    expect(shell.currentContent?.id, 'boards');
    expect(find.byType(DSpinner), findsNothing);
    expect(find.text('Product roadmap'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('a restored board reveals the directory while pulled down', (
    tester,
  ) async {
    final forumTabs = FakeForumTabStore();
    await _openBoard(tester, forumTabs: forumTabs);
    final shell = await pumpMobileShellFixture(
      tester,
      board: boardFixtureJson(),
      forumTabs: forumTabs,
      key: UniqueKey(),
    );
    expect(shell.currentContent?.id, 'boards/1');
    final pull = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
    );
    await pull.moveBy(const Offset(0, 20));
    await pull.moveBy(const Offset(0, 220));
    await tester.pump();
    final directory = find.byType(BoardsDirectory);
    expect(directory, findsOneWidget);
    expect(
      find.descendant(of: directory, matching: find.text('Product roadmap')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(directory).dy,
      lessThan(tester.getTopLeft(_sheet).dy),
    );
    await pull.up();
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'boards');
    expect(_sheet, findsNothing);
    expect(find.text('Product roadmap'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  for (final target in ['board-title', 'board-card-101']) {
    testWidgets(
      'pulling board content at $target dismisses without refreshing',
      (tester) async {
        late FakeDiscourseApi api;
        final shell = await _openBoard(tester, onApi: (value) => api = value);
        final before = api.pluginReadPaths
            .where((path) => path == '/boards/api/boards/1.json')
            .length;
        await tester.dragFrom(
          tester.getCenter(find.byKey(ValueKey(target))),
          const Offset(0, 300),
        );
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, 'boards');
        expect(_sheet, findsNothing);
        expect(
          api.pluginReadPaths
              .where((path) => path == '/boards/api/boards/1.json')
              .length,
          before,
        );
        expect(tester.takeException(), isNull);
      },
      variant: platforms,
    );
  }

  testWidgets('message bus updates an open board sheet', (tester) async {
    late FakeDiscourseApi api;
    final shell = await _openBoard(tester, onApi: (value) => api = value);
    final response = api.pluginResponses['GET /boards/api/boards/1.json']!;
    (response['board'] as Map)['name'] = 'Updated roadmap';
    final column = (response['columns'] as List).first as Map;
    final card = (column['cards'] as List).first as Map;
    (card['topic'] as Map)['title'] = 'Updated search plan';
    final tracker = FakeSiteTracker.built.singleWhere(
      (tracker) => tracker.siteUrl == shell.currentInstance?.url,
    );
    tracker.deliverPluginMessage('/boards/1', {'type': 'board_updated'});
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'boards/1');
    expect(_sheet, findsOneWidget);
    expect(find.text('Updated roadmap'), findsOneWidget);
    expect(find.text('Updated search plan'), findsOneWidget);
    expect(find.text('Improve search'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('reopening a board shows it at once and refreshes it', (
    tester,
  ) async {
    late FakeDiscourseApi api;
    final shell = await _openBoard(tester, onApi: (value) => api = value);
    final readsBefore = api.pluginReadPaths
        .where((path) => path == '/boards/api/boards/1.json')
        .length;
    expect(find.text('Improve search'), findsOneWidget);
    shell.handleBack();
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'boards');
    await tester.tap(find.text('Product roadmap'));
    await tester.pump();
    expect(shell.currentContent?.id, 'boards/1');
    expect(find.text('Improve search'), findsOneWidget);
    expect(find.byType(DSpinner), findsNothing);
    await tester.pumpAndSettle();
    expect(
      api.pluginReadPaths
          .where((path) => path == '/boards/api/boards/1.json')
          .length,
      readsBefore + 1,
    );
    expect(find.text('Improve search'), findsOneWidget);
    expect(find.byType(DSpinner), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('a board reappears as it was left when its card topic closes', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
    final board = boardFixtureJson();
    final columns = (board['columns'] as List).cast<Map<String, dynamic>>();
    final card = (columns.first['cards'] as List).removeAt(0) as Map;
    card
      ..['topic_id'] = 7
      ..['column_id'] = 11;
    (card['topic'] as Map)['id'] = 7;
    (columns[1]['cards'] as List).add(card);
    final shell = await pumpMobileShellFixture(tester, board: board);
    shell.pushContent(
      const ContentRoute(
        destination: ExtensionDestination('boards/1'),
        title: 'Product roadmap',
        icon: boardsIcon,
      ),
    );
    await tester.pumpAndSettle();
    double left() =>
        tester.getRect(_column(11)).left - tester.getRect(_sheet).left;
    await tester.fling(_column(10), const Offset(-120, 0), 1000);
    await tester.pumpAndSettle();
    final leftBefore = left();
    await tester.tap(find.byKey(const ValueKey('board-card-101')));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.isTopic, isTrue);
    final pull = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
    );
    await pull.moveBy(const Offset(0, 20));
    await pull.moveBy(const Offset(0, 220));
    await pull.up();
    // The sheet returns to the board inside an animation frame, so the frame
    // that ends this loop is the first one that builds the board again.
    for (var frame = 0; shell.currentContent?.isTopic ?? false; frame++) {
      expect(frame, lessThan(120));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(shell.currentContent?.id, 'boards/1');
    expect(tester.widget<Text>(_title).data, 'Product roadmap');
    expect(find.byKey(const ValueKey('board-card-101')), findsOneWidget);
    expect(left(), leftBefore);
    await tester.pumpAndSettle();
    expect(left(), leftBefore);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets(
    'pulling a board down after the app resumes shows the directory',
    (tester) async {
      final shell = await _openBoard(tester);
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      final pull = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
      );
      await pull.moveBy(const Offset(0, 20));
      await pull.moveBy(const Offset(0, 220));
      await tester.pump();
      final directory = find.byKey(const PageStorageKey('boards-directory'));
      expect(
        tester.getRect(directory).top,
        lessThan(tester.getRect(_sheet).top),
      );
      await pull.up();
      await tester.pumpAndSettle();
      expect(shell.currentContent?.id, 'boards');
      expect(tester.takeException(), isNull);
    },
    variant: platforms,
  );

  testWidgets('the sheet header keeps tags beside the title', (tester) async {
    await _openBoard(tester, name: 'Board');
    expect(find.byKey(const ValueKey('board-back')), findsNothing);
    final title = tester.getRect(_title);
    final tag = tester.getRect(find.text('# roadmap'));
    expect(tag.left, greaterThan(title.right));
    expect(tag.center.dy, inInclusiveRange(title.top, title.bottom));
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('the sheet header wraps tags below a long title', (tester) async {
    await _openBoard(
      tester,
      name: 'Quarterly product roadmap for the native apps',
      tags: ['roadmap', 'native'],
    );
    final title = tester.getRect(_title);
    final roadmap = tester.getRect(find.text('# roadmap'));
    final native = tester.getRect(find.text('# native'));
    expect(roadmap.top, greaterThanOrEqualTo(title.bottom));
    expect(native.center.dy, roadmap.center.dy);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('a column fills the sheet and hints at the next one', (
    tester,
  ) async {
    await _openBoard(tester);
    final sheet = tester.getRect(_sheet);
    final first = tester.getRect(find.byKey(const ValueKey('board-column-10')));
    final next = tester.getRect(find.byKey(const ValueKey('board-column-11')));
    expect(first.left - sheet.left, 12);
    expect(next.left - first.right, 12);
    // The first column has one neighbour, so it shows both slivers of it.
    expect(sheet.right - next.left, 20);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('a phone swipe settles on one column at a time', (tester) async {
    await _openBoard(tester);
    final sheet = tester.getRect(_sheet);
    Finder column(int id) => find.byKey(ValueKey('board-column-$id'));
    double left(int id) => tester.getRect(column(id)).left - sheet.left;
    double right(int id) => sheet.right - tester.getRect(column(id)).right;
    await tester.fling(column(10), const Offset(-120, 0), 1000);
    await tester.pumpAndSettle();
    // A middle column shows 10 points of each neighbour beyond the padding.
    expect(left(11), 12 + 10);
    expect(tester.getRect(column(10)).right - sheet.left, 10);
    expect(sheet.right - tester.getRect(column(12)).left, 10);
    // The last column rests against the trailing padding, showing the same
    // sliver of its predecessor that the first column shows of its successor.
    await tester.fling(column(11), const Offset(-200, 0), 8000);
    await tester.pumpAndSettle();
    expect(right(12), 12);
    expect(left(12), 12 + 20);
    final hold = await tester.startGesture(tester.getCenter(column(12)));
    for (var step = 0; step < 10; step++) {
      await hold.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await hold.up();
    await tester.pumpAndSettle();
    expect(right(12), 12);
    await tester.fling(column(12), const Offset(120, 0), 1000);
    await tester.pumpAndSettle();
    expect(left(11), 12 + 10);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  for (final (device, size) in [
    ('phone', const Size(390, 844)),
    ('tablet', const Size(820, 1180)),
  ]) {
    testWidgets('a $device sheet scrolls columns without a scrollbar', (
      tester,
    ) async {
      await _openBoard(tester, size: size);
      expect(tester.widget<DScrollBar>(_columnScrollbar).showScrollbar, false);
      expect(tester.takeException(), isNull);
    }, variant: platforms);
  }

  testWidgets('a tablet sheet keeps several fixed-width columns in view', (
    tester,
  ) async {
    await _openBoard(tester, size: const Size(820, 1180));
    expect(_dots, findsNothing);
    final column = find.byKey(const ValueKey('board-column-10'));
    final first = tester.getRect(column);
    final next = tester.getRect(find.byKey(const ValueKey('board-column-11')));
    expect(first.width, 300);
    expect(next.right, lessThan(tester.getRect(_sheet).right));
    await tester.timedDrag(
      column,
      const Offset(-100, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(column).left,
      inExclusiveRange(first.left - 312 + 20, first.left - 20),
    );
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('a board hides the dock that the directory shows', (
    tester,
  ) async {
    final shell = await _openBoard(tester);
    expect(_dock, findsNothing);
    shell.handleBack();
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'boards');
    expect(_dock, findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  for (final homeIndicator in [34.0, 0.0]) {
    testWidgets(
      'column dots rest ${homeIndicator.round()} points above the bottom '
      'under short and long columns',
      (tester) async {
        for (final extraCards in [0, 30]) {
          await _openBoard(
            tester,
            extraCards: extraCards,
            homeIndicator: homeIndicator,
          );
          final dots = tester.getRect(_dots.first);
          expect(_dots, findsNWidgets(3));
          expect(
            dots.bottom,
            tester.getRect(_sheet).bottom - homeIndicator - DSpacing.sm,
          );
          expect(
            tester.getRect(_column(10)).bottom,
            extraCards == 0
                ? lessThan(dots.top - DSpacing.md)
                : dots.top - DSpacing.md,
          );
        }
        expect(tester.takeException(), isNull);
      },
      variant: platforms,
    );
  }

  testWidgets('column dots follow swipes and scroll to a tapped column', (
    tester,
  ) async {
    await _openBoard(tester);
    final sheet = tester.getRect(_sheet);
    List<bool> selected() => [
      for (var index = 0; index < 3; index++)
        tester.widget<DCarouselDot>(_dot(index)).selected,
    ];
    expect(selected(), [true, false, false]);
    await tester.fling(_column(10), const Offset(-120, 0), 1000);
    await tester.pumpAndSettle();
    expect(selected(), [false, true, false]);
    await tester.tap(_dot(2));
    await tester.pumpAndSettle();
    expect(sheet.right - tester.getRect(_column(12)).right, 12);
    expect(selected(), [false, false, true]);
    await tester.tap(_dot(0));
    await tester.pumpAndSettle();
    expect(tester.getRect(_column(10)).left - sheet.left, 12);
    expect(selected(), [true, false, false]);
    await tester.tap(_dot(1));
    await tester.pumpAndSettle();
    expect(tester.getRect(_column(11)).left - sheet.left, 12 + 10);
    expect(selected(), [false, true, false]);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('rotating a phone keeps the older cards a column shows', (
    tester,
  ) async {
    await _openBoard(
      tester,
      doneCards: [
        {
          'id': 300,
          'column_id': 12,
          'card_type': 'floater',
          'title': 'Shipped last year',
          'recency_at': '2025-01-01T00:00:00Z',
        },
      ],
    );
    final older = find.text('Shipped last year');
    await tester.tap(_dot(2));
    await tester.pumpAndSettle();
    expect(older, findsNothing);
    await tester.tap(find.text('Show 1 older card'));
    await tester.pumpAndSettle();
    expect(older, findsOneWidget);
    for (final size in [const Size(844, 390), const Size(390, 844)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(_dots, size.width < 600 ? findsNWidgets(3) : findsNothing);
      await tester.ensureVisible(_column(12));
      await tester.pumpAndSettle();
      expect(older, findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('column dots stay above a minimized composer', (tester) async {
    final shell = await _openBoard(tester);
    unawaited(shell.openNewTopicFromSidebar());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('composer-topic-title')),
      'Draft from a board',
    );
    await tester.dragFrom(
      tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle')).last),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'boards/1');
    final restore = tester.getRect(
      find.byKey(const ValueKey('composer-restore')),
    );
    expect(tester.getRect(_dots.first).bottom, lessThan(restore.top));
    expect(
      tester.getRect(find.byKey(const ValueKey('board-add-10'))).bottom,
      lessThan(restore.top),
    );
    expect(_dot(1).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('board columns scroll to their last card above the dots', (
    tester,
  ) async {
    await _openBoard(tester);
    final dots = tester.getRect(_dots.first);
    final add = find.byKey(const ValueKey('board-add-10'));
    expect(tester.getRect(add).bottom, lessThanOrEqualTo(dots.top));
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const PageStorageKey('board-column-list-10')),
      ),
    );
    for (var step = 0; step < 80; step++) {
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    final last = find.ancestor(
      of: find.text('Task 30'),
      matching: find.byType(DItem),
    );
    expect(tester.getRect(_dots.first), dots);
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(dots.top));
    expect(tester.getRect(add).bottom, lessThanOrEqualTo(dots.top));
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  // Touch drags start after a hold; the first move after it carries the card.
  Future<TestGesture> lift(WidgetTester tester, Finder card) async {
    final gesture = await tester.startGesture(tester.getCenter(card));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0, 4));
    await tester.pump();
    expect(card, findsNothing);
    return gesture;
  }

  // Each 20 point auto-scroll step spans three 16 ms test frames.
  Future<void> hold(WidgetTester tester, {int frames = 200}) async {
    for (var frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('holding a dragged card at the right edge scrolls the board on', (
    tester,
  ) async {
    late FakeDiscourseApi api;
    await _openBoard(tester, extraCards: 0, onApi: (value) => api = value);
    final sheet = tester.getRect(_sheet);
    Finder column(int id) => find.byKey(ValueKey('board-column-$id'));
    final backlog = tester.getRect(column(10));
    final gesture = await lift(
      tester,
      find.byKey(const ValueKey('board-card-102')),
    );
    // Inside the edge zone, and inside the last column once it rests against
    // the trailing padding.
    final edge = Offset(sheet.right - 20, backlog.center.dy);
    await gesture.moveTo(edge);
    await hold(tester);
    expect(tester.getRect(column(10)).right, lessThan(sheet.left));
    final under = [
      11,
      12,
    ].firstWhere((id) => tester.getRect(column(id)).contains(edge));
    await gesture.up();
    await tester.pumpAndSettle();
    final write = api.pluginWrites.single;
    expect(write.path, '/boards/api/boards/1/cards/102');
    expect((write.body['card'] as Map)['column_id'], under);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('holding a dragged card near the bottom of a column scrolls it', (
    tester,
  ) async {
    late FakeDiscourseApi api;
    await _openBoard(tester, onApi: (value) => api = value);
    final list = find.byKey(const PageStorageKey('board-column-list-10'));
    final bounds = tester.getRect(list);
    final ids = [101, 102, for (var i = 0; i < 30; i++) 200 + i];
    final shownAtStart = {
      for (final id in ids)
        if (find.byKey(ValueKey('board-card-$id')).evaluate().isNotEmpty &&
            tester.getRect(find.byKey(ValueKey('board-card-$id'))).bottom <=
                bounds.bottom)
          id,
    };
    expect(shownAtStart, hasLength(lessThan(ids.length)));
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position;
    final gesture = await lift(
      tester,
      find.byKey(const ValueKey('board-card-102')),
    );
    await gesture.moveTo(Offset(bounds.center.dx, bounds.bottom - 8));
    await hold(tester);
    expect(position.pixels, greaterThan(0));
    await gesture.up();
    await tester.pumpAndSettle();
    final card = api.pluginWrites.single.body['card'] as Map;
    expect(card['column_id'], 10);
    expect(card['after_card_id'], isA<int>());
    expect(shownAtStart, isNot(contains(card['after_card_id'])));
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('a dragged card rides centred under the finger', (tester) async {
    await _openBoard(tester, extraCards: 0);
    final gesture = await lift(
      tester,
      find.byKey(const ValueKey('board-card-102')),
    );
    final finger = tester.getCenter(_column(10));
    await gesture.moveTo(finger);
    await tester.pump();
    final preview = find.ancestor(
      of: find.text('Write release notes'),
      matching: find.byType(DCard),
    );
    expect(tester.getRect(preview).center, offsetMoreOrLessEquals(finger));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('a board that fits keeps its header still', (tester) async {
    await _openBoard(tester);
    final title = tester.getRect(_title);
    await tester.drag(_title, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getRect(_title), title);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  for (final (size, scale) in [
    (const Size(320, 700), 1.0),
    (const Size(320, 700), 2.0),
    (const Size(390, 844), 1.5),
    (const Size(390, 844), 2.0),
    (const Size(844, 390), 1.0),
    (const Size(844, 390), 2.0),
  ]) {
    testWidgets(
      'a ${size.width.round()}x${size.height.round()} board at ${scale}x text '
      'reaches every column footer',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _openBoard(
          tester,
          size: size,
          name: 'Quarterly product roadmap for the native apps',
          tags: ['roadmap', 'native', 'ios', 'android'],
          extraCards: 3,
          fromDirectory: false,
        );
        expect(tester.takeException(), isNull);
        final sheet = tester.getRect(_sheet);
        await tester.dragFrom(
          tester.getTopLeft(_title) + const Offset(20, 10),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        for (final id in [10, 11]) {
          final add = find.byKey(ValueKey('board-add-$id'));
          await tester.ensureVisible(add);
          await tester.pumpAndSettle();
          final bounds = tester.getRect(add);
          expect(bounds.top, greaterThanOrEqualTo(sheet.top));
          expect(bounds.bottom, lessThanOrEqualTo(sheet.bottom - 34));
          if (_dots.evaluate().isNotEmpty) {
            expect(
              tester.getRect(_dots.first).bottom,
              lessThanOrEqualTo(sheet.bottom - 34),
            );
          }
        }
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({TargetPlatform.iOS}),
    );
  }
}
