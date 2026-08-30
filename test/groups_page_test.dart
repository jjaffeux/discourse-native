import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/shell/groups_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
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
  testWidgets('directory exposes new group and type dropdown', (tester) async {
    String? search;
    String? type = 'unset';
    Group? opened;
    var loadMore = 0;
    var createGroup = 0;

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
          canCreateGroup: true,
        ),
        onSearchChanged: (value) => search = value,
        onTypeChanged: (value) => type = value,
        onOpenGroup: (value) => opened = value,
        onLoadMore: () => loadMore++,
        onCreateGroup: () => createGroup++,
      ),
    );

    expect(find.byKey(const ValueKey('group-card-support')), findsOneWidget);
    expect(find.text('Support Team'), findsOneWidget);
    expect(find.text('12 members'), findsOneWidget);

    final searchField = tester.widget<TextField>(
      find.byKey(const ValueKey('groups-search')),
    );
    expect(searchField.autofocus, isTrue);
    expect(searchField.focusNode?.hasFocus, isTrue);
    expect(searchField.decoration?.labelText, isNull);
    expect(searchField.decoration?.hintText, 'Search groups');
    expect(searchField.decoration?.border, isA<OutlineInputBorder>());
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('groups-search')),
        matching: find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.magnifyingGlass,
        ),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('groups-search')),
      '  support  ',
    );
    await tester.pump(const Duration(milliseconds: 301));
    expect(search, 'support');

    expect(find.text('Groups'), findsNothing);
    expect(find.text('2 groups'), findsNothing);
    expect(find.byKey(const ValueKey('groups-order')), findsNothing);
    expect(find.byKey(const ValueKey('groups-order-direction')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('groups-type-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(('choice-menu-option', 'my'))));
    await tester.pumpAndSettle();
    expect(type, 'my');

    await tester.tap(find.byKey(const ValueKey('create-group')));
    expect(createGroup, 1);

    await tester.tap(find.byKey(const ValueKey('group-card-support')));
    expect(opened, same(_support));

    await tester.ensureVisible(find.byKey(const ValueKey('groups-load-more')));
    await tester.tap(find.byKey(const ValueKey('groups-load-more')));
    expect(loadMore, greaterThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('type dropdown clears back to all groups on compact layouts', (
    tester,
  ) async {
    String? type = 'automatic';
    await _pump(
      tester,
      GroupsPage(
        siteUrl: 'https://meta.discourse.org',
        data: const GroupsPageData(
          typeFilters: ['my', 'automatic'],
          type: 'automatic',
          loaded: true,
          canCreateGroup: true,
        ),
        onTypeChanged: (value) => type = value,
        onCreateGroup: () {},
      ),
      size: const Size(390, 700),
    );

    expect(find.text('Automatic groups'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('groups-type-filter')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey(('choice-menu-option', '__all_group_types__'))),
    );
    await tester.pumpAndSettle();

    expect(type, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wide directory controls use the available width and matching heights',
    (tester) async {
      await _pump(
        tester,
        GroupsPage(
          siteUrl: 'https://meta.discourse.org',
          data: const GroupsPageData(
            typeFilters: ['my', 'public'],
            loaded: true,
            canCreateGroup: true,
          ),
          onTypeChanged: (_) {},
          onCreateGroup: () {},
        ),
        size: const Size(1400, 760),
      );

      final searchRect = tester.getRect(
        find.byKey(const ValueKey('groups-search')),
      );
      final filterRect = tester.getRect(
        find.byKey(const ValueKey('groups-type-filter')),
      );
      final createRect = tester.getRect(
        find.byKey(const ValueKey('create-group')),
      );

      expect(searchRect.left, 16);
      expect(createRect.right, 1384);
      expect(filterRect.height, createRect.height);
      expect(tester.takeException(), isNull);
    },
  );

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
