import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a round screen gets a full-width bar down to its foot', () {
    const geometry = DMobileDockGeometry(foot: 34);
    expect(geometry.margin, const EdgeInsetsDirectional.fromSTEB(0, 6, 0, 0));
    expect(geometry.padding, const EdgeInsetsDirectional.fromSTEB(6, 6, 6, 30));
    expect(geometry.rowHeight, 50);
    expect(geometry.barHeight, 86);
    expect(geometry.footerExtent, 92);
    expect(
      geometry.borderRadius,
      const BorderRadius.vertical(top: Radius.circular(31)),
    );
  });

  test('a square screen keeps the floating capsule', () {
    const geometry = DMobileDockGeometry(foot: 0);
    expect(geometry.margin, const EdgeInsetsDirectional.all(6));
    expect(geometry.padding, const EdgeInsetsDirectional.all(6));
    expect(geometry.barHeight, 62);
    expect(geometry.footerExtent, 74);
    expect(geometry.borderRadius, BorderRadius.circular(31));
  });

  test('a shallow foot keeps the bar that far from the edges', () {
    const geometry = DMobileDockGeometry(foot: 4);
    expect(geometry.margin, const EdgeInsetsDirectional.fromSTEB(2, 6, 2, 2));
    expect(geometry.padding, const EdgeInsetsDirectional.fromSTEB(6, 6, 6, 10));
  });

  test('larger text grows the row and keeps its room above the foot', () {
    const geometry = DMobileDockGeometry(foot: 34, growth: 11);
    expect(geometry.rowHeight, 61);
    expect(geometry.circle, 59);
    expect(geometry.topRadius, 36.5);
    expect(geometry.padding.bottom, 30);
    expect(geometry.barHeight, 6 + 30 + 61);
  });

  test('a corner is on the diagonal, never deeper than the foot', () {
    const round = DMobileDockGeometry(foot: 34);
    expect(round.cornerAt(48), closeTo(13.3225, .001));
    expect(round.cornerAt(59), closeTo(11.7116, .001));
    expect(round.cornerAt(34), closeTo(15.3728, .001));
    expect(const DMobileDockGeometry(foot: 10).cornerAt(48), 10);
    expect(const DMobileDockGeometry(foot: 0).cornerAt(48), 6);
  });

  test('what ends at the foot stands off it, rounded with the screen', () {
    const round = DMobileDockGeometry(foot: 34);
    expect(round.endLift, 23);
    expect(round.endRadius(24), 32);
    expect(round.endRadius(14), 32);
    const deep = DMobileDockGeometry(foot: 80);
    expect(deep.endLift, 46);
    expect(deep.endRadius(24), 24, reason: 'never tighter than its least');
    const square = DMobileDockGeometry(foot: 0);
    expect(square.endLift, 6);
    expect(square.endRadius(24), 24, reason: 'no curve to follow');
  });

  test('the row is four columns, the ⋮ and action sharing the fourth', () {
    final slots = const DMobileDockGeometry(
      foot: 34,
    ).rowSlots(390, places: 3, tail: DMobileDockTail.more, action: true);
    expect(slots.places, [
      (start: 0.0, width: 91.5),
      (start: 95.5, width: 91.5),
      (start: 191.0, width: 91.5),
    ]);
    expect(slots.tail, (start: 286.5, width: 40.0));
    expect(slots.action, (start: 328.0, width: 50.0));
  });

  test('a narrow bar widens the fourth column so the ⋮ and action fit', () {
    final capsule = const DMobileDockGeometry(
      foot: 0,
    ).rowSlots(378, places: 3, tail: DMobileDockTail.more, action: true);
    expect(capsule.places.map((slot) => slot.width), [88.0, 88.0, 88.0]);
    expect(capsule.tail, (start: 276.0, width: 40.0));
    expect(capsule.action, (start: 316.0, width: 50.0));
    final largeText = const DMobileDockGeometry(
      foot: 34,
      growth: 11,
    ).rowSlots(320, places: 3, tail: DMobileDockTail.more, action: true);
    expect(largeText.places.map((slot) => slot.width), [65.0, 65.0, 65.0]);
    expect(largeText.tail, (start: 207.0, width: 40.0));
    expect(largeText.action, (start: 247.0, width: 61.0));
  });

  test('without an action or a ⋮ the columns stay the grid\'s', () {
    final noAction = const DMobileDockGeometry(
      foot: 0,
    ).rowSlots(378, places: 3, tail: DMobileDockTail.more, action: false);
    expect(noAction.places.map((slot) => slot.width), [88.5, 88.5, 88.5]);
    expect(noAction.tail, (start: 277.5, width: 40.0));
    expect(noAction.action, isNull);
    final few = const DMobileDockGeometry(
      foot: 34,
    ).rowSlots(390, places: 2, tail: DMobileDockTail.none, action: true);
    expect(few.places, [(start: 0.0, width: 91.5), (start: 95.5, width: 91.5)]);
    expect(few.tail, isNull);
    expect(few.action, (start: 328.0, width: 50.0));
  });

  test('an overflowed page shares the three places\' and the ⋮\'s room', () {
    final slots = const DMobileDockGeometry(
      foot: 34,
    ).rowSlots(390, places: 3, tail: DMobileDockTail.page, action: true);
    // (3 * 91.5 + 40) / 4, with the three gaps kept.
    expect(slots.places, [
      (start: 0.0, width: 78.625),
      (start: 82.625, width: 78.625),
      (start: 165.25, width: 78.625),
    ]);
    expect(slots.tail, (start: 247.875, width: 78.625));
    expect(slots.action, (start: 328.0, width: 50.0));
    final capsule = const DMobileDockGeometry(
      foot: 0,
    ).rowSlots(378, places: 3, tail: DMobileDockTail.page, action: true);
    expect(capsule.places.map((slot) => slot.width), [76.0, 76.0, 76.0]);
    expect(capsule.tail, (start: 240.0, width: 76.0));
    expect(capsule.action, (start: 316.0, width: 50.0));
  });

  group('the panel the bar grows into', () {
    const round = DMobileDockGeometry(foot: 34);

    test('is laid out from the screen\'s foot on the bar\'s columns', () {
      final panel = round.panel(tiles: 5);
      expect(round.tileHeight, 56);
      expect(round.headOverflow, 3);
      expect(panel.tileHeight, 56);
      expect(panel.rows, 2);
      // 16 above the bar, its 6 inset, its row as a 56 tile, and a row gap.
      expect(panel.topPadding, 92);
      expect(panel.bottomPadding, 42);
      expect(panel.height, 260);
      expect(panel.barTop, 86);
      expect(panel.reveal, 174);
      expect(panel.travel, 158);
      expect(round.gridColumn(390), 91.5);
      expect(panel.tileRect(0, 390), const Rect.fromLTWH(6, 92, 91.5, 56));
      expect(panel.tileRect(3, 390), const Rect.fromLTWH(292.5, 92, 91.5, 56));
      expect(panel.tileRect(4, 390), const Rect.fromLTWH(6, 162, 91.5, 56));
    });

    test('measures what it holds, a row at a time', () {
      expect(round.panel(tiles: 1).height, 190);
      expect(round.panel(tiles: 4).height, 190);
      expect(round.panel(tiles: 9).rows, 3);
      expect(round.panel(tiles: 9).height, 330);
    });

    test('shows from the bar\'s top edge up as the bar rises', () {
      final panel = round.panel(tiles: 5);
      expect(panel.clipInset(0), 174);
      expect(panel.clipInset(.5), 87);
      expect(panel.clipInset(1), 0);
      expect(panel.barRise(0), 0);
      expect(panel.barRise(.5), 79);
      expect(panel.barRise(1), 158);
      expect(panel.grabberTop(0), 180);
      expect(panel.grabberTop(1), 6);
    });

    test('a spring past open moves the bar alone', () {
      final panel = round.panel(tiles: 5);
      expect(panel.clipInset(1.1), 0);
      expect(panel.clipInset(-.1), 174);
      expect(panel.barRise(1.1), closeTo(173.8, 1e-9));
      expect(panel.grabberTop(1.1), 6);
    });

    test('the grid comes up once the panel is out from under the bar', () {
      expect(DMobileDockPanelGeometry.gridOpacity(0), 0);
      expect(DMobileDockPanelGeometry.gridOpacity(.375), closeTo(0, 1e-9));
      expect(DMobileDockPanelGeometry.gridOpacity(.5), closeTo(.2, 1e-9));
      expect(DMobileDockPanelGeometry.gridOpacity(1), 1);
      expect(DMobileDockPanelGeometry.gridOpacity(1.2), 1);
    });

    test('a capsule has less of the panel above it', () {
      final capsule = const DMobileDockGeometry(foot: 0).panel(tiles: 5);
      expect(capsule.barTop, 68);
      expect(capsule.height, 226);
      expect(capsule.reveal, 158);
      expect(capsule.travel, 142);
    });

    test('larger text grows the tiles with the bar\'s row', () {
      final panel = const DMobileDockGeometry(
        foot: 34,
        growth: 11,
      ).panel(tiles: 5);
      expect(panel.tileHeight, 67);
      expect(panel.bar.headOverflow, 3);
      expect(panel.topPadding, 103);
      expect(panel.height, 293);
      expect(panel.tileRect(4, 390).top, 184);
    });

    test('its places\' slots are the head\'s tiles, then the grid\'s', () {
      final full = const DMobileDockGeometry(foot: 34).panel(tiles: 4);
      expect(full.placeRects(places: 6, width: 390, action: true), const [
        Rect.fromLTWH(6, 19, 91.5, 56),
        Rect.fromLTWH(101.5, 19, 91.5, 56),
        Rect.fromLTWH(197, 19, 91.5, 56),
        Rect.fromLTWH(6, 92, 91.5, 56),
        Rect.fromLTWH(101.5, 92, 91.5, 56),
        Rect.fromLTWH(197, 92, 91.5, 56),
      ]);
      // A capsule stands in from the panel's edges by its own margin, and its
      // fourth column grows to hold the ⋮ and the action, so the head's
      // tiles are set in and narrower than the grid's.
      final capsule = const DMobileDockGeometry(foot: 0).panel(tiles: 4);
      final slots = capsule.placeRects(places: 6, width: 390, action: true);
      expect(slots.take(3), const [
        Rect.fromLTWH(12, 19, 88, 56),
        Rect.fromLTWH(104, 19, 88, 56),
        Rect.fromLTWH(196, 19, 88, 56),
      ]);
      expect(slots[3], const Rect.fromLTWH(6, 92, 91.5, 56));
      expect(slots, hasLength(6));
    });

    test('equal inputs make equal panels', () {
      expect(round.panel(tiles: 5), round.panel(tiles: 5));
      expect(round.panel(tiles: 5), isNot(round.panel(tiles: 6)));
    });
  });

  test('equal inputs make equal geometries', () {
    expect(
      const DMobileDockGeometry(foot: 34, growth: 2),
      const DMobileDockGeometry(foot: 34, growth: 2),
    );
    expect(
      const DMobileDockGeometry(foot: 34),
      isNot(const DMobileDockGeometry(foot: 0)),
    );
  });
}
