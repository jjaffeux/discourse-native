import 'dart:async';
import 'dart:math' as math;

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

Future<void> _buildEveryRow(
  WidgetTester tester,
  ScrollPosition position,
  int rows,
) async {
  while (_rows.evaluate().length < rows) {
    position.jumpTo(math.min(position.pixels + 200, position.maxScrollExtent));
    await tester.pump();
  }
}

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

bool _isFirstPageRow(Widget widget) =>
    widget is UserActivityRow && widget.item.topicId < 1000 + _pageSize;

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
    await tester.pump();
    await tester.pump();
    await tester.pump();
    final settling = tester.getTopLeft(name).dy;

    var built = _rows.evaluate().length;
    expect(built, lessThanOrEqualTo(3));
    while (built < 8) {
      await tester.pump();
      final next = _rows.evaluate().length;
      expect(next - built, lessThanOrEqualTo(1));
      built = next;
      expect(tester.getTopLeft(name).dy, closeTo(settling, 1));
    }
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

  testWidgets('a tall sheet keeps building rows until it can scroll', (
    tester,
  ) async {
    _phone(tester, size: const Size(1024, 1600));
    await pumpUserCardActivityFixture(tester);
    await _openCard(tester);
    await tester.pumpAndSettle();

    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(_surface),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    expect(position.extentAfter, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('every row of a page is reachable before the next page loads', (
    tester,
  ) async {
    _phone(tester);
    final fixture = await pumpUserCardActivityFixture(tester);
    await _openCard(tester);
    final position = await _raise(tester);
    expect(fixture.api.userActivityRequests, hasLength(1));

    while (fixture.api.userActivityRequests.length < 2) {
      position.jumpTo(
        math.min(position.pixels + 200, position.maxScrollExtent),
      );
      await tester.pump();
      if (fixture.api.userActivityRequests.length < 2) {
        expect(_rows.evaluate().length, lessThanOrEqualTo(_pageSize));
      }
    }

    expect(_rows.evaluate().length, greaterThanOrEqualTo(_pageSize));
    expect(fixture.api.userActivityRequests.last.offset, _pageSize);
    expect(find.text('Load more'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a page in flight and its arrival leave built rows alone', (
    tester,
  ) async {
    _phone(tester);
    var gate = Completer<void>()..complete();
    await pumpUserCardActivityFixture(tester, beforePage: () => gate.future);
    await _openCard(tester);
    final position = await _raise(tester);
    await _buildEveryRow(tester, position, _pageSize);

    gate = Completer<void>();
    final beforeRequest = position.pixels;
    final inFlight = await _rebuildsDuring(() async {
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
    }, matches: _isFirstPageRow);
    expect(position.pixels, greaterThan(beforeRequest));
    expect(inFlight, 0, reason: 'the loading flag changes no row');

    final arrival = await _rebuildsDuring(() async {
      gate.complete();
      await tester.pump();
      await tester.pump();
    }, matches: _isFirstPageRow);
    expect(arrival, 0, reason: 'a new page builds only rows that are new');
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling does not repaint rows it has already drawn', (
    tester,
  ) async {
    _phone(tester);
    await pumpUserCardActivityFixture(tester);
    await _openCard(tester);
    final position = await _raise(tester);
    await _buildEveryRow(tester, position, 20);
    position.jumpTo(100);
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
        position.jumpTo(position.pixels + 40);
        await tester.pump();
      }
    } finally {
      debugProfilePaintsEnabled = false;
      debugOnProfilePaint = null;
    }

    expect(paintedTitles, 0);
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
          const UserCard(username: 'sam', name: 'Sam Renamed'),
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
