import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/shell/groups_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

const _weeklyFocus = Group(
  id: 3,
  name: 'weekly-focus-dev',
  fullName: 'Dev Weekly Focus Roster',
  userCount: 3,
  bioExcerpt:
      'Used in the Dev Weekly Focus automation to automatically assign '
      'managers to write a new post.',
  isGroupOwner: true,
);

const _design = Group(id: 4, name: 'design', userCount: 8);

void main() {
  for (final (width, columns, platform) in [
    (390.0, 1, TargetPlatform.macOS),
    (700.0, 2, TargetPlatform.macOS),
    (1100.0, 2, TargetPlatform.macOS),
    (1100.0, 3, TargetPlatform.android),
  ]) {
    testWidgets(
      'cards fit their content in $columns masonry columns at width $width',
      (tester) async {
        const groups = [_weeklyFocus, _design, _support, _moderators];
        Group? opened;
        await _pump(
          tester,
          GroupsPage(
            siteUrl: 'https://meta.discourse.org',
            data: const GroupsPageData(groups: groups, loaded: true),
            onOpenGroup: (group) => opened = group,
          ),
          size: Size(width, 1000),
        );

        final cards = [
          for (final group in groups)
            tester.getRect(find.byKey(ValueKey('group-card-${group.name}'))),
        ];
        expect(cards[0].height, greaterThan(cards[1].height));
        for (var i = 0; i < cards.length; i++) {
          expect(cards[i].width, cards[0].width);
          for (var j = i + 1; j < cards.length; j++) {
            expect(cards[i].overlaps(cards[j]), isFalse);
          }
        }

        if (columns == 1) {
          expect(cards[1].left, cards[0].left);
          expect(cards[1].top, closeTo(cards[0].bottom + 12, 0.01));
        } else {
          expect(cards[1].top, cards[0].top);
          expect(cards[1].left, greaterThan(cards[0].right));
          expect(cards[columns].left, cards[1].left);
          expect(cards[columns].top, closeTo(cards[1].bottom + 12, 0.01));
          expect(cards[columns].top, lessThan(cards[0].bottom + 12));
        }

        final description = tester.getRect(find.text(_weeklyFocus.bioExcerpt!));
        final members = tester.getRect(find.text('3 members'));
        expect(members.top - description.bottom, greaterThanOrEqualTo(16));
        expect(find.text('No group description.'), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('group-card-weekly-focus-dev')),
        );
        expect(opened, same(_weeklyFocus));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets(
    'masonry supports scrolling, pagination, resizing, and filtering',
    (tester) async {
      final groups = [
        for (var i = 0; i < 80; i++)
          Group(
            id: i,
            name: 'group-$i',
            userCount: i,
            bioExcerpt: i.isEven ? _weeklyFocus.bioExcerpt : null,
          ),
      ];
      var data = GroupsPageData(
        groups: groups.take(60).toList(),
        loaded: true,
        hasMore: true,
      );
      var loadMore = 0;
      Group? opened;
      late StateSetter update;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return GroupsPage(
              siteUrl: 'https://meta.discourse.org',
              data: data,
              onLoadMore: () => loadMore++,
              onOpenGroup: (group) => opened = group,
            );
          },
        ),
        size: const Size(700, 760),
      );
      final scrollable = find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first;

      expect(find.byKey(const ValueKey('group-card-group-59')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('group-card-group-59')),
        500,
        scrollable: scrollable,
        maxScrolls: 50,
      );
      expect(loadMore, greaterThan(0));

      update(() => data = GroupsPageData(groups: groups, loaded: true));
      await tester.pump();
      tester.view.physicalSize = const Size(390, 760);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('group-card-group-79')),
        500,
        scrollable: scrollable,
        maxScrolls: 50,
      );
      await tester.tap(find.byKey(const ValueKey('group-card-group-79')));
      expect(opened, same(groups.last));

      tester.view.physicalSize = const Size(1100, 760);
      await tester.pumpAndSettle();
      update(() {
        data = GroupsPageData(groups: [groups.last], loaded: true);
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('group-card-group-79')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      _primaryFocusIsWithin(find.byKey(const ValueKey('groups-type-filter'))),
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      _primaryFocusIsWithin(find.byKey(const ValueKey('create-group'))),
      isTrue,
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
      expect(searchRect.height, filterRect.height);
      expect(searchRect.height, createRect.height);
      expect(filterRect.height, createRect.height);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search stays mounted while only directory results update', (
    tester,
  ) async {
    var data = const GroupsPageData(groups: [_support], loaded: true);
    late StateSetter update;

    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return GroupsPage(
            siteUrl: 'https://meta.discourse.org',
            data: data,
            onSearchChanged: (_) {},
          );
        },
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('groups-search')),
      'moderators',
    );
    final editable = tester.state<EditableTextState>(
      find.descendant(
        of: find.byKey(const ValueKey('groups-search')),
        matching: find.byType(EditableText),
      ),
    );

    update(() {
      data = const GroupsPageData(query: 'moderators', loading: true);
    });
    await tester.pump();

    expect(find.byKey(const ValueKey('groups-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('groups-loading')), findsOneWidget);
    expect(
      tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const ValueKey('groups-search')),
          matching: find.byType(EditableText),
        ),
      ),
      same(editable),
    );
    expect(editable.widget.controller.text, 'moderators');
    expect(editable.widget.focusNode.hasFocus, isTrue);

    update(() {
      data = const GroupsPageData(
        groups: [_moderators],
        query: 'moderators',
        loaded: true,
      );
    });
    await tester.pump();

    expect(find.byKey(const ValueKey('groups-loading')), findsNothing);
    expect(find.byKey(const ValueKey('group-card-moderators')), findsOneWidget);
    expect(
      tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const ValueKey('groups-search')),
          matching: find.byType(EditableText),
        ),
      ),
      same(editable),
    );
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

bool _primaryFocusIsWithin(Finder finder) {
  final focusedContext = FocusManager.instance.primaryFocus?.context;
  if (focusedContext == null) return false;
  final targets = finder.evaluate().toSet();
  if (targets.contains(focusedContext)) return true;
  var matches = false;
  focusedContext.visitAncestorElements((ancestor) {
    if (!targets.contains(ancestor)) return true;
    matches = true;
    return false;
  });
  return matches;
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
