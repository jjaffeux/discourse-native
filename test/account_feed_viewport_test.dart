import 'package:discourse_native/src/shell/account_feed_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'keeps the visible anchor through both window edges at $scale',
      (tester) async {
        final rows = ValueNotifier([for (var i = 0; i < 60; i++) i]);
        addTearDown(rows.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: ValueListenableBuilder<List<int>>(
                valueListenable: rows,
                builder: (context, ids, _) => _viewport(ids),
              ),
            ),
          ),
        );
        final viewport = tester.state<AccountFeedViewportState>(
          find.byType(AccountFeedViewport),
        );
        viewport.listController.jumpToItem(
          index: 40,
          scrollController: viewport.scrollController,
          alignment: 0,
        );
        await tester.pumpAndSettle();
        final before = tester.getTopLeft(find.text('Row 40')).dy;
        rows.value = [for (var i = 30; i < 90; i++) i];
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.text('Row 40')).dy, closeTo(before, 1));
        rows.value = [for (var i = 0; i < 60; i++) i];
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.text('Row 40')).dy, closeTo(before, 1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('replacement identity and disposal cancel anchor restoration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: _viewport([for (var i = 0; i < 60; i++) i])),
    );
    final viewport = tester.state<AccountFeedViewportState>(
      find.byType(AccountFeedViewport),
    );
    viewport.listController.jumpToItem(
      index: 40,
      scrollController: viewport.scrollController,
      alignment: 0,
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(home: _viewport([for (var i = 30; i < 90; i++) i])),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: _viewport([
          for (var i = 30; i < 90; i++) i,
        ], identity: 'other-account'),
      ),
    );
    await tester.pumpAndSettle();
    expect(viewport.scrollController.offset, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a disjoint response window reveals its first row', (
    tester,
  ) async {
    final rows = ValueNotifier([for (var i = 0; i < 30; i++) i]);
    addTearDown(rows.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<List<int>>(
          valueListenable: rows,
          builder: (context, ids, _) => _viewport(ids),
        ),
      ),
    );
    final viewport = tester.state<AccountFeedViewportState>(
      find.byType(AccountFeedViewport),
    );
    viewport.scrollController.jumpTo(
      viewport.scrollController.position.maxScrollExtent,
    );
    await tester.pumpAndSettle();
    rows.value = [for (var i = 30; i < 60; i++) i];
    await tester.pumpAndSettle();
    expect(find.text('Row 30').hitTestable(), findsOneWidget);
    expect(viewport.scrollController.offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a disjoint previous window reveals its trailing row', (
    tester,
  ) async {
    final rows = ValueNotifier([for (var i = 30; i < 60; i++) i]);
    addTearDown(rows.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<List<int>>(
          valueListenable: rows,
          builder: (context, ids, _) => _viewport(ids, revealEnd: true),
        ),
      ),
    );
    rows.value = [for (var i = 0; i < 30; i++) i];
    await tester.pumpAndSettle();
    expect(find.text('Row 29').hitTestable(), findsOneWidget);
    final viewport = tester.state<AccountFeedViewportState>(
      find.byType(AccountFeedViewport),
    );
    expect(
      viewport.scrollController.offset,
      closeTo(viewport.scrollController.position.maxScrollExtent, 1),
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _viewport(
  List<int> rows, {
  Object identity = 'account',
  bool revealEnd = false,
}) => AccountFeedViewport(
  identity: identity,
  rows: rows,
  revealEnd: revealEnd,
  builder: (context, viewport) => CustomScrollView(
    controller: viewport.scrollController,
    slivers: [
      SuperSliverList.builder(
        listController: viewport.listController,
        findChildIndexCallback: viewport.indexForKey,
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final id = rows[index];
          return viewport.row(
            id,
            SizedBox(
              height:
                  (80 + (id % 3) * 24) *
                  MediaQuery.textScalerOf(context).scale(1),
              child: Text('Row $id'),
            ),
          );
        },
      ),
    ],
  ),
);
