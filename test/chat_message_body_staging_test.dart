import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_body_staging.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_scroll_fixture.dart';

void main() {
  group('chatBodyStagingFor', () {
    (double, bool) measured(int row) => (120.0, false);
    (double, bool) estimated(int row) => (80.0, true);

    test('defers a row entering from history without a hold', () {
      expect(
        chatBodyStagingFor(
          row: 12,
          direction: ScrollDirection.reverse,
          visibleRange: (4, 11),
          extentForIndex: estimated,
        ),
        (followsFrame: true, reservedHeight: null),
      );
    });

    test('holds the measured height of a row entering from the present', () {
      expect(
        chatBodyStagingFor(
          row: 3,
          direction: ScrollDirection.forward,
          visibleRange: (4, 11),
          extentForIndex: measured,
        ),
        (followsFrame: true, reservedHeight: 120.0),
      );
    });

    test('builds an unmeasured row entering from the present at once', () {
      expect(
        chatBodyStagingFor(
          row: 3,
          direction: ScrollDirection.forward,
          visibleRange: (4, 11),
          extentForIndex: estimated,
        ),
        chatBodyAtOnce,
      );
    });

    test('builds at once when idle or inside the visible rows', () {
      for (final (row, direction) in [
        (12, ScrollDirection.idle),
        (3, ScrollDirection.idle),
        // A live arrival at the present while the reader scrolls history.
        (0, ScrollDirection.reverse),
        (12, ScrollDirection.forward),
        (8, ScrollDirection.reverse),
      ]) {
        expect(
          chatBodyStagingFor(
            row: row,
            direction: direction,
            visibleRange: (4, 11),
            extentForIndex: measured,
          ),
          chatBodyAtOnce,
          reason: '$row $direction',
        );
      }
      expect(
        chatBodyStagingFor(
          row: 12,
          direction: ScrollDirection.reverse,
          visibleRange: null,
          extentForIndex: measured,
        ),
        chatBodyAtOnce,
      );
    });
  });

  testWidgets('rows first built while dragging into history mount their body '
      'a frame later without moving the visible rows', (tester) async {
    final controller = await _mount(tester);
    addTearDown(controller.dispose);
    for (final id in _tiles(tester).keys) {
      expect(_hasBody(tester, id), isTrue, reason: 'initial row $id');
    }

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DMessageScrollerViewport)),
    );
    var landed = 0;
    // Rows whose landing body made them taller: the case that would move
    // visible rows if the transcript anchored them wrongly.
    var grew = 0;
    for (var step = 0; step < 60 && grew < 4; step++) {
      final known = _tiles(tester).keys.toSet();
      // Fingers moving down pull older messages in from the top.
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 16));
      final staged = [
        for (final id in _tiles(tester).keys)
          if (!known.contains(id) && !_hasBody(tester, id)) id,
      ];
      if (staged.isEmpty) continue;
      final visible = _visibleRects(tester, except: staged);
      final heights = {for (final id in staged) id: _rowHeight(tester, id)};
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      for (final id in staged) {
        expect(_hasBody(tester, id), isTrue, reason: 'row $id landed');
        if (_rowHeight(tester, id) > heights[id]!) grew++;
        landed++;
      }
      expect(_visibleRects(tester, except: staged), visible);
    }
    await gesture.up();
    expect(grew, greaterThanOrEqualTo(4), reason: '$landed rows landed');
  });

  testWidgets('a released row scrolled back toward the present holds its '
      'measured height until its body lands', (tester) async {
    final controller = await _mount(tester);
    addTearDown(controller.dispose);
    final firstIds = _tiles(tester).keys.toSet();

    final away = await tester.startGesture(
      tester.getCenter(find.byType(DMessageScrollerViewport)),
    );
    for (var step = 0; step < 120; step++) {
      await away.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await away.up();
    await _settle(tester);
    expect(
      _tiles(tester).keys.toSet().intersection(firstIds),
      isEmpty,
      reason: 'the newest rows were released',
    );

    final back = await tester.startGesture(
      tester.getCenter(find.byType(DMessageScrollerViewport)),
    );
    var held = 0;
    for (var step = 0; step < 160 && held < 3; step++) {
      final known = _tiles(tester).keys.toSet();
      await back.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 16));
      final staged = [
        for (final id in _tiles(tester).keys)
          if (!known.contains(id) && !_hasBody(tester, id)) id,
      ];
      if (staged.isEmpty) continue;
      final visible = _visibleRects(tester, except: staged);
      final heights = {for (final id in staged) id: _rowHeight(tester, id)};
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      for (final id in staged) {
        expect(_hasBody(tester, id), isTrue, reason: 'row $id landed');
        expect(_rowHeight(tester, id), closeTo(heights[id]!, .01));
        held++;
      }
      expect(_visibleRects(tester, except: staged), visible);
    }
    await back.up();
    expect(held, greaterThanOrEqualTo(3));
  });
}

Future<ShellController> _mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = await chatScrollController(count: 120);
  await tester.pumpWidget(ChatScrollFixture(controller: controller));
  await _settle(tester);
  return controller;
}

Future<void> _settle(WidgetTester tester) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (!tester.binding.hasScheduledFrame) return;
  }
  throw StateError('Chat did not settle');
}

Map<int, Element> _tiles(WidgetTester tester) => {
  for (final element
      in find.byType(ChatMessageTile, skipOffstage: false).evaluate())
    (element.widget as ChatMessageTile).messageId: element,
};

bool _hasBody(WidgetTester tester, int id) {
  final text = RegExp('\\bMessage $id\\b');
  return find
      .descendant(
        of: find.byElementPredicate(
          (element) => identical(element, _tiles(tester)[id]),
          skipOffstage: false,
        ),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is RichText && text.hasMatch(widget.text.toPlainText()),
          skipOffstage: false,
        ),
        skipOffstage: false,
      )
      .evaluate()
      .isNotEmpty;
}

/// The extent the transcript lays the row out at, including any hold.
double _rowHeight(WidgetTester tester, int id) {
  Element? staging;
  _tiles(tester)[id]!.visitAncestorElements((ancestor) {
    if (ancestor.widget is! ChatMessageBodyStaging) return true;
    staging = ancestor;
    return false;
  });
  return (staging!.renderObject! as RenderBox).size.height;
}

Map<int, Rect> _visibleRects(WidgetTester tester, {required List<int> except}) {
  final viewport = tester.getRect(find.byType(DMessageScrollerViewport));
  return {
    for (final element in find.byType(ChatMessageTile).evaluate())
      if ((element.widget as ChatMessageTile).messageId case final id
          when !except.contains(id))
        if (_rectOf(element) case final rect
            when rect.top >= viewport.top && rect.bottom <= viewport.bottom)
          id: rect,
  };
}

Rect _rectOf(Element element) {
  final box = element.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}
