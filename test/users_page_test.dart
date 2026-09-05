import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
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
  testWidgets(
    'Matrix supports search, periods, sorting, columns, and selection',
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
      expect(find.byKey(const ValueKey('users-load-more')), findsNothing);
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
      expect(find.byKey(const ValueKey('user-row-sam')), findsOneWidget);
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

      await tester.tap(find.text('Likes received').last);
      expect(sort, ('likes_received', true));
      await tester.tap(find.byKey(const ValueKey('users-sort-direction')));
      expect(sort, ('likes_received', true));

      await tester.tap(find.byKey(const ValueKey('user-select-sam')));
      await tester.pump();
      expect(
        tester
            .widget<Checkbox>(find.byKey(const ValueKey('user-select-sam')))
            .value,
        isTrue,
      );

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
