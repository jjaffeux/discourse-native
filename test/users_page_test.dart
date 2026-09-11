import 'dart:async';
import 'dart:collection';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/user_directory_column_width_store.dart';
import 'package:discourse_native/src/models/json.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/shell/user_directory_controller.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _likes = UserDirectoryColumn(
  id: 1,
  name: 'likes_received',
  type: UserDirectoryColumnType.automatic,
  position: 1,
);
const _replies = UserDirectoryColumn(
  id: 2,
  name: 'post_count',
  type: UserDirectoryColumnType.automatic,
  position: 2,
);
const _days = UserDirectoryColumn(
  id: 3,
  name: 'days_visited',
  type: UserDirectoryColumnType.automatic,
  position: 3,
);
const _timeRead = UserDirectoryColumn(
  id: 4,
  name: 'time_read',
  type: UserDirectoryColumnType.automatic,
  position: 4,
);
const _solutions = UserDirectoryColumn(
  id: 9,
  name: 'solutions',
  type: UserDirectoryColumnType.plugin,
  position: 4,
  enabled: false,
);
const _sam = UserDirectoryItem(
  id: 1,
  user: UserDirectoryUser(
    id: 1,
    username: 'sam',
    name: 'Sam Saffron',
    primaryGroupName: 'staff',
  ),
  values: {'likes_received': 290, 'post_count': 121, 'days_visited': 7},
);
const _hawk = UserDirectoryItem(
  id: 2,
  user: UserDirectoryUser(id: 2, username: 'hawk', name: 'Hawk'),
  values: {'likes_received': 167, 'post_count': 52, 'days_visited': 7},
);

