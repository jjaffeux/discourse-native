import 'dart:collection';

import 'package:discourse_native/discourse_ui.dart';

import 'package:discourse_native/src/models/json.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/skeleton_expectations.dart';

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
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('directory controls use reference scaling on $platform', (
      tester,
    ) async {
      for (final (appScale, platformScale, height, textSize) in [
        (1.0, 1.0, 36.0, 14.0),
        (1.25, 2.0, 67.5, 35.0),
      ]) {
        await _pump(
          tester,
          const UsersPage(
            siteUrl: 'https://example.com',
            data: UsersPageData(loaded: true),
          ),
          theme: AppTheme.light.copyWith(platform: platform),
          textScaler: AppTextScaler(
            platformScaler: TextScaler.linear(platformScale),
            appScale: appScale,
            baselineScale: 17 / 14,
          ),
        );
        await tester.pumpAndSettle();
        for (final key in [
          'users-period-filter',
          'users-group-filter',
          'users-columns',
        ]) {
          expect(
            tester.getSize(find.byKey(ValueKey(key))).height,
            height,
            reason: key,
          );
        }
        final label = find
            .descendant(
              of: find.byKey(const ValueKey('users-period-filter')),
              matching: find.byType(Text),
            )
            .first;
        expect(
          tester
              .getSize(find.byKey(const ValueKey('users-group-filter')))
              .width,
          lessThanOrEqualTo(96 * appScale * platformScale),
        );
        final context = tester.element(label);
        expect(
          MediaQuery.textScalerOf(
            context,
          ).scale(DefaultTextStyle.of(context).style.fontSize!),
          textSize,
        );
        expect(tester.takeException(), isNull);
      }
    });
  }

  for (final size in [const Size(390, 844), const Size(1440, 1200)]) {
    testWidgets('user skeleton fills the page at $size', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        const UsersPage(
          siteUrl: 'https://example.com',
          data: UsersPageData(loading: true),
        ),
        size: size,
      );
      expectSkeletonFillsViewport(
        tester,
        label: 'Loading users',
        bottom: size.height,
      );
      expect(find.bySemanticsLabel('Loading users'), findsOneWidget);
      expect(find.byKey(const ValueKey('users-search')), findsOneWidget);
      semantics.dispose();
    });
  }

  testWidgets('failed directory can be retried from its error state', (
    tester,
  ) async {
    var retries = 0;
    await _pump(
      tester,
      UsersPage(
        siteUrl: 'https://example.com',
        data: const UsersPageData(loaded: true, error: 'Offline'),
        onRefresh: () async {
          retries++;
        },
      ),
    );
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

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
        expect(
          find.descendant(
            of: _metrics('invalid'),
            matching: find.byType(DChartBar),
          ),
          findsNothing,
        );
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
      ['1h 1m', '1.3M', '—'],
      ['-1m', '-1250', '4'],
      ['2562047788h 0m', '120', '1e+294M'],
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

  testWidgets('directory abbreviates counts the way the web directory does', (
    tester,
  ) async {
    const rows = [
      (10500, '10.5k'),
      (999500, '999k'),
      (999999, '999k'),
      (1500000, '1.5M'),
    ];
    await _pump(
      tester,
      UsersPage(
        siteUrl: 'https://example.com',
        data: UsersPageData(
          items: [
            for (final (index, (likes, _)) in rows.indexed)
              UserDirectoryItem.fromWire({
                'user': {'id': index + 1, 'username': 'user$index'},
                'likes_received': likes,
              }, 'https://example.com'),
          ],
          columns: const [_likes],
          loaded: true,
        ),
      ),
      size: const Size(1100, 900),
    );

    for (final (index, (likes, label)) in rows.indexed) {
      final texts = tester.widgetList<Text>(
        find.descendant(
          of: _metrics('user$index'),
          matchRoot: true,
          matching: find.byType(Text),
        ),
      );
      expect(texts.map((text) => text.data), [label], reason: '$likes');
    }
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
    final list = tester.widget<ListView>(
      find.byWidgetPredicate((widget) => widget is ListView),
    );
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
    'directory keeps the all-groups filter when there are no choices',
    (tester) async {
      await _pump(
        tester,
        UsersPage(
          siteUrl: 'https://example.com',
          data: const UsersPageData(
            items: [_sam, _hawk],
            columns: [_likes],
            loaded: true,
          ),
          onGroupChanged: (_) {},
        ),
      );

      expect(find.byKey(const ValueKey('users-group-filter')), findsOneWidget);
      expect(find.text('All groups'), findsWidgets);
      expect(find.byKey(const ValueKey('users-search')), findsOneWidget);
      expect(find.byKey(const ValueKey('user-row-sam')), findsOneWidget);
    },
  );

  testWidgets('an active group can be cleared when discovery has no choices', (
    tester,
  ) async {
    var query = const UserDirectoryQuery(group: 'design');
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => UsersPage(
          siteUrl: 'https://example.com',
          data: UsersPageData(
            columns: const [_likes],
            loaded: true,
            query: query,
          ),
          onGroupChanged: (group) =>
              setState(() => query = query.copyWith(group: group)),
        ),
      ),
    );

    final filter = find.byKey(const ValueKey('users-group-filter'));
    expect(filter, findsOneWidget);
    expect(
      find.descendant(of: filter, matching: find.text('design')),
      findsOneWidget,
    );
    await tester.tap(filter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('All groups'));
    await tester.pumpAndSettle();

    expect(query.group, isNull);
    expect(filter, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'opening the group filter shows all choices before and after selection',
    (tester) async {
      var query = const UserDirectoryQuery();
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => UsersPage(
            siteUrl: 'https://example.com',
            data: UsersPageData(
              columns: const [_likes],
              groupNames: const ['design', 'support'],
              loaded: true,
              query: query,
            ),
            onGroupChanged: (group) =>
                setState(() => query = query.copyWith(group: group)),
          ),
        ),
      );

      final filter = find.byKey(const ValueKey('users-group-filter'));
      // The open menu is drawn over the page, after the pill's own label.
      Finder option(String label) => find.text(label).last;

      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(find.text('design'), findsOneWidget);
      expect(find.text('support'), findsOneWidget);
      await tester.tap(option('design'));
      await tester.pumpAndSettle();
      expect(query.group, 'design');

      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(find.text('All groups'), findsOneWidget);
      expect(find.text('support'), findsOneWidget);
      await tester.tap(option('support'));
      await tester.pumpAndSettle();
      expect(query.group, 'support');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'directory supports search, periods, sorting, columns, and omits selection',
    (tester) async {
      String? search;
      String? group;
      UserDirectoryPeriod? period;
      (String, bool)? sort;

      await _pump(
        tester,
        UsersPage(
          siteUrl: 'https://example.com',
          data: const UsersPageData(
            items: [_sam, _hawk],
            columns: [_likes, _replies, _days],
            groupNames: ['design', 'staff'],
            currentUsername: 'SAM',
            totalRows: 87,
            loaded: true,
            hasMore: true,
          ),
          onSearchChanged: (value) => search = value,
          onGroupChanged: (value) => group = value,
          onPeriodChanged: (value) => period = value,
          onSortChanged: (order, ascending) => sort = (order, ascending),
        ),
        size: const Size(1100, 820),
      );

      final pageRect = tester.getRect(find.byKey(const ValueKey('users-page')));
      final tableRect = tester.getRect(
        find.byKey(const ValueKey('users-table')),
      );
      expect(pageRect, const Rect.fromLTWH(0, 0, 1100, 820));
      expect(tableRect.left, 0);
      expect(tableRect.right, 1100);
      expect(tableRect.bottom, 820);
      expect(find.byType(DResizableHandle), findsNothing);

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
      expect(tester.getSize(avatar), const Size.square(22));
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
      expect(find.text('staff'), findsOneWidget);
      await tester.tap(find.text('design'));
      await tester.pumpAndSettle();
      expect(group, 'design');

      // A header orders the directory itself: the column it is ordered by
      // turns around, a count starts at its largest and a name at A.
      expect(find.text('Likes received'), findsOneWidget);
      await tester.tap(find.text('Likes received'));
      await tester.pump();
      expect(sort, ('likes_received', true));
      await tester.tap(find.text('Replies posted'));
      await tester.pump();
      expect(sort, ('post_count', false));
      await tester.tap(find.text('User'));
      await tester.pump();
      expect(sort, ('username', true));
      sort = null;
      await tester.tap(find.text('Name'));
      await tester.pump();
      expect(sort, isNull);
      expect(find.text('Sort ascending'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('users-columns')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(DDropdownMenuCheckboxItem, 'Replies posted'),
      );
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.text('Replies posted'), findsNothing);

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

  testWidgets('the echoed trimmed search keeps the typed whitespace', (
    tester,
  ) async {
    var query = const UserDirectoryQuery();
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
              items: const [_sam],
              columns: const [_likes],
              loaded: true,
              query: query,
            ),
            onSearchChanged: (value) {
              searches.add(value);
              setState(() => query = query.copyWith(search: value));
            },
          );
        },
      ),
    );
    final search = find.byKey(const ValueKey('users-search'));
    TextEditingController field() => tester
        .widget<EditableText>(
          find.descendant(of: search, matching: find.byType(EditableText)),
        )
        .controller;

    await tester.enterText(search, 'john ');
    await tester.pump(const Duration(milliseconds: 351));
    await tester.pump();

    expect(searches, ['john']);
    expect(query.search, 'john');
    expect(field().text, 'john ');
    expect(field().selection, const TextSelection.collapsed(offset: 5));

    await tester.enterText(search, 'draft');
    update(() => query = const UserDirectoryQuery(search: 'restored'));
    await tester.pump();
    expect(field().text, 'restored');
    await tester.pump(const Duration(milliseconds: 351));
    expect(searches, ['john']);
    expect(query.search, 'restored');
    expect(field().text, 'restored');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a delayed search echo keeps keystrokes typed after it', (
    tester,
  ) async {
    var query = const UserDirectoryQuery();
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
              items: const [_sam],
              columns: const [_likes],
              loaded: true,
              query: query,
            ),
            onSearchChanged: searches.add,
          );
        },
      ),
    );
    final search = find.byKey(const ValueKey('users-search'));
    await tester.enterText(search, 'john');
    await tester.pump(const Duration(milliseconds: 351));
    expect(searches, ['john']);

    await tester.enterText(search, 'john s');
    update(() => query = query.copyWith(search: 'john'));
    await tester.pump();
    expect(tester.widget<DDataTableFilterField>(search).value, 'john s');

    await tester.pump(const Duration(milliseconds: 351));
    expect(searches, ['john', 'john s']);
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

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    testWidgets('directory controls use their visible bounds on $platform', (
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
      final search = find.byKey(const ValueKey('users-search'));
      final period = find.byKey(const ValueKey('users-period-filter'));
      final columns = find.byKey(const ValueKey('users-columns'));
      final searchFocus = tester
          .widget<EditableText>(
            find.descendant(of: search, matching: find.byType(EditableText)),
          )
          .focusNode;
      final periodMenu = find.text('Day');
      final columnsMenu = find.byType(DDropdownMenuCheckboxItem);
      for (final (control, surface, height, opened) in [
        (
          search,
          find
              .descendant(of: search, matching: find.byType(AnimatedContainer))
              .first,
          platform == TargetPlatform.macOS ? 35.5 : kDTouchTargetExtent,
          () => searchFocus.hasFocus,
        ),
        (
          period,
          find.descendant(
            of: period,
            matching: find.byKey(const Key('d-select-trigger-visual')),
          ),
          platform == TargetPlatform.macOS ? 30 : 36,
          () => periodMenu.evaluate().isNotEmpty,
        ),
        (
          columns,
          find.descendant(
            of: columns,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is DButtonDecoration,
            ),
          ),
          platform == TargetPlatform.macOS ? 30 : 36,
          () => columnsMenu.evaluate().isNotEmpty,
        ),
      ]) {
        final bounds = tester.getRect(surface);
        expect(bounds.height, height);
        expect(tester.getRect(control), bounds);
        for (final outside in [
          bounds.centerLeft - const Offset(1, 0),
          bounds.centerRight + const Offset(1, 0),
          bounds.topCenter - const Offset(0, 1),
          bounds.bottomCenter + const Offset(0, 1),
        ]) {
          await tester.tapAt(outside);
          await tester.pumpAndSettle();
          expect(opened(), isFalse, reason: 'Tap outside $bounds at $outside');
        }
        await tester.tapAt(bounds.topLeft + const Offset(1, 1));
        await tester.pumpAndSettle();
        expect(opened(), isTrue, reason: 'Tap inside $bounds');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      await tester.tap(columns);
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
    final list = tester.widget<ListView>(
      find.byWidgetPredicate((widget) => widget is ListView),
    );
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent - 1400);
    await tester.pump();

    expect(loads, 1);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets(
      'phone directory wraps its filters like the reference at width $width',
      (tester) async {
        await (FontLoader(
          'Roboto',
        )..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))).load();
        await _pump(
          tester,
          DPageHeaderHost(
            identity: 'users',
            titlesInBar: true,
            builder: (context, header, child) => child,
            child: const UsersPage(
              siteUrl: 'https://example.com',
              data: UsersPageData(
                items: [_sam, _hawk],
                columns: [_likes, _replies, _days],
                groupNames: ['design'],
                totalRows: 2,
                loaded: true,
              ),
            ),
          ),
          size: Size(width, 680),
          theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        );

        final search = tester.getRect(
          find.byKey(const ValueKey('users-search')),
        );
        final period = tester.getRect(
          find.byKey(const ValueKey('users-period-filter')),
        );
        final group = tester.getRect(
          find.byKey(const ValueKey('users-group-filter')),
        );
        final columns = tester.getRect(
          find.byKey(const ValueKey('users-columns')),
        );
        // Columns is not a filter: it stays beside them, level with the first
        // line, while the filters wrap among themselves.
        expect(columns.top, search.top);
        expect(columns.right, width - 16);
        // The field keeps 220 before a pill joins its line, then grows into
        // whatever its line has left.
        final room = columns.left - 8 - search.left;
        if (room >= 220 + 8 + period.width) {
          expect(period.top, search.top);
          expect(period.right, columns.left - 8);
          expect(group.top, greaterThan(search.bottom));
          expect(group.left, search.left);
        } else {
          expect(search.right, columns.left - 8);
          expect(period.top, greaterThan(search.bottom));
          expect(period.left, search.left);
          expect(group.top, period.top);
          expect(group.left, period.right + 8);
        }
        expect(find.byKey(const ValueKey('user-row-sam')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('users-columns')));
        await tester.pumpAndSettle();
        expect(find.byType(DDropdownMenuCheckboxItem), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      },
    );
  }

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
      expect(find.bySemanticsLabel('View profile for @sam'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets('the directory title retracts on scroll like the reference', (
    tester,
  ) async {
    await _pump(
      tester,
      UsersPage(
        siteUrl: 'https://example.com',
        data: UsersPageData(
          items: [
            for (var i = 0; i < 200; i++)
              UserDirectoryItem(
                id: i + 1,
                user: UserDirectoryUser(id: i + 1, username: 'user$i'),
                values: {'likes_received': 1000 - i},
              ),
          ],
          columns: const [_likes],
          totalRows: 200,
          loaded: true,
        ),
      ),
      size: const Size(1100, 800),
      theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
    );
    final title = find.text('Users').hitTestable();
    final search = find.byKey(const ValueKey('users-search')).hitTestable();
    final rows = Scrollable.of(
      tester.element(find.byKey(const ValueKey('user-row-user0'))),
      axis: Axis.vertical,
    ).position;
    Future<void> wheel(double amount) async {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byKey(const ValueKey('users-table'))),
          scrollDelta: Offset(0, amount),
        ),
      );
      await tester.pumpAndSettle();
    }

    expect(title, findsOneWidget);
    await wheel(600);
    expect(title, findsNothing);
    expect(search, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await wheel(-160);
    expect(rows.pixels, greaterThan(200));
    expect(title, findsOneWidget);
    rows.jumpTo(0);
    await tester.pumpAndSettle();
    expect(title, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('words a search opened the directory on show as its pill', (
    tester,
  ) async {
    var cleared = 0;
    var data = const UsersPageData(
      items: [_sam],
      columns: [_likes],
      loaded: true,
      query: UserDirectoryQuery(search: 'sam'),
      words: 'sam',
    );
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return UsersPage(
            siteUrl: 'https://example.com',
            data: data,
            onWordsCleared: () => cleared++,
          );
        },
      ),
    );

    final pill = find.byKey(const ValueKey('users-search-words'));
    expect(find.text('“sam” in users'), findsOneWidget);
    expect(
      find.descendant(of: pill, matching: find.text('“sam”')),
      findsOneWidget,
    );
    expect(
      tester.getRect(pill).right,
      lessThan(tester.getRect(find.byKey(const ValueKey('users-search'))).left),
    );
    expect(
      tester
          .widget<DDataTableFilterField>(
            find.byKey(const ValueKey('users-search')),
          )
          .value,
      isEmpty,
    );
    await tester.tap(pill);
    expect(cleared, 1);

    update(
      () => data = const UsersPageData(
        items: [_sam],
        columns: [_likes],
        loaded: true,
        query: UserDirectoryQuery(search: 'sa'),
      ),
    );
    await tester.pump();
    expect(pill, findsNothing);
    expect(find.text('Users'), findsOneWidget);
    expect(
      tester
          .widget<DDataTableFilterField>(
            find.byKey(const ValueKey('users-search')),
          )
          .value,
      'sa',
    );
    expect(tester.takeException(), isNull);
  });

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
    expect(find.text('No users match that filter.'), findsOneWidget);
    expect(find.byType(DSkeletonRegion), findsNothing);
    update(
      () => data = const UsersPageData(
        loaded: true,
        error: "Couldn't load the user directory.",
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('users-error')), findsOneWidget);
    expect(find.byType(DSkeletonRegion), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pagination does not replace the header separator with progress',
    (tester) async {
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

      expect(find.byType(DProgress), findsNothing);
      expect(find.byKey(const ValueKey('user-row-sam')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('directory retains rows without loading indicators', (
    tester,
  ) async {
    await _pump(
      tester,
      const UsersPage(
        siteUrl: 'https://example.com',
        data: UsersPageData(
          items: [_sam],
          columns: [_likes],
          loading: true,
          loaded: true,
        ),
      ),
    );
    expect(find.byType(DProgress), findsNothing);
    expect(find.byKey(const ValueKey('user-row-sam')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reference-width directory lines its filters and columns up with the title',
    (tester) async {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))).load();
      await _pump(
        tester,
        UsersPage(
          siteUrl: 'https://example.com',
          data: const UsersPageData(
            items: [_sam, _hawk],
            columns: [_likes, _replies],
            groupNames: ['staff'],
            loaded: true,
          ),
          onPeriodChanged: (_) {},
          onGroupChanged: (_) {},
        ),
        size: const Size(810, 850),
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
      );
      final title = tester.getRect(find.text('Users'));
      final search = tester.getRect(find.byKey(const ValueKey('users-search')));
      final period = tester.getRect(
        find.byKey(const ValueKey('users-period-filter')),
      );
      final group = tester.getRect(
        find.byKey(const ValueKey('users-group-filter')),
      );
      final columns = tester.getRect(
        find.byKey(const ValueKey('users-columns')),
      );
      expect(title.bottom, lessThan(search.top));
      expect(search.left, title.left);
      expect(search.width, 220);
      expect(period.left, search.right + 8);
      expect(group.left, period.right + 8);
      expect(columns.right, 810 - 16);
      for (final pill in [period, group, columns]) {
        expect(pill.top, search.top);
        expect(pill.height, 30);
      }

      final table = tester.getRect(find.byKey(const ValueKey('users-table')));
      expect(table.left, search.left - 16);
      final header = tester.getRect(find.text('User'));
      final avatar = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('user-row-sam')),
          matching: find.byType(DAvatar),
        ),
      );
      expect(header.left, search.left);
      expect(avatar.left, search.left);
      expect(
        tester.getRect(find.text('Name')).left,
        search.left + _referenceText + 16,
      );
      // A count's label stands over its numbers, at the column's end.
      final likes = tester.getRect(
        find.byKey(ValueKey('user-metric-sam-${_likes.id}')),
      );
      expect(likes.left, search.left + 2 * (_referenceText + 16));
      expect(likes.width, 132);
      expect(
        tester
            .getRect(
              find
                  .ancestor(
                    of: find.text('Likes received'),
                    matching: find.byType(Row),
                  )
                  .first,
            )
            .right,
        likes.right,
      );
      final rows = [
        for (final user in ['sam', 'hawk'])
          tester.getRect(find.byKey(ValueKey('user-row-$user'))),
      ];
      expect(rows[1].center.dy - rows[0].center.dy, 39);
      expect(tester.takeException(), isNull);
    },
  );
}

const double _referenceText = 170;

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
  TextScaler? textScaler,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      builder: textScaler == null
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: child!,
            ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}
