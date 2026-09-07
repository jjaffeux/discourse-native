import 'dart:async';
import 'dart:collection';

import 'package:discourse_native/src/data/user_directory_column_width_store.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/shell/user_directory_controller.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
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
  testWidgets('directory hover updates only the affected row backgrounds', (
    tester,
  ) async {
    final items = _countedItems();
    await _pump(
      tester,
      UsersPage(
        siteUrl: 'https://example.com',
        data: UsersPageData(
          items: items,
          columns: _countedColumns,
          currentUsername: 'USER2',
          loaded: true,
        ),
      ),
      size: const Size(1100, 820),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    addTearDown(mouse.removePointer);
    await tester.pump();
    final stableWidgets = [
      for (final key in [
        'users-toolbar',
        'users-search',
        'users-metric-column-width-1',
        'user-avatar-user0',
        'user-identity-background-user5',
        'user-metrics-background-user5',
      ])
        (key, tester.widget(find.byKey(ValueKey(key)))),
    ];
    for (final item in items) {
      (item.values as _CountingValues).reads = 0;
    }
    for (var index = 0; index < 5; index++) {
      await mouse.moveTo(
        tester.getCenter(find.byKey(ValueKey('user-row-user$index'))),
      );
      await tester.pump();
      expect(_rowColors(tester, 'user$index'), [
        AppTheme.light.shell.hover,
        AppTheme.light.shell.hover,
      ]);
    }
    final reads = items.fold<int>(
      0,
      (total, item) => total + (item.values as _CountingValues).reads,
    );
    expect(reads, 0, reason: '1000 users, 5 metrics, 5 mouse moves');
    for (final (key, widget) in stableWidgets) {
      expect(
        tester.widget(find.byKey(ValueKey(key))),
        same(widget),
        reason: key,
      );
    }
    expect(_rowColors(tester, 'user2'), [
      AppTheme.light.colorScheme.tertiaryContainer,
      AppTheme.light.colorScheme.tertiaryContainer,
    ]);
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();
    expect(_rowColors(tester, 'user4'), [
      AppTheme.light.shell.content,
      AppTheme.light.shell.content,
    ]);
  });

  testWidgets(
    'hover follows split scrolling and theme changes with lazy rows',
    (tester) async {
      final items = _countedItems();
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
                  items: items,
                  columns: _countedColumns,
                  currentUsername: 'user21',
                  loaded: true,
                ),
              ),
            );
          },
        ),
        size: const Size(700, 700),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final firstRow = find.byKey(const ValueKey('user-row-user0'));
      await mouse.addPointer(location: tester.getCenter(firstRow));
      addTearDown(mouse.removePointer);
      await tester.pump();
      final identity = tester.widget<ListView>(
        find.byKey(const PageStorageKey('users-identity-scroll')),
      );
      final metrics = tester.widget<ListView>(
        find.byKey(const PageStorageKey('users-metrics-scroll')),
      );
      identity.controller!.jumpTo(56 * 20);
      await tester.pumpAndSettle();
      expect(metrics.controller!.offset, identity.controller!.offset);
      expect(firstRow, findsNothing);
      expect(find.byKey(const ValueKey('user-row-user999')), findsNothing);
      expect(_rowColors(tester, 'user20'), [
        theme.shell.hover,
        theme.shell.hover,
      ]);
      final row = find.byKey(const ValueKey('user-row-user20'));
      final metricRow = find.byKey(
        const ValueKey('user-metrics-background-user20'),
      );
      final identityPosition = tester.getTopLeft(row);
      expect(tester.getTopLeft(metricRow).dy, identityPosition.dy);

      await mouse.moveTo(tester.getTopLeft(metricRow) + const Offset(30, 28));
      await tester.pump();
      expect(_rowColors(tester, 'user20'), [
        theme.shell.hover,
        theme.shell.hover,
      ]);
      final horizontal = tester.widget<SingleChildScrollView>(
        find.descendant(
          of: find.byKey(const ValueKey('users-table')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is SingleChildScrollView &&
                widget.scrollDirection == Axis.horizontal,
          ),
        ),
      );
      final metricLeft = tester.getTopLeft(metricRow).dx;
      horizontal.controller!.jumpTo(100);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(row), identityPosition);
      expect(tester.getTopLeft(metricRow).dx, metricLeft - 100);
      expect(_rowColors(tester, 'user20'), [
        theme.shell.hover,
        theme.shell.hover,
      ]);

      update(() => theme = AppTheme.dark);
      await tester.pumpAndSettle();
      expect(_rowColors(tester, 'user20'), [
        theme.shell.hover,
        theme.shell.hover,
      ]);
      expect(_rowColors(tester, 'user21'), [
        theme.colorScheme.tertiaryContainer,
        theme.colorScheme.tertiaryContainer,
      ]);
      await mouse.moveTo(const Offset(1, 1));
      await tester.pump();
      expect(_rowColors(tester, 'user20'), [
        theme.shell.content,
        theme.shell.content,
      ]);
      metrics.controller!.jumpTo(0);
      await tester.pumpAndSettle();
      expect(identity.controller!.offset, 0);
      expect(_rowColors(tester, 'user0'), [
        theme.shell.content,
        theme.shell.content,
      ]);
      expect(tester.takeException(), isNull);
    },
  );

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
      if (['query', 'forum', 'account'].contains(change)) {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(
          location: tester.getCenter(
            find.byKey(const ValueKey('user-row-first')),
          ),
        );
        addTearDown(mouse.removePointer);
        await tester.pump();
        expect(_rowColors(tester, 'first'), [
          AppTheme.light.shell.hover,
          AppTheme.light.shell.hover,
        ]);
      }
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
      expect(_rowColors(tester, account), [
        AppTheme.light.colorScheme.tertiaryContainer,
        AppTheme.light.colorScheme.tertiaryContainer,
      ]);
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
    await tester.drag(
      find.byKey(const ValueKey('users-resize-1-handle')),
      const Offset(60, 0),
    );
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
      expect(
        tester
            .widget<TextField>(searchFinder)
            .decoration
            ?.prefixIconConstraints
            ?.minHeight,
        searchHeight,
      );

      final page = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('users-page')),
      );
      final toolbar = tester.widget<Material>(
        find.byKey(const ValueKey('users-toolbar')),
      );
      expect(page.color, AppTheme.light.shell.content);
      expect(toolbar.color, AppTheme.light.shell.sidebar);
      final currentUserColor = AppTheme.light.colorScheme.tertiaryContainer;
      final currentIdentity = tester.widget<Container>(
        find.byKey(const ValueKey('user-identity-background-sam')),
      );
      final currentIdentityDecoration =
          currentIdentity.decoration! as BoxDecoration;
      expect(currentIdentityDecoration.color, currentUserColor);
      expect(
        tester
            .widget<ColoredBox>(
              find.byKey(const ValueKey('user-metrics-background-sam')),
            )
            .color,
        currentUserColor,
      );
      expect(
        (tester
                    .widget<Container>(
                      find.byKey(
                        const ValueKey('user-identity-background-hawk'),
                      ),
                    )
                    .decoration!
                as BoxDecoration)
            .color,
        AppTheme.light.shell.content,
      );
      expect(find.byKey(const ValueKey('user-row-sam')), findsOneWidget);
      expect(find.byKey(const ValueKey('user-avatar-sam')), findsOneWidget);
      final avatarClip = tester.widget<ClipRRect>(
        find.byKey(const ValueKey('user-avatar-sam')),
      );
      expect(avatarClip.borderRadius, BorderRadius.circular(16));
      expect(find.byKey(const ValueKey('users-select-all')), findsNothing);
      expect(find.byKey(const ValueKey('user-select-sam')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('users-table')),
          matching: find.byType(Checkbox),
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

      expect(find.text('Likes received'), findsOneWidget);
      await tester.tap(find.text('Likes received'));
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
        expect(tester.widget<TextField>(search).controller?.text, 'restored');
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

    expect(
      find.byKey(const ValueKey('users-resize-identity-handle')),
      findsOneWidget,
    );
    for (final column in const [_likes, _replies, _days]) {
      expect(
        find.byKey(ValueKey('users-resize-${column.id}-handle')),
        findsOneWidget,
      );
    }

    final identityColumn = find.byKey(
      const ValueKey('users-identity-column-width'),
    );
    final firstMetric = find.byKey(
      const ValueKey('users-metric-column-width-1'),
    );
    final initialIdentityWidth = tester.getSize(identityColumn).width;

    await tester.drag(
      find.byKey(const ValueKey('users-resize-identity-handle')),
      const Offset(42, 0),
    );
    await tester.pumpAndSettle();
    final resizedIdentityWidth = tester.getSize(identityColumn).width;
    expect(resizedIdentityWidth, closeTo(initialIdentityWidth + 42, .01));

    await tester.drag(
      find.byKey(const ValueKey('users-resize-1-handle')),
      const Offset(-1000, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(firstMetric).width, 88);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _pump(
      tester,
      page('https://example.com'),
      size: const Size(1100, 820),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(identityColumn).width, resizedIdentityWidth);
    expect(tester.getSize(firstMetric).width, 88);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _pump(
      tester,
      page('https://another.example'),
      size: const Size(1100, 820),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(identityColumn).width, initialIdentityWidth);
    expect(tester.getSize(firstMetric).width, greaterThan(88));
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

    final identityColumn = find.byKey(
      const ValueKey('users-identity-column-width'),
    );
    final initialWidth = tester.getSize(identityColumn).width;
    await tester.drag(
      find.byKey(const ValueKey('users-resize-identity-handle')),
      const Offset(32, 0),
    );
    await tester.pumpAndSettle();
    final resizedWidth = tester.getSize(identityColumn).width;
    expect(resizedWidth, initialWidth + 32);

    persistence.completeRead();
    await tester.pumpAndSettle();

    expect(tester.getSize(identityColumn).width, resizedWidth);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('users-metric-column-width-1')))
          .width,
      200,
    );
    expect(UserDirectoryColumnWidths.decode(persistence.writes.last).widths, {
      'identity': resizedWidth,
      'metric.automatic.1': 200,
    });
    expect(tester.takeException(), isNull);
  });

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
      final dialog = tester.widget<AlertDialog>(
        find.byKey(const ValueKey('users-manage-columns-dialog')),
      );
      expect(
        dialog.insetPadding,
        const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      );
      final content = find.byKey(
        const ValueKey('users-manage-columns-content'),
      );
      expect(tester.widget<SizedBox>(content).width, 560);
      expect(tester.getSize(content).width, 560);
      expect(
        tester
            .widget<ConstrainedBox>(
              find.byKey(const ValueKey('users-manage-columns-list')),
            )
            .constraints
            .maxHeight,
        600,
      );
      final solutionsTile = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('users-manage-column-9')),
      );
      expect(solutionsTile.value, isFalse);
      expect(solutionsTile.visualDensity, VisualDensity.compact);
      expect(solutionsTile.minTileHeight, 48);
      expect(solutionsTile.minVerticalPadding, 6);
      expect(solutionsTile.contentPadding, EdgeInsets.zero);

      final firstUp = find.byKey(const ValueKey('users-column-up-1'));
      final firstDown = find.byKey(const ValueKey('users-column-down-1'));
      expect(
        tester.widget<DButton>(firstUp).variant,
        DButtonVariant.transparent,
      );
      expect(
        tester.widget<DButton>(firstDown).variant,
        DButtonVariant.transparent,
      );
      expect(tester.getSize(firstUp), const Size.square(40));
      expect(tester.getSize(firstDown), const Size.square(40));
      expect(tester.getTopRight(firstUp).dx, tester.getTopLeft(firstDown).dx);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('users-manage-columns-dialog')),
          matching: find.byType(Divider),
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
      310,
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

    final avatarClip = tester.widget<ClipRRect>(
      find.byKey(const ValueKey('user-avatar-sam')),
    );
    expect(avatarClip.borderRadius, BorderRadius.circular(5));
  });

  testWidgets('Matrix loads the next page automatically near the end', (
    tester,
  ) async {
    final items = List.generate(
      30,
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
    await tester.drag(
      find.byKey(const PageStorageKey<String>('users-metrics-scroll')),
      const Offset(0, -1200),
    );
    await tester.pump();

    expect(loads, 1);
    expect(find.byKey(const ValueKey('users-load-more')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Matrix keeps the scrollbar out of the pinned user column', (
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
      theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
    );

    final identity = tester.widget<ListView>(
      find.byKey(const PageStorageKey<String>('users-identity-scroll')),
    );
    final metrics = tester.widget<ListView>(
      find.byKey(const PageStorageKey<String>('users-metrics-scroll')),
    );
    final scrollbars = tester.widgetList<Scrollbar>(find.byType(Scrollbar));

    expect(
      scrollbars.where(
        (scrollbar) => identical(scrollbar.controller, identity.controller),
      ),
      isEmpty,
    );
    expect(
      scrollbars.where(
        (scrollbar) => identical(scrollbar.controller, metrics.controller),
      ),
      hasLength(1),
    );
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
      find.descendant(
        of: refresh,
        matching: find.byType(CircularProgressIndicator),
      ),
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

List<Color?> _rowColors(WidgetTester tester, String username) => [
  (tester
              .widget<Container>(
                find.byKey(ValueKey('user-identity-background-$username')),
              )
              .decoration!
          as BoxDecoration)
      .color,
  tester
      .widget<ColoredBox>(
        find.byKey(ValueKey('user-metrics-background-$username')),
      )
      .color,
];

List<double?> _barWidths(WidgetTester tester, String username) => [
  for (final bar in tester.widgetList<FractionallySizedBox>(
    find.descendant(
      of: find.byKey(ValueKey('user-metrics-background-$username')),
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
