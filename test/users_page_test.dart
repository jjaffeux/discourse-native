import 'dart:async';
import 'dart:collection';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/user_directory_column_width_store.dart';
import 'package:discourse_native/src/models/json.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
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
const _github = UserDirectoryColumn(
  id: 14,
  name: 'GitHub Username',
  type: UserDirectoryColumnType.userField,
  position: 5,
  userFieldId: 42,
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
      'invalid directory ${value is String ? 'text' : 'number'} $value renders as unscaled text',
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
        expect(_barWidths(tester, 'invalid'), isEmpty);
        expect(_barWidths(tester, 'half'), [.5, .5, .5]);
        expect(_barWidths(tester, 'full'), [1, 1, 1]);
        for (final text in tester.widgetList<Text>(find.text('$value'))) {
          expect(text.style?.fontWeight, FontWeight.w400);
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
          find.descendant(of: _metrics('sam'), matching: find.byType(Text)),
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

  for (final change in [
    'page append',
    'refresh',
    'query',
    'forum',
    'account',
    'column definition',
    'column addition',
  ]) {
    testWidgets('metric bars use the new maxima after $change', (tester) async {
      const first = UserDirectoryItem(
        id: 1,
        user: UserDirectoryUser(id: 1, username: 'first'),
        values: {'likes_received': 10, 'post_count': 40},
      );
      const second = UserDirectoryItem(
        id: 2,
        user: UserDirectoryUser(id: 2, username: 'second'),
        values: {'likes_received': 20, 'post_count': 50},
      );
      var items = [first, second];
      var columns = [_likes];
      var query = const UserDirectoryQuery();
      var site = 'https://example.com';
      var account = 'first';
      late StateSetter update;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return UsersPage(
              siteUrl: site,
              data: UsersPageData(
                items: items,
                columns: columns,
                currentUsername: account,
                query: query,
                loaded: true,
              ),
            );
          },
        ),
      );
      expect(_barWidths(tester, 'first'), [.5]);
      var expected = [.25];
      update(() {
        switch (change) {
          case 'page append':
            items = [
              ...items,
              const UserDirectoryItem(
                id: 3,
                user: UserDirectoryUser(id: 3, username: 'third'),
                values: {'likes_received': 40},
              ),
            ];
          case 'column definition':
            columns = [
              const UserDirectoryColumn(
                id: 1,
                name: 'post_count',
                type: UserDirectoryColumnType.plugin,
                position: 1,
              ),
            ];
            expected = [.8];
          case 'column addition':
            columns = [_likes, _replies];
            expected = [.5, .8];
          default:
            if (change == 'query') {
              query = const UserDirectoryQuery(
                period: UserDirectoryPeriod.daily,
              );
            }
            if (change == 'forum') site = 'https://another.example';
            if (change == 'account') account = 'second';
            items = [
              first,
              UserDirectoryItem(
                id: second.id,
                user: second.user,
                values: const {'likes_received': 40},
              ),
            ];
        }
      });
      await tester.pump();
      expect(_barWidths(tester, 'first'), expected);
      expect(find.text('You'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unchanged metrics reuse maxima through directory interactions', (
    tester,
  ) async {
    final items = _countedItems();
    final offscreenValues = items.last.values as _CountingValues;
    var loadingMore = false;
    var theme = AppTheme.light;
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return Theme(
            data: theme,
            child: UsersPage(
              siteUrl: 'https://example.com',
              data: UsersPageData(
                items: List.of(items),
                columns: List.of(_countedColumns),
                loadingMore: loadingMore,
                loaded: true,
              ),
            ),
          );
        },
      ),
    );
    expect(offscreenValues.reads, 5);
    offscreenValues.reads = 0;
    await tester.enterText(
      find.byKey(const ValueKey('users-search')),
      'person',
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(offscreenValues.reads, 0, reason: 'typing');
    await tester.drag(_resize('Metric0'), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(offscreenValues.reads, 0, reason: 'resizing');
    update(() {
      loadingMore = true;
      theme = AppTheme.dark;
    });
    await tester.pumpAndSettle();
    expect(offscreenValues.reads, 0, reason: 'loading feedback and theme');
    await tester.tap(find.byKey(const ValueKey('users-columns')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('users-column-2')));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Metric1'), findsNothing);
    expect(offscreenValues.reads, 0, reason: 'hiding a column');
    await tester.tap(find.byKey(const ValueKey('users-columns')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('users-column-2')));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Metric1'), findsOneWidget);
    expect(offscreenValues.reads, 0, reason: 'showing a column');
    expect(_barWidths(tester, 'user1'), [
      for (var metric = 0; metric < 5; metric++) .06,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Matrix supports search, periods, sorting, columns, and omits selection',
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
      expect(tableRect.left, 0);
      expect(tableRect.right, 1100);
      expect(tableRect.bottom, 820);

      final searchFinder = find.byKey(const ValueKey('users-search'));
      final periodFinder = find.byKey(const ValueKey('users-period-filter'));
      final searchHeight = tester.getSize(searchFinder).height;
      expect(searchHeight, tester.getSize(periodFinder).height);
      expect(tester.widget<DInput>(searchFinder).controller, isNotNull);
      expect(find.text('You'), findsOneWidget);
      expect(find.byKey(const ValueKey('user-row-sam')), findsOneWidget);
      expect(find.byKey(const ValueKey('user-avatar-sam')), findsOneWidget);
      final avatar = tester.widget<DAvatar>(
        find.byKey(const ValueKey('user-avatar-sam')),
      );
      expect(avatar.borderRadius, BorderRadius.circular(16));
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
      await tester.tap(find.byKey(const ValueKey('users-group-filter')));
      await tester.pumpAndSettle();
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
      await tester.tap(find.byKey(const ValueKey('users-column-2')));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Replies posted'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('users-refresh')));
      await tester.pump();
      expect(refreshes, 1);
      expect(tester.takeException(), isNull);
    },
  );

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
        expect(tester.widget<DInput>(search).controller?.text, 'restored');
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
      'column visibility ${dialogOpen ? 'drafts' : 'choices'} stay with their forum',
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
        await tester.tap(find.byKey(const ValueKey('users-column-2')));
        if (!dialogOpen) {
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
          expect(find.text('Replies posted'), findsNothing);
        }

        update(() => site = 'https://another.example');
        await tester.pump();
        if (dialogOpen) {
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
        }
        expect(find.text('Likes received'), findsOneWidget);
        expect(find.text('Replies posted'), findsOneWidget);
      },
    );
  }

  for (final boundary in ['forum', 'account', 'permission']) {
    testWidgets('column management stops after the $boundary changes', (
      tester,
    ) async {
      var site = 'https://example.com';
      var username = 'admin';
      var canManage = true;
      var writes = 0;
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
                availableColumns: const [_likes, _solutions],
                loaded: true,
                currentUsername: username,
                canManageColumns: canManage,
              ),
              onManageColumns: canManage
                  ? (_) async {
                      writes++;
                      return true;
                    }
                  : null,
            );
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('users-columns')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('users-manage-column-9')));
      update(() {
        switch (boundary) {
          case 'forum':
            site = 'https://another.example';
          case 'account':
            username = 'replacement';
          case 'permission':
            canManage = false;
        }
      });
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('users-save-columns')));
      await tester.pumpAndSettle();

      expect(writes, 0);
      expect(tester.takeException(), isNull);
    });
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
      List<UserDirectoryColumn>? saved;
      await _pump(
        tester,
        UsersPage(
          siteUrl: 'https://example.com',
          data: const UsersPageData(
            items: [_sam],
            columns: [_likes, _replies],
            availableColumns: [_likes, _replies],
            canManageColumns: true,
            loaded: true,
          ),
          onPeriodChanged: (_) {},
          onManageColumns: (columns) async {
            saved = columns;
            return true;
          },
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
      await tester.tap(find.byKey(const ValueKey('users-columns')));
      await tester.pumpAndSettle();
      final down = find.byKey(const ValueKey('users-column-down-1'));
      final up = find.byKey(const ValueKey('users-column-up-2'));
      for (final button in [down, up]) {
        expect(
          tester.getSize(button),
          Size.square(platform == TargetPlatform.iOS ? 48 : 28),
        );
        expect(
          tester.getSemantics(button).rect.size,
          Size.square(platform == TargetPlatform.iOS ? 48 : 28),
        );
        expect(
          tester.getSemantics(button).label,
          tester.widget<DButton>(button).tooltip,
        );
      }
      // The bottom outside the painted icon must still activate the action.
      final target = tester.getRect(down);
      await tester.tapAt(Offset(target.center.dx, target.bottom - 1));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('users-save-columns')));
      await tester.pumpAndSettle();
      expect(saved!.map((column) => column.id), [2, 1]);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'staff column editor includes disabled plugin and user-field columns',
    (tester) async {
      List<UserDirectoryColumn>? saved;
      await _pump(
        tester,
        UsersPage(
          siteUrl: 'https://example.com',
          data: const UsersPageData(
            items: [_sam],
            columns: [_likes],
            availableColumns: [_likes, _solutions, _github],
            canManageColumns: true,
            loaded: true,
          ),
          onManageColumns: (columns) async {
            saved = columns;
            return true;
          },
        ),
        size: const Size(1100, 820),
      );

      await tester.tap(find.byKey(const ValueKey('users-columns')));
      await tester.pumpAndSettle();

      expect(find.text('Directory columns'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('users-enabled-columns-count')),
        findsNothing,
      );
      expect(
        find.text(
          'Choose which columns everyone sees and arrange their order.',
        ),
        findsNothing,
      );
      expect(find.text('Solutions'), findsOneWidget);
      expect(find.text('GitHub Username'), findsOneWidget);
      final dialog = tester.widget<DDialogContent>(
        find.byKey(const ValueKey('users-manage-columns-dialog')),
      );
      expect(dialog.maxWidth, 608);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('users-manage-columns-content')))
            .width,
        lessThanOrEqualTo(608),
      );
      final solutionsTile = tester.widget<DCheckbox>(
        find.byKey(const ValueKey('users-manage-column-9')),
      );
      expect(solutionsTile.value, isFalse);
      expect(solutionsTile.contentPadding, EdgeInsets.zero);

      final firstUp = find.byKey(const ValueKey('users-column-up-1'));
      final firstDown = find.byKey(const ValueKey('users-column-down-1'));
      expect(tester.widget<DButton>(firstUp).variant, DButtonVariant.ghost);
      expect(tester.widget<DButton>(firstDown).variant, DButtonVariant.ghost);
      expect(tester.getSize(firstUp), const Size.square(48));
      expect(tester.getSize(firstDown), const Size.square(48));
      expect(tester.getTopRight(firstUp).dx, tester.getTopLeft(firstDown).dx);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('users-manage-columns-dialog')),
          matching: find.byType(DSeparator),
        ),
        findsNWidgets(2),
      );

      await tester.tap(find.byKey(const ValueKey('users-manage-column-9')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('users-column-up-14')));
      await tester.tap(find.byKey(const ValueKey('users-save-columns')));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.map((column) => column.name), [
        'likes_received',
        'GitHub Username',
        'solutions',
      ]);
      expect(saved!.last.enabled, isTrue);
      expect(saved!.map((column) => column.position), [1, 2, 3]);
    },
  );

  testWidgets('staff column editor stays compact on narrow screens', (
    tester,
  ) async {
    await _pump(
      tester,
      UsersPage(
        siteUrl: 'https://example.com',
        data: const UsersPageData(
          items: [_sam],
          columns: [_likes],
          availableColumns: [_likes, _solutions, _github],
          canManageColumns: true,
          loaded: true,
        ),
        onManageColumns: (_) async => true,
      ),
      size: const Size(1100, 700),
    );

    await tester.tap(find.byKey(const ValueKey('users-columns')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 700);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('users-manage-columns-dialog')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('users-manage-columns-content')))
          .width,
      lessThan(390),
    );
    expect(find.text('Save changes'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('users-manage-column-1')))
          .height,
      48,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Matrix follows an explicit theme avatar radius', (tester) async {
    final theme = AppTheme.fromPalette(
      ResolvedSitePalette.fromJson({
        'primary': Colors.black.toARGB32(),
        'secondary': Colors.white.toARGB32(),
        'tertiary': discourseBlue.toARGB32(),
        'avatarBorderRadius': const AvatarBorderRadius.pixels(5).toJson(),
      }),
    );
    await _pump(
      tester,
      const UsersPage(
        siteUrl: 'https://example.com',
        data: UsersPageData(items: [_sam], loaded: true),
      ),
      theme: theme,
    );

    final avatar = tester.widget<DAvatar>(
      find.byKey(const ValueKey('user-avatar-sam')),
    );
    expect(avatar.borderRadius, BorderRadius.circular(5));
  });

  testWidgets('Matrix loads the next page automatically near the end', (
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

  testWidgets('Matrix remains usable in a narrow content lane', (tester) async {
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

  testWidgets('Matrix exposes stable loading, empty, and error states', (
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

  testWidgets('Matrix does not show a progress strip while rows update', (
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
          updatingColumns: true,
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
    final button = find.descendant(of: refresh, matching: find.byType(DButton));
    expect(tester.widget<DButton>(button).loading, isTrue);
    expect(
      find.descendant(of: refresh, matching: find.byType(DSpinner)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(of: refresh, matching: find.byType(FilledButton)),
          )
          .onPressed,
      isNull,
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

Future<void> _resizeBy(WidgetTester tester, String label, double delta) async {
  final gesture = await tester.startGesture(tester.getCenter(_resize(label)));
  // Establish the drag past touch slop before measuring the resize delta.
  await gesture.moveBy(const Offset(20, 0));
  await tester.pump();
  await gesture.moveBy(Offset(delta, 0));
  await gesture.up();
}

Finder _resize(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is DResizableHandle &&
      widget.semanticLabel == 'Resize $label column',
);

List<double?> _barWidths(WidgetTester tester, String username) => [
  for (final bar in tester.widgetList<FractionallySizedBox>(
    find.descendant(
      of: _metrics(username),
      matching: find.byType(FractionallySizedBox),
    ),
  ))
    bar.widthFactor,
];

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
