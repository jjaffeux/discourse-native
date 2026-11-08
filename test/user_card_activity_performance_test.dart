import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/src/models/user_activity_feed.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/shell/user_activity.dart';
import 'package:discourse_native/src/shell/user_card_header.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/user_card_activity_fixture.dart';

const _surface = ValueKey('user-card-surface');
const _pageSize = 30;

final _rows = find.byType(UserActivityRow);

void _phone(WidgetTester tester, {Size size = const Size(393, 852)}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
  tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
  addTearDown(tester.view.reset);
}

Future<void> _openCard(WidgetTester tester) async {
  await tester.tap(find.text('Open card'));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Future<ScrollPosition> _raise(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const ValueKey('sheet-drag-handle')),
    const Offset(0, -700),
  );
  await tester.pumpAndSettle();
  return tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(_surface),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;
}

Future<void> _scrollUntil(
  WidgetTester tester,
  ScrollPosition position,
  bool Function() reached,
) async {
  for (var step = 0; step < 800 && !reached(); step++) {
    // Resting exactly on the end would never ask for the next page again.
    final end = position.maxScrollExtent;
    position.jumpTo(
      position.pixels >= end ? end - 1 : math.min(position.pixels + 120, end),
    );
    await tester.pump();
  }
  expect(reached(), isTrue, reason: 'scrolling never got there');
}

Iterable<UserActivityRow> _builtRows() =>
    _rows.evaluate().map((element) => element.widget as UserActivityRow);

/// Counts rebuilds of the widgets [matches] accepts, for the length of [body].
Future<int> _rebuildsDuring(
  Future<void> Function() body, {
  bool Function(Widget widget)? matches,
}) async {
  var rebuilds = 0;
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    if (matches == null || matches(element.widget)) rebuilds++;
  };
  try {
    await body();
  } finally {
    debugOnRebuildDirtyWidget = previous;
  }
  return rebuilds;
}

bool _isRow(Widget widget) => widget is UserActivityRow;

