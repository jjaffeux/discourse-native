import 'dart:async';

import 'package:discourse_native/src/data/user_directory_column_width_store.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
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
      expect(find.text('Solutions'), findsOneWidget);
      expect(find.text('GitHub Username'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('users-manage-column-9')),
            )
            .value,
        isFalse,
      );

      await tester.tap(find.byKey(const ValueKey('users-manage-column-9')));
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
