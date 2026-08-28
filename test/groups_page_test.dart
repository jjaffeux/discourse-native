import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/shell/groups_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _support = Group(
  id: 1,
  name: 'support',
  fullName: 'Support Team',
  userCount: 12,
  bioCooked: '<p>People who help the community.</p>',
  isGroupUser: true,
);

const _moderators = Group(
  id: 2,
  name: 'moderators',
  fullName: 'Moderators',
  userCount: 4,
  bioExcerpt: 'Forum moderators',
  isGroupOwner: true,
);

void main() {
  testWidgets('directory exposes search, type, ordering, paging and cards', (
    tester,
  ) async {
    String? search;
    String? type = 'unset';
    GroupDirectoryOrder? order;
    bool? ascending;
    Group? opened;
    var loadMore = 0;

    await _pump(
      tester,
      GroupsPage(
        siteUrl: 'https://meta.discourse.org',
        data: const GroupsPageData(
          groups: [_support, _moderators],
          typeFilters: ['my', 'public'],
          totalRows: 2,
          loaded: true,
          hasMore: true,
        ),
        onSearchChanged: (value) => search = value,
        onTypeChanged: (value) => type = value,
        onOrderChanged: (value) => order = value,
        onAscendingChanged: (value) => ascending = value,
        onOpenGroup: (value) => opened = value,
        onLoadMore: () => loadMore++,
      ),
    );

    expect(find.byKey(const ValueKey('group-card-support')), findsOneWidget);
    expect(find.text('Support Team'), findsOneWidget);
    expect(find.text('12 members'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('groups-search')),
      '  support  ',
    );
    await tester.pump(const Duration(milliseconds: 301));
    expect(search, 'support');

    await tester.tap(find.byKey(const ValueKey('group-type-my')));
    expect(type, 'my');

    await tester.tap(find.byKey(const ValueKey('groups-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Members').last);
    await tester.pumpAndSettle();
    expect(order, GroupDirectoryOrder.memberCount);

    await tester.tap(find.byKey(const ValueKey('groups-order-direction')));
    expect(ascending, isFalse);

    await tester.tap(find.byKey(const ValueKey('group-card-support')));
    expect(opened, same(_support));

    await tester.ensureVisible(find.byKey(const ValueKey('groups-load-more')));
    await tester.tap(find.byKey(const ValueKey('groups-load-more')));
    expect(loadMore, greaterThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty filtered directory is a stable scrollable state', (
    tester,
  ) async {
    await _pump(
      tester,
      const GroupsPage(
        siteUrl: 'https://meta.discourse.org',
        data: GroupsPageData(loaded: true, query: 'missing'),
      ),
      size: const Size(390, 700),
    );

    expect(find.text('No groups match these filters.'), findsOneWidget);
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1000, 760),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}