void main() {
  testWidgets('a resting card builds only the rows that outgrow its sheet', (
    tester,
  ) async {
    _phone(tester);
    await pumpUserCardActivityFixture(tester);
    await _openCard(tester);
    await tester.pumpAndSettle();

    final built = _rows.evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(_pageSize));
    expect(tester.takeException(), isNull);
  });

  testWidgets('arriving activity spreads its rows without moving the card', (
    tester,
  ) async {
    _phone(tester);
    final gate = Completer<void>();
    await pumpUserCardActivityFixture(tester, beforePage: () => gate.future);
    await _openCard(tester);
    final name = find.text('Sam Example');

    gate.complete();
    var built = 0;
    double? settled;
    for (var frame = 0; frame < 15; frame++) {
      await tester.pump();
      final next = _rows.evaluate().length;
      expect(next - built, lessThanOrEqualTo(1));
      built = next;
      // The frame the feed lands in replaces the skeleton and moves the rest
      // line once; after that, filling must move nothing.
      if (frame < 3) continue;
      settled ??= tester.getTopLeft(name).dy;
      expect(tester.getTopLeft(name).dy, closeTo(settled, 1));
    }
    expect(built, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a history too short to fill the sheet lays out at once', (
    tester,
  ) async {
    _phone(tester);
    final gate = Completer<void>();
    await pumpUserCardActivityFixture(
      tester,
      items: 3,
      beforePage: () => gate.future,
    );
    await _openCard(tester);

    gate.complete();
    await tester.pump();
    await tester.pump();

    expect(_rows, findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scrolling reaches every row across pages and releases old ones',
    (tester) async {
      _phone(tester);
      final fixture = await pumpUserCardActivityFixture(tester);
      await _openCard(tester);
      final position = await _raise(tester);
      expect(fixture.api.userActivityRequests, hasLength(1));

      final seen = <int>{};
      var mostBuilt = 0;
      await _scrollUntil(tester, position, () {
        seen.addAll(_builtRows().map((row) => row.item.topicId));
        mostBuilt = math.max(mostBuilt, _rows.evaluate().length);
        return seen.contains(1089);
      });

      expect(seen, {for (var id = 0; id < 90; id++) 1000 + id});
      expect(mostBuilt, lessThan(_pageSize));
      expect(
        _builtRows().map((row) => row.item.topicId),
        isNot(contains(1000)),
      );
      expect(
        fixture.api.userActivityRequests.map((request) => request.offset),
        containsAllInOrder([0, _pageSize, 2 * _pageSize]),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a page in flight and its arrival leave built rows alone', (
    tester,
  ) async {
    _phone(tester);
    var gate = Completer<void>()..complete();
    final fixture = await pumpUserCardActivityFixture(
      tester,
      beforePage: () => gate.future,
    );
    await _openCard(tester);
    await _raise(tester);
    expect(_rows.evaluate(), isNotEmpty);

    gate = Completer<void>();
    final inFlight = await _rebuildsDuring(() async {
      unawaited(
        fixture.shell.accountActivity.loadUserActivity(
          fixture.shell.instances.single,
          username: 'sam',
          loadMore: true,
        ),
      );
      await tester.pump();
    }, matches: _isRow);
    expect(inFlight, 0, reason: 'the loading flag changes no row');

    final arrival = await _rebuildsDuring(() async {
      gate.complete();
      await tester.pump();
      await tester.pump();
    }, matches: _isRow);
    expect(arrival, 0, reason: 'a page beyond the viewport builds no row');
    expect(
      fixture.shell.accountActivity
          .userActivityFor(userCardActivitySite, username: 'sam')
          .items,
      hasLength(2 * _pageSize),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dropping old pages keeps the row being read in place', (
    tester,
  ) async {
    _phone(tester);
    var gate = Completer<void>()..complete();
    final fixture = await pumpUserCardActivityFixture(
      tester,
      items: 400,
      beforePage: () => gate.future,
    );
    await _openCard(tester);
    final position = await _raise(tester);
    final requests = fixture.api.userActivityRequests;
    await _scrollUntil(tester, position, () => requests.length >= 10);
    await tester.pump();
    gate = Completer<void>();
    UserActivityFeed feed() => fixture.shell.accountActivity.userActivityFor(
      userCardActivitySite,
      username: 'sam',
    );
    await _scrollUntil(tester, position, () => feed().loading);
    await tester.pump();

    final reading = _rows.at(_rows.evaluate().length ~/ 2);
    final id = tester.widget<UserActivityRow>(reading).item.identity;
    final held = find.byWidgetPredicate(
      (widget) => widget is UserActivityRow && widget.item.identity == id,
    );
    final before = tester.getTopLeft(held).dy;

    gate.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(feed().hasPrevious, isTrue, reason: 'the oldest page was dropped');
    expect(held, findsOneWidget);
    expect(tester.getTopLeft(held).dy, closeTo(before, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling does not repaint rows it has already drawn', (
    tester,
  ) async {
    _phone(tester);
    await pumpUserCardActivityFixture(tester);
    await _openCard(tester);
    final position = await _raise(tester);
    position.jumpTo(800);
    await tester.pumpAndSettle();

    var paintedTitles = 0;
    debugProfilePaintsEnabled = true;
    debugOnProfilePaint = (object) {
      if (object is RenderParagraph &&
          object.text.toPlainText().startsWith('Discussion')) {
        paintedTitles++;
      }
    };
    try {
      for (var frame = 0; frame < 5; frame++) {
        position.jumpTo(position.pixels + 2);
        await tester.pump();
      }
    } finally {
      debugProfilePaintsEnabled = false;
      debugOnProfilePaint = null;
    }

    expect(paintedTitles, lessThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a request for another card leaves the open card alone', (
    tester,
  ) async {
    _phone(tester);
    final fixture = await pumpUserCardActivityFixture(tester);
    await _openCard(tester);
    await tester.pumpAndSettle();

    final rebuilds = await _rebuildsDuring(() async {
      fixture.shell.userCardRequests.begin(userCardActivitySite, 'someone');
      await tester.pump();
      fixture.shell.userCardRequests.finish(userCardActivitySite, 'someone');
      await tester.pump();
    });

    expect(rebuilds, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a refreshed card redraws the card but not its activity', (
    tester,
  ) async {
    _phone(tester);
    final fixture = await pumpUserCardActivityFixture(tester);
    await _openCard(tester);
    await tester.pumpAndSettle();

    var headers = 0;
    final rows = await _rebuildsDuring(
      () async {
        fixture.shell.store.put(
          userCardActivitySite,
          UserCard(
            username: 'sam',
            name: 'Sam Renamed',
            title: userCardActivityProfile.title,
            bioExcerpt: userCardActivityProfile.bioExcerpt,
            location: userCardActivityProfile.location,
            timeRead: userCardActivityProfile.timeRead,
            badgeCount: userCardActivityProfile.badgeCount,
          ),
        );
        await tester.pump();
      },
      matches: (widget) {
        if (widget is UserCardHeader) headers++;
        return _isRow(widget);
      },
    );

    expect(find.text('Sam Renamed'), findsWidgets);
    expect(headers, greaterThan(0));
    expect(rows, 0);
    expect(tester.takeException(), isNull);
  });
}
