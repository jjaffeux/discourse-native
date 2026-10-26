import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart' show TopicCategory;
import 'package:discourse_native/src/plugins/boards/boards_data.dart';
import 'package:discourse_native/src/plugins/boards/boards_navigation.dart';
import 'package:discourse_native/src/plugins/boards/boards_page.dart';
import 'package:discourse_native/src/shell/app_settings_controller.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/boards_fixture.dart';
import '../../support/native_ui_evidence.dart';

void main() => boardsReaderTests();

void boardsReaderTests({
  bool nativeView = false,
  Future<void> Function(WidgetTester, String)? onCapture,
}) {
  void resize(WidgetTester tester, Size size) {
    if (nativeView) return;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget page(
    BoardsFixture fixture, {
    BoardsRoute route = const BoardsRoute(boardId: 1),
    AppSettingsController? settings,
    double scale = 1,
    bool phone = false,
    double? paneWidth,
  }) {
    Widget body = BoardsPage(
      site: boardsSite,
      route: route,
      controller: fixture.controller,
      navigation: fixture.navigation,
    );
    if (settings != null) {
      body = ContentSettingsScope(
        controller: settings,
        child: DPageContentSettings(
          limitContentSize: settings.limitContentSize,
          child: body,
        ),
      );
    }
    if (paneWidth != null) {
      body = Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: paneWidth, child: body),
      );
    }
    return MaterialApp(
      theme: AppTheme.dark.copyWith(
        platform: phone ? TargetPlatform.android : TargetPlatform.macOS,
      ),
      builder: (context, child) => nativeUiEvidenceBuilder(
        context,
        MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
      home: RepaintBoundary(
        key: const ValueKey('boards-native-capture'),
        child: Scaffold(body: body),
      ),
    );
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await captureNativeUi(tester, name);
    await onCapture?.call(tester, name);
  }

  Future<void> menu(WidgetTester tester, int columnId) async {
    await tester.tap(find.byKey(ValueKey('board-column-menu-$columnId')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'reader presents screenshot-like constraints and activity metadata',
    (tester) async {
      resize(tester, const Size(1500, 900));
      final now = DateTime.now().toUtc().toIso8601String();
      Map<String, dynamic> topic(
        int id,
        int column,
        String title,
        int category,
      ) => {
        'id': id,
        'column_id': column,
        'card_type': 'topic',
        'topic_id': id + 1000,
        'recency_at': now,
        'topic': {
          'id': id + 1000,
          'title': title,
          'category_id': category,
          'tags': ['cs-onboarding', 'customer-success', 'launch-xp'],
          'last_poster': {'username': 'ruben'},
          'all_assigned_users': [
            {'username': 'sam'},
            {'username': 'lee'},
          ],
        },
      };
      final json = boardFixtureJson();
      json['board'] = <String, dynamic>{
        ...boardObject(json['board']),
        'name': 'Customer Success Focus',
        'tag_names': ['cs-onboarding', 'cs-handover', 'cs-renewals-expansion'],
      };
      json['columns'] = [
        {
          'id': 10,
          'title': 'Ice',
          'default_sort': 'recency',
          'cards': [
            {
              'id': 10,
              'column_id': 10,
              'card_type': 'floater',
              'title': 'Old planning task',
              'recency_at': '2020-01-01T00:00:00Z',
            },
          ],
        },
        {
          'id': 11,
          'title': 'CS-Onboarding',
          'tag_name': 'cs-onboarding',
          'cards': [
            topic(
              101,
              11,
              'Launch XP - Automating Launch: Enterprise Category Creation',
              5,
            ),
          ],
        },
        {
          'id': 12,
          'title': 'CS-Handover',
          'cards': [
            topic(201, 12, 'CS Handover: Kijiji (SE)', 5),
            topic(202, 12, 'CS Handover: Roku (SE)', 6),
            topic(203, 12, 'CS Handover: Chaos (SE)', 5),
          ],
        },
        {'id': 13, 'title': 'CS-Ongoing', 'cards': <Object?>[]},
        {
          'id': 14,
          'title': 'CS-Renewals-Expansion',
          'cards': [topic(401, 14, 'Inductive Automation LLC 2026 Renewal', 6)],
        },
        {'id': 15, 'title': 'CS-Ops', 'cards': <Object?>[]},
        {
          'id': 16,
          'title': 'CS-Completed',
          'icon': 'check',
          'cards': <Object?>[],
        },
      ];
      final fixture = BoardsFixture(
        json: json,
        categories: {
          5: const TopicCategory(id: 5, name: 'customer', color: 'b4df20'),
          6: const TopicCategory(id: 6, name: 'overview', color: '12b5d8'),
        },
      );
      addTearDown(fixture.dispose);
      await prepareNativeUiEvidence(tester);
      await tester.pumpWidget(page(fixture));
      await tester.pumpAndSettle();
      expect(find.text('CS-RENEWALS-EXPANSION'), findsOneWidget);
      expect(
        tester
            .getSize(
              find.text(
                'Launch XP - Automating Launch: Enterprise Category Creation',
              ),
            )
            .height,
        greaterThan(30),
      );
      expect(find.text('Show 1 older card'), findsOneWidget);
      expect(find.text('customer-success, launch-xp'), findsWidgets);
      expect(find.textContaining('(ruben)'), findsWidgets);
      expect(find.byType(DAvatarGroup), findsWidgets);
      await capture(tester, 'boards-reader-reference-dark');
      await menu(tester, 11);
      await capture(tester, 'boards-reader-reference-column-menu');
      await tester.tap(find.text('Move left'));
      await tester.pumpAndSettle();
      expect(fixture.columns.first['id'], 11);
      await tester.tap(find.byKey(const ValueKey('board-add-11')));
      await tester.pumpAndSettle();
      await capture(tester, 'boards-reader-reference-add-menu');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'reader ignores content limiting and shrinks short column panels',
    (tester) async {
      resize(tester, const Size(1280, 860));
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettingsController();
      addTearDown(settings.dispose);
      await settings.setLimitContentSize(true);
      final fixture = BoardsFixture(json: boardFixtureJson(extraCards: 20));
      addTearDown(fixture.dispose);
      await prepareNativeUiEvidence(tester);
      await tester.pumpWidget(page(fixture, settings: settings));
      await tester.pumpAndSettle();
      final horizontal = find.byWidgetPredicate(
        (w) => w is DScrollArea && w.axes == DScrollAxes.horizontal,
      );
      final viewport = tester.getSize(find.byType(Scaffold));
      expect(tester.getSize(horizontal).width, viewport.width);
      expect(
        DPageContentSettings.limitOf(tester.element(find.byType(BoardsPage))),
        isTrue,
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('board-title'))).dx,
        lessThan((viewport.width - DPageReadingLane.maxWidth) / 2),
      );
      final long = tester.getRect(
        find.byKey(const ValueKey('board-column-10')),
      );
      final short = tester.getRect(
        find.byKey(const ValueKey('board-column-11')),
      );
      expect(long.left, 12);
      expect(short.height, lessThan(long.height));
      expect(long.bottom, lessThanOrEqualTo(viewport.height));
      final firstList = find.byKey(
        const PageStorageKey('board-column-list-10'),
      );
      final vertical = find.descendant(
        of: firstList,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(vertical).position;
      expect(position.pixels, 0);
      await capture(tester, 'boards-reader-full-width');
      await tester.drag(firstList, const Offset(0, -280));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('phone reader keeps all columns in a horizontal viewport', (
    tester,
  ) async {
    resize(tester, const Size(390, 844));
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(page(fixture, phone: true, paneWidth: 390));
    await tester.pumpAndSettle();
    expect(find.byType(DSelect<int>), findsNothing);
    expect(find.byKey(const ValueKey('board-column-12')), findsOneWidget);
    final horizontal = find.byWidgetPredicate(
      (w) => w is DScrollArea && w.axes == DScrollAxes.horizontal,
    );
    final scroll = find
        .descendant(of: horizontal, matching: find.byType(Scrollable))
        .evaluate()
        .map((element) => (element as StatefulElement).state)
        .whereType<ScrollableState>()
        .firstWhere((state) => state.position.axis == Axis.horizontal);
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    await tester.drag(horizontal, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(0));
    expect(
      tester.getRect(find.byKey(const ValueKey('board-column-12'))).left,
      lessThan(390),
    );
    await capture(tester, 'boards-reader-phone');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'recency columns keep linked older cards and reveal the remainder locally',
    (tester) async {
      resize(tester, const Size(1100, 800));
      final json = boardFixtureJson();
      final column = (json['columns'] as List)[2] as Map;
      column['cards'] = [
        {
          'id': 301,
          'column_id': 12,
          'card_type': 'floater',
          'title': 'Recent work',
          'recency_at': DateTime.now().toUtc().toIso8601String(),
        },
        {
          'id': 302,
          'column_id': 12,
          'card_type': 'floater',
          'title': 'Linked old work',
          'recency_at': '2020-01-01T00:00:00Z',
        },
        {
          'id': 303,
          'column_id': 12,
          'card_type': 'floater',
          'title': 'Other old work',
          'recency_at': '2020-01-01T00:00:00Z',
        },
      ];
      final fixture = BoardsFixture(json: json);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(
        page(fixture, route: const BoardsRoute(boardId: 1, cardId: 302)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recent work'), findsOneWidget);
      expect(find.text('Linked old work'), findsOneWidget);
      expect(find.text('Other old work'), findsNothing);
      expect(find.text('Show 1 older card'), findsOneWidget);
      final reads = fixture.transport.reads.length;
      await tester.tap(find.text('Show 1 older card'));
      await tester.pumpAndSettle();
      expect(find.text('Other old work'), findsOneWidget);
      expect(find.text('Show 1 older card'), findsNothing);
      expect(fixture.transport.reads, hasLength(reads));
      await capture(tester, 'boards-reader-recency');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('linked card moved remotely reveals its new horizontal column', (
    tester,
  ) async {
    resize(tester, const Size(390, 844));
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      page(
        fixture,
        route: const BoardsRoute(boardId: 1, cardId: 102),
        phone: true,
        paneWidth: 390,
      ),
    );
    await tester.pumpAndSettle();
    final from = fixture.columns.first['cards'] as List;
    final card = from.firstWhere((raw) => boardObject(raw)['id'] == 102) as Map;
    from.remove(card);
    card['column_id'] = 12;
    (fixture.columns[2]['cards'] as List).add(card);
    fixture.live.deliver('/boards/1', {});
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.text('Write release notes'));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(390));
    expect(find.text('Show 1 older card'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cards can drop into a column whose older cards are hidden', (
    tester,
  ) async {
    resize(tester, const Size(1100, 800));
    final json = boardFixtureJson();
    ((json['columns'] as List)[2] as Map)['cards'] = [
      {
        'id': 301,
        'column_id': 12,
        'card_type': 'floater',
        'title': 'Old work',
        'recency_at': '2020-01-01T00:00:00Z',
      },
    ];
    final fixture = BoardsFixture(json: json);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(page(fixture));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Write release notes')),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Show 1 older card')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      (fixture.transport.writes.single.body['card'] as Map)['column_id'],
      12,
    );
    expect(find.text('Write release notes'), findsOneWidget);
    expect(find.text('Old work'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  final placeholder = find.byKey(const ValueKey('board-drop-placeholder'));
  final releaseNotes = find.byKey(const ValueKey('board-card-102'));
  final inProgress = find.byKey(const ValueKey('board-column-11'));

  Future<TestGesture> lift(WidgetTester tester, Finder card) async {
    final gesture = await tester.startGesture(
      tester.getCenter(card),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 4));
    await tester.pump();
    return gesture;
  }

  testWidgets('a dragged card leaves a placeholder that follows the pointer', (
    tester,
  ) async {
    resize(tester, const Size(1100, 800));
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(page(fixture));
    await tester.pumpAndSettle();
    final home = tester.getRect(releaseNotes);
    final gesture = await lift(tester, releaseNotes);
    expect(releaseNotes, findsNothing);
    expect(tester.getRect(placeholder).top, home.top);
    expect(tester.getSize(placeholder).height, home.height);
    final noCards = find.descendant(
      of: inProgress,
      matching: find.text('No cards in this column.'),
    );
    expect(noCards, findsOneWidget);
    await gesture.moveTo(tester.getCenter(inProgress));
    await tester.pump();
    expect(find.descendant(of: inProgress, matching: placeholder), findsOne);
    expect(noCards, findsNothing);
    final improve = find.byKey(const ValueKey('board-card-101'));
    await gesture.moveTo(
      tester.getRect(improve).topCenter + const Offset(0, 4),
    );
    await tester.pump();
    expect(
      tester.getRect(placeholder).bottom,
      lessThanOrEqualTo(tester.getRect(improve).top),
    );
    expect(noCards, findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fixture.transport.writes.single.body['card'], {
      'column_id': 10,
      'after_card_id': null,
    });
    expect(placeholder, findsNothing);
    expect(releaseNotes, findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a mouse drag holds the card preview by its corner', (
    tester,
  ) async {
    resize(tester, const Size(1100, 800));
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(page(fixture));
    await tester.pumpAndSettle();
    final gesture = await lift(tester, releaseNotes);
    final pointer = tester.getCenter(inProgress);
    await gesture.moveTo(pointer);
    await tester.pump();
    final preview = find.ancestor(
      of: find.text('Write release notes'),
      matching: find.byType(DCard),
    );
    expect(tester.getRect(preview).topLeft, pointer);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('releasing a card over its own slot writes nothing', (
    tester,
  ) async {
    resize(tester, const Size(1100, 800));
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(page(fixture));
    await tester.pumpAndSettle();
    final gesture = await lift(tester, releaseNotes);
    expect(placeholder, findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fixture.transport.writes, isEmpty);
    expect(placeholder, findsNothing);
    expect(releaseNotes, findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a recency column takes a dragged card at its top', (
    tester,
  ) async {
    resize(tester, const Size(1100, 800));
    final json = boardFixtureJson();
    ((json['columns'] as List)[2] as Map)['cards'] = [
      {
        'id': 301,
        'column_id': 12,
        'card_type': 'floater',
        'title': 'Recent work',
        'recency_at': DateTime.now().toUtc().toIso8601String(),
      },
    ];
    final fixture = BoardsFixture(json: json);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(page(fixture));
    await tester.pumpAndSettle();
    final recent = find.byKey(const ValueKey('board-card-301'));
    final gesture = await lift(tester, releaseNotes);
    await gesture.moveTo(
      tester.getRect(recent).bottomCenter - const Offset(0, 4),
    );
    await tester.pump();
    expect(
      tester.getRect(placeholder).bottom,
      lessThanOrEqualTo(tester.getRect(recent).top),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fixture.transport.writes.single.body['card'], {'column_id': 12});
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a move awaiting review keeps the card hidden at its slot', (
    tester,
  ) async {
    resize(tester, const Size(1100, 800));
    final json = boardFixtureJson();
    (json['board'] as Map)['require_confirmation'] = true;
    final fixture = BoardsFixture(json: json);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(page(fixture));
    await tester.pumpAndSettle();
    final gesture = await lift(tester, releaseNotes);
    await gesture.moveTo(tester.getCenter(inProgress));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Review move'), findsOneWidget);
    expect(find.descendant(of: inProgress, matching: placeholder), findsOne);
    expect(releaseNotes, findsNothing);
    expect(fixture.transport.writes, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Review move'), findsNothing);
    expect(placeholder, findsNothing);
    expect(releaseNotes, findsOneWidget);
    expect(fixture.transport.writes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a board closed while a dropped card is saving settles quietly', (
    tester,
  ) async {
    resize(tester, const Size(1100, 800));
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    const route = 'PUT /boards/api/boards/1/cards/102';
    final save = fixture.transport.responders[route]!;
    final answer = Completer<void>();
    fixture.transport.responders[route] = (request) async {
      await answer.future;
      return save(request);
    };
    await tester.pumpWidget(page(fixture));
    await tester.pumpAndSettle();
    final gesture = await lift(tester, releaseNotes);
    await gesture.moveTo(tester.getCenter(inProgress));
    await tester.pump();
    await gesture.up();
    // The header's busy spinner animates until the write answers.
    await tester.pump();
    await tester.pump();
    expect(
      fixture.transport.writes.map((write) => write.path),
      contains('/boards/api/boards/1/cards/102'),
    );
    expect(find.descendant(of: inProgress, matching: placeholder), findsOne);
    await tester.pumpWidget(const SizedBox.shrink());
    answer.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('column menus preserve management permissions and edge actions', (
    tester,
  ) async {
    resize(tester, const Size(1100, 800));
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(page(fixture));
    await tester.pumpAndSettle();
    await menu(tester, 10);
    final left = tester.widget<DDropdownMenuItem>(
      find.widgetWithText(DDropdownMenuItem, 'Move left'),
    );
    expect(left.onPressed, isNull);
    await capture(tester, 'boards-reader-column-menu');
    await tester.tap(find.text('Move right'));
    await tester.pumpAndSettle();
    expect(fixture.columns.map((column) => column['id']), [11, 10, 12]);
    await menu(tester, 10);
    await tester.tap(find.text('Edit column'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(DInput).first, 'Ready for review');
    await tester.tap(find.widgetWithText(DButton, 'Save'));
    await tester.pumpAndSettle();
    expect(fixture.columns[1]['title'], 'Ready for review');
    expect(find.text('READY FOR REVIEW'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'destructive column confirmation blocks removal and retires private editor text',
    (tester) async {
      resize(tester, const Size(1100, 800));
      final fixture = BoardsFixture(json: boardFixtureJson(extraCards: 5));
      addTearDown(fixture.dispose);
      await tester.pumpWidget(page(fixture));
      await tester.pumpAndSettle();
      await menu(tester, 10);
      await tester.tap(find.text('Clear column'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('also removes the column tag'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(DButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(fixture.transport.writes, isEmpty);
      await menu(tester, 10);
      await tester.tap(find.text('Delete column'));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(DButton, 'Delete column');
      expect(tester.widget<DButton>(confirm).onPressed, isNull);
      await tester.enterText(find.byType(DInput), 'wrong');
      await tester.pumpAndSettle();
      expect(tester.widget<DButton>(confirm).onPressed, isNull);
      await tester.enterText(find.byType(DInput), 'Backlog');
      await tester.pumpAndSettle();
      expect(tester.widget<DButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(fixture.columns.any((column) => column['id'] == 10), isFalse);
      expect(fixture.refreshedTopics, [500]);
      await menu(tester, 11);
      await tester.tap(find.text('Edit column'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(DInput).first,
        'Private retained title',
      );
      fixture.requests.forget(boardsSite);
      fixture.controller.forget(boardsSite);
      await tester.pumpAndSettle();
      expect(find.text('Private retained title'), findsNothing);
      expect(find.widgetWithText(DButton, 'Save'), findsNothing);
      expect(fixture.transport.writes, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('reordering keeps revealed older cards and column scroll', (
    tester,
  ) async {
    resize(tester, const Size(1100, 800));
    final json = boardFixtureJson(sort: 'recency');
    ((json['columns'] as List).first as Map)['cards'] = <Object?>[
      for (var i = 0; i < 40; i++)
        {
          'id': 700 + i,
          'column_id': 10,
          'card_type': 'floater',
          'title': 'Older task $i',
          'recency_at': '2020-01-01T00:00:00Z',
        },
    ];
    final fixture = BoardsFixture(json: json);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(page(fixture));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show 40 older cards'));
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('board-column-10'));
    final list = find.descendant(of: panel, matching: find.byType(Scrollable));
    await tester.drag(list, const Offset(0, -450));
    await tester.pumpAndSettle();
    final before = tester.state<ScrollableState>(list).position.pixels;
    expect(before, greaterThan(0));
    await menu(tester, 10);
    await tester.tap(find.widgetWithText(DDropdownMenuItem, 'Move right'));
    await tester.pumpAndSettle();
    expect(fixture.columns.map((column) => column['id']), [11, 10, 12]);
    expect(find.text('Show 40 older cards'), findsNothing);
    expect(
      tester.state<ScrollableState>(list).position.pixels,
      closeTo(before, 1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'long card titles reserve the menu control and retain card navigation',
    (tester) async {
      resize(tester, const Size(1100, 800));
      const title =
          'Launch XP - Automating Launch: Enterprise Category Creation';
      final json = boardFixtureJson();
      final firstColumn = (json['columns'] as List).first as Map;
      final topic =
          ((firstColumn['cards'] as List).first as Map)['topic'] as Map;
      topic['title'] = title;
      final fixture = BoardsFixture(json: json);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(page(fixture));
      await tester.pumpAndSettle();
      final card = find.ancestor(
        of: find.text(title),
        matching: find.byType(DItem),
      );
      final trigger = find.descendant(
        of: card,
        matching: find.byType(DDropdownMenuTrigger),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(card));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text(title)).right,
        lessThanOrEqualTo(tester.getRect(trigger).left),
      );
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(fixture.host.openedTopic, isNull);
      expect(
        find.widgetWithText(DDropdownMenuItem, 'Move to…'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('read-only and non-manager boards omit management actions', (
    tester,
  ) async {
    final fixture = BoardsFixture(json: boardFixtureJson(canManage: false));
    addTearDown(fixture.dispose);
    await tester.pumpWidget(page(fixture));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-column-menu-10')), findsNothing);
    expect(find.byKey(const ValueKey('board-add-10')), findsOneWidget);
    (fixture.data['board'] as Map)['can_write'] = false;
    fixture.live.deliver('/boards/1', {});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-add-10')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final save in [false, true]) {
    testWidgets(
      'add-topic dialog closes safely after ${save ? 'save' : 'cancel'}',
      (tester) async {
        final fixture = BoardsFixture();
        addTearDown(fixture.dispose);
        await tester.pumpWidget(page(fixture));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('board-add-10')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(DDropdownMenuItem, 'Add topic as card'),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '678');
        await tester.tap(
          find.widgetWithText(DButton, save ? 'Save' : 'Cancel'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Add existing topic'), findsNothing);
        expect(find.text('Product roadmap'), findsOneWidget);
        expect(find.text('Added topic'), save ? findsOneWidget : findsNothing);
        expect(fixture.refreshedTopics, save ? [678] : isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('large text reader and add menu use bounded Native controls', (
    tester,
  ) async {
    resize(tester, const Size(390, 844));
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      page(fixture, scale: 2, phone: true, paneWidth: 390),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('board-add-10')));
    await tester.pumpAndSettle();
    expect(find.text('Add topic as card'), findsOneWidget);
    await capture(tester, 'boards-reader-add-menu-large-text');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