void main() {
  testWidgets('metric bars scale with loaded values and update with new rows', (
    tester,
  ) async {
    var items = <UserDirectoryItem>[_sam, _hawk];
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return UsersPage(
            siteUrl: 'https://example.com',
            data: UsersPageData(
              items: items,
              columns: const [_likes],
              loaded: true,
            ),
          );
        },
      ),
    );
    DChartBar bar(String username) => tester.widget<DChartBar>(
      find.descendant(of: _metrics(username), matching: find.byType(DChartBar)),
    );
    expect(bar('sam').fraction, 1);
    expect(bar('hawk').fraction, closeTo(167 / 290, 0.001));
    expect(find.text('290'), findsOneWidget);
    final rowHeight = tester.getSize(_metrics('sam')).height;
    update(
      () => items = [
        ...items,
        const UserDirectoryItem(
          id: 3,
          user: UserDirectoryUser(id: 3, username: 'new'),
          values: {'likes_received': 580},
        ),
        const UserDirectoryItem(
          id: 4,
          user: UserDirectoryUser(id: 4, username: 'zero'),
          values: {'likes_received': 0},
        ),
      ],
    );
    await tester.pump();
    expect(bar('sam').fraction, 0.5);
    expect(bar('new').fraction, 1);
    expect(
      find.descendant(of: _metrics('zero'), matching: find.byType(DChartBar)),
      findsNothing,
    );
    expect(tester.getSize(_metrics('sam')).height, rowHeight);
    expect(tester.takeException(), isNull);
  });

  for (final value in <Object>[
    'NaN',
    'Infinity',
    '-Infinity',
    '1e999',
    double.nan,
    double.infinity,
    double.negativeInfinity,
    '123'.padLeft(maximumJsonIntegerCodeUnits + 1, '0'),
    'not a number with all its original text',
  ]) {
    testWidgets(
      'invalid directory ${value is String ? 'text' : 'number'} $value renders as plain text',
      (tester) async {
        const columns = [_timeRead, _likes, _solutions];
        await _pump(
          tester,
          UsersPage(
            siteUrl: 'https://example.com',
            data: UsersPageData(
              items: [
                for (final (index, (username, metric)) in [
                  ('invalid', value),
                  ('half', '60'),
                  ('full', 120),
                ].indexed)
                  UserDirectoryItem.fromWire({
                    'user': {'id': index + 1, 'username': username},
                    for (final column in columns) column.name: metric,
                  }, 'https://example.com'),
              ],
              columns: columns,
              loaded: true,
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('$value'), findsNWidgets(columns.length));
        for (final text in tester.widgetList<Text>(find.text('$value'))) {
          expect(text.style, isNull);
        }
      },
    );
  }

  for (final value in <Object>[
    9223372036855,
    '9223372036855',
    -9223372036855,
    '-9223372036855',
    9223372036854775807,
    -9223372036854775808,
    1e300,
    '1e300',
  ]) {
    testWidgets(
      'oversized directory time ${value is String ? 'text' : 'number'} $value renders without overflow',
      (tester) async {
        await _pump(
          tester,
          UsersPage(
            siteUrl: 'https://example.com',
            data: UsersPageData(
              items: [
                UserDirectoryItem.fromWire({
                  'user': const {'id': 1, 'username': 'sam'},
                  'time_read': value,
                }, 'https://example.com'),
              ],
              columns: const [_timeRead],
              loaded: true,
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        final texts = tester.widgetList<Text>(
          find.descendant(
            of: _metrics('sam'),
            matching: find.byType(Text),
            matchRoot: true,
          ),
        );
        expect(texts.map((text) => text.data), ['$value']);
      },
    );
  }

  testWidgets('directory keeps normal time and compact number formatting', (
    tester,
  ) async {
    final bounded = '120'.padLeft(maximumJsonIntegerCodeUnits, '0');
    final rows = <(Object?, Object?, Object?)>[
      (0, 0, null),
      (59.9, 12.5, 'words'),
      ('3599.9', '1200', ['one', 'two']),
      ('3661', '1250000', []),
      (-61, '-1250', '3.5'),
      (9223372036854, bounded, '1e300'),
      (bounded, '1e3', '1.0'),
    ];
    await _pump(
      tester,
      UsersPage(
        siteUrl: 'https://example.com',
        data: UsersPageData(
          items: [
            for (final (index, (time, likes, solutions)) in rows.indexed)
              UserDirectoryItem.fromWire({
                'user': {'id': index + 1, 'username': 'user$index'},
                'time_read': time,
                'likes_received': likes,
                'solutions': solutions,
              }, 'https://example.com'),
          ],
          columns: const [_timeRead, _likes, _solutions],
          loaded: true,
        ),
      ),
      size: const Size(1100, 900),
    );

    const expectedRows = [
      ['0m', '0', '—'],
      ['0m', '13', 'words'],
      ['59m', '1.2k', 'one · two'],
      ['1h 1m', '1.3m', '—'],
      ['-1m', '-1.3k', '3.5'],
      ['2562047788h 0m', '120', '1e+294m'],
      ['2m', '1k', '1'],
    ];
    for (final (index, expected) in expectedRows.indexed) {
      final texts = tester.widgetList<Text>(
        find.descendant(
          of: _metrics('user$index'),
          matchRoot: true,
          matching: find.byType(Text),
        ),
      );
      expect(texts.map((text) => text.data), expected);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('hover does not reread directory metrics', (tester) async {
    final items = _countedItems();
    await _pump(
      tester,
      UsersPage(
        siteUrl: 'https://example.com',
        data: UsersPageData(
          items: items,
          columns: _countedColumns,
          loaded: true,
        ),
      ),
    );
    for (final item in items) {
      (item.values as _CountingValues).reads = 0;
    }
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    addTearDown(mouse.removePointer);
    for (var index = 0; index < 5; index++) {
      await mouse.moveTo(
        tester.getCenter(find.byKey(ValueKey('user-row-user$index'))),
      );
      await tester.pumpAndSettle();
    }
    expect(
      items.fold<int>(
        0,
        (total, item) => total + (item.values as _CountingValues).reads,
      ),
      0,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('directory virtualizes rows and scrolls identity with metrics', (
    tester,
  ) async {
    await _pump(
      tester,
      UsersPage(
        siteUrl: 'https://example.com',
        data: UsersPageData(
          items: _countedItems(),
          columns: _countedColumns,
          loaded: true,
        ),
      ),
      size: const Size(700, 700),
    );
    expect(find.byType(DDataTable<UserDirectoryItem>), findsOneWidget);
    expect(find.byKey(const ValueKey('user-row-user999')), findsNothing);
    final list = tester.widget<ListView>(find.byType(ListView));
    list.controller!.jumpTo(1200);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-row-user0')), findsNothing);
    final horizontal = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byType(DDataTable<UserDirectoryItem>),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      ),
    );
    final visible = find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith('user-row-'),
        )
        .first;
    final before = tester.getTopLeft(visible);
    horizontal.controller!.jumpTo(100);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(visible), before - const Offset(100, 0));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'directory supports search, periods, sorting, columns, and omits selection',
    (tester) async {
      String? search;
      String? group;
      UserDirectoryPeriod? period;
      (String, bool)? sort;
      var refreshes = 0;

      await _pump(
        tester,
        UsersPage(
          siteUrl: 'https://example.com',
          data: UsersPageData(
            items: const [_sam, _hawk],
            columns: const [_likes, _replies, _days],
            groupNames: const ['design', 'staff'],
            currentUsername: 'SAM',
            totalRows: 87,
            lastUpdatedAt: DateTime.utc(2026, 9, 4, 7, 6),
            loaded: true,
            hasMore: true,
          ),
          onSearchChanged: (value) => search = value,
          onGroupChanged: (value) => group = value,
          onPeriodChanged: (value) => period = value,
          onSortChanged: (order, ascending) => sort = (order, ascending),
          onRefresh: () async => refreshes++,
        ),
        size: const Size(1100, 820),
      );

      expect(find.text('Community signal'), findsNothing);
      expect(find.text('87 results'), findsNothing);
      expect(find.byKey(const ValueKey('users-sort')), findsNothing);
      expect(find.byKey(const ValueKey('users-sort-direction')), findsNothing);
      expect(find.byKey(const ValueKey('users-load-more')), findsNothing);
      expect(
        find.byKey(const ValueKey('users-directory-progress')),
        findsNothing,
      );
      final pageRect = tester.getRect(find.byKey(const ValueKey('users-page')));
      final tableRect = tester.getRect(
        find.byKey(const ValueKey('users-table')),
      );
      expect(pageRect, const Rect.fromLTWH(0, 0, 1100, 820));
      expect(tableRect.left, 16);
      expect(tableRect.right, 1084);
      expect(tableRect.bottom, 804);

      expect(find.byType(DDataTableFilterField), findsOneWidget);
      expect(
        find.byType(DDataTableColumnToggle<UserDirectoryItem>),
        findsOneWidget,
      );
      expect(find.byType(DAvatar), findsNWidgets(2));
      final identity = find.byKey(const ValueKey('user-row-sam'));
      final avatar = find.descendant(
        of: identity,
        matching: find.byType(DAvatar),
      );
      expect(avatar, findsOneWidget);
      expect(tester.widget<DAvatar>(avatar).decorative, isTrue);
      expect(tester.getSize(avatar), const Size.square(24));
      expect(
        find.descendant(of: identity, matching: find.text('sam')),
        findsOneWidget,
      );
      expect(find.byType(DChartBar), findsNWidgets(6));
      expect(find.text('You'), findsNothing);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Sam Saffron'), findsOneWidget);
      expect(find.byKey(const ValueKey('user-row-sam')), findsOneWidget);
      expect(find.byKey(const ValueKey('users-select-all')), findsNothing);
      expect(find.byKey(const ValueKey('user-select-sam')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('users-table')),
          matching: find.byType(DCheckbox),
        ),
        findsNothing,
      );
      expect(find.text('1'), findsNothing);
      expect(find.text('2'), findsNothing);
      expect(find.text('290'), findsOneWidget);
      expect(find.text('121'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('users-search')),
        '  saffron  ',
      );
      await tester.pump(const Duration(milliseconds: 351));
      expect(search, 'saffron');

      await tester.tap(find.byKey(const ValueKey('users-period-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();
      expect(period, UserDirectoryPeriod.monthly);
      final groupInput = find.descendant(
        of: find.byKey(const ValueKey('users-group-filter')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(groupInput, 'des');
      await tester.pumpAndSettle();
      expect(find.text('staff'), findsNothing);
      await tester.tap(find.text('design'));
      await tester.pumpAndSettle();
      expect(group, 'design');

      expect(find.text('Likes received'), findsOneWidget);
      await tester.tap(find.text('Likes received'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sort ascending'));
      await tester.pumpAndSettle();
      expect(sort, ('likes_received', true));

      await tester.tap(find.byKey(const ValueKey('users-columns')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(DDropdownMenuCheckboxItem, 'Replies posted'),
      );
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.text('Replies posted'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('users-refresh')));
      await tester.pump();
      expect(refreshes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('refreshing rows preserves in-progress search text', (
    tester,
  ) async {
    var items = const [_sam];
    final searches = <String>[];
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return UsersPage(
            siteUrl: 'https://example.com',
            data: UsersPageData(
              items: items,
              columns: const [_likes],
              loaded: true,
            ),
            onSearchChanged: searches.add,
          );
        },
      ),
    );
    final search = find.byKey(const ValueKey('users-search'));
    await tester.enterText(search, 'saff');
    await tester.pump(const Duration(milliseconds: 100));
    update(() => items = const [_sam, _hawk]);
    await tester.pump();
    expect(tester.widget<DDataTableFilterField>(search).value, 'saff');
    await tester.pump(const Duration(milliseconds: 300));
    expect(searches, ['saff']);
    expect(tester.takeException(), isNull);
  });

  for (final changesAccount in [false, true]) {
    testWidgets(
      'pending search stays with its ${changesAccount ? 'account' : 'forum'}',
      (tester) async {
        var site = 'https://example.com';
        var username = 'reader';
        var query = const UserDirectoryQuery();
        final searches = <String>[];
        late StateSetter update;
        await _pump(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return UsersPage(
                siteUrl: site,
                data: UsersPageData(
                  items: const [_sam],
                  columns: const [_likes],
                  loaded: true,
                  currentUsername: username,
                  query: query,
                ),
                onSearchChanged: searches.add,
              );
            },
          ),
        );
        final search = find.byKey(const ValueKey('users-search'));
        await tester.enterText(search, 'unfinished');
        await tester.pump(const Duration(milliseconds: 100));
        update(() {
          if (changesAccount) {
            username = 'replacement';
          } else {
            site = 'https://another.example';
          }
          query = const UserDirectoryQuery(search: 'restored');
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(searches, isEmpty);
        expect(tester.widget<DDataTableFilterField>(search).value, 'restored');
        await tester.enterText(search, 'new search');
        await tester.pump(const Duration(milliseconds: 350));
        expect(searches, ['new search']);
      },
    );
  }

  testWidgets('switching forums permits the new directory to load more', (
    tester,
  ) async {
    var site = 'https://example.com';
    final loads = <String>[];
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return UsersPage(
            siteUrl: site,
            data: const UsersPageData(
              items: [_sam],
              columns: [_likes],
              loaded: true,
              hasMore: true,
            ),
            onLoadMore: () => loads.add(site),
          );
        },
      ),
    );
    expect(loads, ['https://example.com']);
    update(() => site = 'https://another.example');
    await tester.pump();
    expect(loads, ['https://example.com', 'https://another.example']);
  });

  for (final dialogOpen in [false, true]) {
    testWidgets(
      'column visibility resets for a new forum with menu ${dialogOpen ? 'open' : 'closed'}',
      (tester) async {
        var site = 'https://example.com';
        late StateSetter update;
        await _pump(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return UsersPage(
                siteUrl: site,
                data: const UsersPageData(
                  items: [_sam],
                  columns: [_likes, _replies],
                  loaded: true,
                ),
              );
            },
          ),
        );
        await tester.tap(find.byKey(const ValueKey('users-columns')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(DDropdownMenuCheckboxItem, 'Replies posted'),
        );
        if (!dialogOpen) {
          await tester.tapAt(const Offset(2, 2));
          await tester.pumpAndSettle();
          expect(find.text('Replies posted'), findsNothing);
        }

        update(() => site = 'https://another.example');
        await tester.pump();
        if (dialogOpen) {
          await tester.tapAt(const Offset(2, 2));
          await tester.pumpAndSettle();
        }
        expect(find.text('Likes received'), findsOneWidget);
        expect(find.text('Replies posted'), findsOneWidget);
      },
    );
  }

  testWidgets('every column resizes and restores its forum-specific width', (
    tester,
  ) async {
    final persistence = _ColumnWidthMemoryPersistence();
    final store = UserDirectoryColumnWidthStore(persistence: persistence);

    UsersPage page(String siteUrl) => UsersPage(
      siteUrl: siteUrl,
      columnWidthStore: store,
      data: const UsersPageData(
        items: [_sam, _hawk],
        columns: [_likes, _replies, _days],
        loaded: true,
      ),
    );

    await _pump(
      tester,
      page('https://example.com'),
      size: const Size(1100, 820),
    );
    await tester.pumpAndSettle();

    expect(_resize('User'), findsOneWidget);
    for (final column in const [_likes, _replies, _days]) {
      expect(_resize(column.label), findsOneWidget);
    }

    final identityColumn = _resize('User');
    final firstMetric = _resize('Likes received');
    final initialIdentityWidth = tester
        .widget<DResizableHandle>(identityColumn)
        .value;

    await _resizeBy(tester, 'User', 42);
    await tester.pumpAndSettle();
    final resizedIdentityWidth = tester
        .widget<DResizableHandle>(identityColumn)
        .value;
    expect(resizedIdentityWidth, closeTo(initialIdentityWidth + 42, .01));

    await tester.drag(_resize('Likes received'), const Offset(-1000, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<DResizableHandle>(firstMetric).value, 88);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _pump(
      tester,
      page('https://example.com'),
      size: const Size(1100, 820),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<DResizableHandle>(identityColumn).value,
      resizedIdentityWidth,
    );
    expect(tester.widget<DResizableHandle>(firstMetric).value, 88);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _pump(
      tester,
      page('https://another.example'),
      size: const Size(1100, 820),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<DResizableHandle>(identityColumn).value,
      initialIdentityWidth,
    );
    expect(tester.widget<DResizableHandle>(firstMetric).value, greaterThan(88));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a resize wins over a delayed width restoration', (tester) async {
    final persistence = _DelayedColumnWidthPersistence(
      UserDirectoryColumnWidths(const {
        'identity': 420,
        'metric.automatic.1': 200,
      }).encode(),
    );
    final store = UserDirectoryColumnWidthStore(persistence: persistence);
    await _pump(
      tester,
      UsersPage(
        siteUrl: 'https://example.com',
        columnWidthStore: store,
        data: const UsersPageData(
          items: [_sam, _hawk],
          columns: [_likes, _replies, _days],
          loaded: true,
        ),
      ),
      size: const Size(1100, 820),
    );

    final identityColumn = _resize('User');
    final initialWidth = tester.widget<DResizableHandle>(identityColumn).value;
    await _resizeBy(tester, 'User', 32);
    await tester.pumpAndSettle();
    final resizedWidth = tester.widget<DResizableHandle>(identityColumn).value;
    expect(resizedWidth, initialWidth + 32);

    persistence.completeRead();
    await tester.pumpAndSettle();

    expect(tester.widget<DResizableHandle>(identityColumn).value, resizedWidth);
    expect(
      tester.widget<DResizableHandle>(_resize('Likes received')).value,
      200,
    );
    expect(UserDirectoryColumnWidths.decode(persistence.writes.last).widths, {
      'identity': resizedWidth,
      'metric.automatic.1': 200,
    });
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    testWidgets('directory controls retain full targets on $platform', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        UsersPage(
          siteUrl: 'https://example.com',
          data: const UsersPageData(
            items: [_sam],
            columns: [_likes, _replies],
            loaded: true,
          ),
          onPeriodChanged: (_) {},
        ),
        theme: AppTheme.light.copyWith(platform: platform),
      );
      final dimension = platform == TargetPlatform.iOS ? 48.0 : 32.0;
      expect(
        tester.getSize(find.byKey(const ValueKey('users-search'))).height,
        dimension,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('users-period-filter')))
            .height,
        dimension,
      );
      expect(find.text('Manage columns'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('users-columns')));
      await tester.pumpAndSettle();
      expect(find.text('Toggle columns'), findsNothing);
      expect(find.text('Columns'), findsWidgets);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('directory loads the next page automatically near the end', (
    tester,
  ) async {
    final items = List.generate(
      60,
      (index) => UserDirectoryItem(
        id: index + 1,
        user: UserDirectoryUser(
          id: index + 1,
          username: 'user$index',
          name: 'User $index',
        ),
        values: {'likes_received': 100 - index},
      ),
    );
    var loads = 0;
    await _pump(
      tester,
      UsersPage(
        siteUrl: 'https://example.com',
        data: UsersPageData(
          items: items,
          columns: const [_likes],
          totalRows: 80,
          loaded: true,
          hasMore: true,
        ),
        onLoadMore: () => loads++,
      ),
      size: const Size(900, 700),
    );

    expect(loads, 0);
    final list = tester.widget<ListView>(find.byType(ListView));
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent - 1400);
    await tester.pump();

    expect(loads, 1);
    expect(find.byKey(const ValueKey('users-load-more')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('directory remains usable in a narrow content lane', (
    tester,
  ) async {
    await _pump(
      tester,
      const UsersPage(
        siteUrl: 'https://example.com',
        data: UsersPageData(
          items: [_sam, _hawk],
          columns: [_likes, _replies, _days],
          totalRows: 2,
          loaded: true,
        ),
      ),
      size: const Size(390, 680),
    );

    expect(find.byKey(const ValueKey('users-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('user-row-sam')), findsOneWidget);
    expect(find.byKey(const ValueKey('users-group-filter')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 1100.0]) {
    testWidgets('directory supports large text at width $width', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: const UsersPage(
              siteUrl: 'https://example.com',
              data: UsersPageData(
                items: [_sam, _hawk],
                columns: [_likes, _replies, _days],
                loaded: true,
              ),
            ),
          ),
        ),
        size: Size(width, 820),
      );
      expect(find.byKey(const ValueKey('users-search')), findsOneWidget);
      expect(find.byKey(const ValueKey('user-row-sam')), findsOneWidget);
      expect(find.bySemanticsLabel('View profile for @sam'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets('directory exposes stable loading, empty, and error states', (
    tester,
  ) async {
    var data = const UsersPageData(loading: true);
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return UsersPage(siteUrl: 'https://example.com', data: data);
        },
      ),
    );

    expect(find.byKey(const ValueKey('users-loading')), findsOneWidget);
    update(() => data = const UsersPageData(loaded: true));
    await tester.pump();
    expect(find.byKey(const ValueKey('users-empty')), findsOneWidget);
    update(
      () => data = const UsersPageData(
        loaded: true,
        error: "Couldn't load the user directory.",
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('users-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('directory does not show a progress strip while rows update', (
    tester,
  ) async {
    await _pump(
      tester,
      const UsersPage(
        siteUrl: 'https://example.com',
        data: UsersPageData(
          items: [_sam],
          columns: [_likes],
          loadingMore: true,
          loaded: true,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('users-directory-progress')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('user-row-sam')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh button owns the directory loading feedback', (
    tester,
  ) async {
    var refreshes = 0;
    await _pump(
      tester,
      UsersPage(
        siteUrl: 'https://example.com',
        data: const UsersPageData(
          items: [_sam],
          columns: [_likes],
          loading: true,
          loaded: true,
        ),
        onRefresh: () async => refreshes++,
      ),
    );

    final refresh = find.byKey(const ValueKey('users-refresh'));
    final button = find.descendant(
      of: refresh,
      matching: find.byType(DButton),
      matchRoot: true,
    );
    expect(tester.widget<DButton>(button).loading, isTrue);
    expect(
      find.descendant(of: refresh, matching: find.byType(DSpinner)),
      findsOneWidget,
    );

    await tester.tap(refresh);
    await tester.pump();
    expect(refreshes, 0);
    expect(tester.takeException(), isNull);
  });
}

final _countedColumns = [
  for (var index = 0; index < 5; index++)
    UserDirectoryColumn(
      id: index + 1,
      name: 'metric$index',
      type: UserDirectoryColumnType.automatic,
      position: index,
    ),
];

List<UserDirectoryItem> _countedItems() => [
  for (var index = 0; index < 1000; index++)
    UserDirectoryItem(
      id: index + 1,
      user: UserDirectoryUser(id: index + 1, username: 'user$index'),
      values: _CountingValues({
        for (var metric = 0; metric < 5; metric++)
          'metric$metric': index + metric,
      }),
    ),
];

Finder _metrics(String username) => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith(
        'user-metric-$username-',
      ),
);

Future<void> _resizeBy(WidgetTester tester, String label, double delta) =>
    tester.drag(_resize(label), Offset(delta, 0));

Finder _resize(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is DResizableHandle &&
      widget.semanticLabel == 'Resize $label column',
);

final class _CountingValues extends MapBase<String, Object?> {
  _CountingValues(this._values);

  final Map<String, Object?> _values;
  int reads = 0;

  @override
  Object? operator [](Object? key) {
    reads++;
    return _values[key];
  }

  @override
  void operator []=(String key, Object? value) => _values[key] = value;

  @override
  Iterable<String> get keys => _values.keys;

  @override
  void clear() => _values.clear();

  @override
  Object? remove(Object? key) => _values.remove(key);
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1000, 760),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

final class _ColumnWidthMemoryPersistence
    implements UserDirectoryColumnWidthPersistence {
  final Map<String, String> _values = {};

  @override
  Future<String?> readWidths({required String siteUrl}) async =>
      _values[siteUrl];

  @override
  Future<bool> writeWidths({
    required String siteUrl,
    required String encoded,
  }) async {
    _values[siteUrl] = encoded;
    return true;
  }
}

final class _DelayedColumnWidthPersistence
    implements UserDirectoryColumnWidthPersistence {
  _DelayedColumnWidthPersistence(this._initialValue);

  final String _initialValue;
  final Completer<String?> _read = Completer<String?>();
  final List<String> writes = [];

  void completeRead() => _read.complete(_initialValue);

  @override
  Future<String?> readWidths({required String siteUrl}) => _read.future;

  @override
  Future<bool> writeWidths({
    required String siteUrl,
    required String encoded,
  }) async {
    writes.add(encoded);
    return true;
  }
}
