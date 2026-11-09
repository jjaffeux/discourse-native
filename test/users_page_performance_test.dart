import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/users_directory_fixture.dart';

const _layouts = [
  ('phone', Size(393, 852), TargetPlatform.iOS),
  ('desktop', Size(1440, 1000), TargetPlatform.macOS),
];

bool _isBodyCell(Element element) =>
    element.widget is DTableCell && element.widget is! DTableHead;
bool _isPage(Element element) => element.widget is UsersPage;
bool _isTable(Element element) =>
    element.widget is DDataTable<UserDirectoryItem>;

/// Counts rebuilds of the widgets [matches] accepts, for the length of [body].
Future<int> _rebuildsDuring(
  Future<void> Function() body,
  bool Function(Element element) matches,
) async {
  var rebuilds = 0;
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    if (matches(element)) rebuilds++;
  };
  try {
    await body();
  } finally {
    debugOnRebuildDirtyWidget = previous;
  }
  return rebuilds;
}

Finder get _list => find.descendant(
  of: find.byType(DDataTable<UserDirectoryItem>),
  matching: find.byWidgetPredicate((widget) => widget is ListView),
);

ScrollPosition _vertical(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _list, matching: find.byType(Scrollable)).first,
    )
    .position;

void _type(WidgetTester tester, String text) => tester
    .state<EditableTextState>(
      find.descendant(
        of: find.byKey(const ValueKey('users-search')),
        matching: find.byType(EditableText),
      ),
    )
    .updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );

String _fieldText(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('users-search')),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

UsersPageData _pageData(WidgetTester tester) =>
    tester.widget<UsersPage>(find.byType(UsersPage)).data;

final class _ChangingLabelPlugin
    implements SitePlugin, UserDirectoryColumnLabelPlugin {
  String label = 'Cheers';

  @override
  String get name => 'changing-label';

  @override
  String? userDirectoryColumnLabel(
    BuildContext context,
    String siteUrl,
    String columnName,
  ) => columnName == 'likes_received' ? label : null;
}

final class _ChangingLabelModule implements PluginModule {
  const _ChangingLabelModule(this.plugin);

  final _ChangingLabelPlugin plugin;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('changing-label'));

  @override
  void register(PluginRegistrar registrar) => registrar.addCapability(plugin);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (name, size, platform) in _layouts) {
    group('on a $name', () {
      Future<UsersDirectoryFixture> open(WidgetTester tester) async {
        final fixture = await pumpUsersDirectoryFixture(
          tester,
          size: size,
          platform: platform,
        );
        await tester.pumpAndSettle();
        return fixture;
      }

      testWidgets('notifications about something else rebuild no row', (
        tester,
      ) async {
        final fixture = await open(tester);
        final shell = fixture.shell;
        final tab = shell.focusedTabContext;

        final rebuilds = await _rebuildsDuring(() async {
          shell.search.setPageWords(
            usersDirectorySite,
            tab.tabId,
            'other',
            'word',
          );
          await tester.pump();
          await shell.userDirectory.load(
            shell.instanceFor(usersDirectorySite)!,
            query: const UserDirectoryQuery(period: UserDirectoryPeriod.daily),
          );
          await tester.pump();
        }, (element) => _isPage(element) || _isBodyCell(element));

        expect(rebuilds, 0);
      });

      testWidgets('typing in the filter rebuilds only the field', (
        tester,
      ) async {
        await open(tester);

        final rebuilds = await _rebuildsDuring(
          () async {
            _type(tester, 'sam');
            await tester.pump();
          },
          (element) =>
              _isPage(element) || _isTable(element) || _isBodyCell(element),
        );

        expect(rebuilds, 0);
        expect(_fieldText(tester), 'sam');
      });

      testWidgets('asking for the next page rebuilds no row', (tester) async {
        final gate = Completer<void>();
        final fixture = await pumpUsersDirectoryFixture(
          tester,
          size: size,
          platform: platform,
          beforeRead: (path) async {
            if (path.contains('page=1')) await gate.future;
          },
        );
        await tester.pumpAndSettle();
        final position = _vertical(tester);

        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        final rowsBeforeRequest = find
            .byType(DTableCell)
            .evaluate()
            .where((element) => element.widget is! DTableHead)
            .length;
        expect(rowsBeforeRequest, greaterThan(0));

        final rebuilds = await _rebuildsDuring(() async {
          await tester.pump();
          await tester.pump();
        }, _isBodyCell);

        expect(_pageData(tester).loadingMore, isTrue);
        expect(rebuilds, 0);
        gate.complete();
        await tester.pumpAndSettle();
        expect(
          _pageData(tester).items.length,
          usersDirectoryPageSize * 2,
          reason: 'the page ${fixture.api.reads.last} never landed',
        );
      });

      testWidgets('a landing page builds only the rows it adds', (
        tester,
      ) async {
        final gate = Completer<void>();
        await pumpUsersDirectoryFixture(
          tester,
          size: size,
          platform: platform,
          beforeRead: (path) async {
            if (path.contains('page=1')) await gate.future;
          },
        );
        await tester.pumpAndSettle();
        final position = _vertical(tester);

        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        await tester.pump();
        expect(_pageData(tester).loadingMore, isTrue);

        final rebuilds = await _rebuildsDuring(() async {
          gate.complete();
          await tester.pump();
          await tester.pump();
        }, _isBodyCell);

        expect(_pageData(tester).items.length, usersDirectoryPageSize * 2);
        final visibleCells = find
            .byType(DTableCell)
            .evaluate()
            .where((element) => element.widget is! DTableHead)
            .length;
        expect(
          rebuilds,
          lessThan(visibleCells),
          reason: 'rows already on screen were rebuilt for the new page',
        );
      });
    });
  }

  testWidgets('a page that lands above the fold fetches only that page', (
    tester,
  ) async {
    await pumpUsersDirectoryFixture(
      tester,
      size: const Size(430, 1200),
      platform: TargetPlatform.iOS,
    );
    await tester.pumpAndSettle();

    final position = _vertical(tester);
    expect(_pageData(tester).items.length, usersDirectoryPageSize * 2);
    expect(
      position.extentAfter,
      greaterThan(paginationPrefetchDistance(position)),
    );
  });

  testWidgets('controls keep working after an equal route replaces this one', (
    tester,
  ) async {
    final fixture = await pumpUsersDirectoryFixture(
      tester,
      size: const Size(393, 852),
      platform: TargetPlatform.iOS,
    );
    await tester.pumpAndSettle();

    fixture.shell.pushContent(freshUsersDirectoryRoute());
    await tester.pumpAndSettle();
    tester.widget<UsersPage>(find.byType(UsersPage)).onPeriodChanged!(
      UserDirectoryPeriod.monthly,
    );
    await tester.pumpAndSettle();

    expect(_pageData(tester).query.period, UserDirectoryPeriod.monthly);
  });

  testWidgets('a plugin column label follows the next notification', (
    tester,
  ) async {
    final plugin = _ChangingLabelPlugin();
    final fixture = await pumpUsersDirectoryFixture(
      tester,
      size: const Size(1440, 1000),
      platform: TargetPlatform.macOS,
      pluginManifest: PluginManifest([_ChangingLabelModule(plugin)]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cheers'), findsOneWidget);

    plugin.label = 'Score';
    fixture.shell.search.setPageWords(
      usersDirectorySite,
      fixture.shell.focusedTabContext.tabId,
      'other',
      'word',
    );
    await tester.pump();

    expect(find.text('Score'), findsOneWidget);
    expect(find.text('Cheers'), findsNothing);
  });

  testWidgets('rows arrive without waiting for the group filter', (
    tester,
  ) async {
    final groups = Completer<void>();
    final fixture = await pumpUsersDirectoryFixture(
      tester,
      size: const Size(393, 852),
      platform: TargetPlatform.iOS,
      beforeRead: (path) async {
        if (path.startsWith('/groups/')) await groups.future;
      },
    );
    await tester.pumpAndSettle();

    expect(_pageData(tester).items, isNotEmpty);
    expect(_pageData(tester).groupNames, isEmpty);

    groups.complete();
    await tester.pumpAndSettle();

    expect(_pageData(tester).groupNames, ['design']);
    expect(
      fixture.api.reads.where((path) => path.startsWith('/groups/')),
      hasLength(1),
    );
  });

  testWidgets('dragging a column edge rebuilds no cell', (tester) async {
    await pumpUsersDirectoryFixture(
      tester,
      size: const Size(1440, 1000),
      platform: TargetPlatform.macOS,
    );
    await tester.pumpAndSettle();
    final handle = find.byType(DResizableHandle).first;
    final before = tester.getSize(handle);
    final mounted = find.byType(DTableCell).evaluate().toSet();
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();

    final rebuilds = await _rebuildsDuring(() async {
      for (var move = 0; move < 5; move++) {
        await gesture.moveBy(const Offset(4, 0));
        await tester.pump();
      }
    }, (element) => _isBodyCell(element) && mounted.contains(element));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(rebuilds, 0);
    expect(tester.getSize(handle), before);
  });

  testWidgets('a held row repaints for a new theme and for new values', (
    tester,
  ) async {
    const metric = UserDirectoryColumn(
      id: 1,
      name: 'likes_received',
      type: UserDirectoryColumnType.automatic,
      position: 1,
    );
    UserDirectoryItem row(int likes) => UserDirectoryItem(
      id: 1,
      user: const UserDirectoryUser(id: 1, username: 'sam'),
      values: {'likes_received': likes},
    );
    const peer = UserDirectoryItem(
      id: 2,
      user: UserDirectoryUser(id: 2, username: 'hawk'),
      values: {'likes_received': 400},
    );
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late StateSetter update;
    var brightness = Brightness.light;
    var data = UsersPageData(
      loaded: true,
      columns: const [metric],
      items: [row(20), peer],
    );
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return MaterialApp(
            theme: AppTheme.forBrightness(brightness),
            home: Scaffold(
              body: UsersPage(siteUrl: 'https://example.com', data: data),
            ),
          );
        },
      ),
    );
    await tester.pump();
    expect(find.text('20'), findsOneWidget);

    Color barColor() => tester
        .widget<DChartBar>(
          find
              .descendant(
                of: find.byKey(const ValueKey('user-metric-sam-1')),
                matching: find.byType(DChartBar),
              )
              .first,
        )
        .color!;
    final lightColor = barColor();
    update(() => brightness = Brightness.dark);
    await tester.pumpAndSettle();
    expect(barColor(), isNot(lightColor));

    update(() {
      data = UsersPageData(
        loaded: true,
        columns: const [metric],
        items: [row(35), peer],
      );
    });
    await tester.pump();
    expect(find.text('35'), findsOneWidget);
    expect(find.text('20'), findsNothing);
  });
}
