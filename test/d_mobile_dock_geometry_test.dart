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

  test('the row is five columns: three places, the fixed place, and the action '
      '37 in from the screen\'s edge', () {
    final slots = const DMobileDockGeometry(
      foot: 34,
    ).rowSlots(390, places: 3, fixed: true, action: true);
    // 378 inside: columns of 72.4 and four gaps of 4.
    expect(slots.places, [
      (start: 0.0, width: 72.4),
      (start: 76.4, width: 72.4),
      (start: 152.8, width: 72.4),
    ]);
    expect(slots.here, isNull);
    expect(slots.fixed!.start, closeTo(229.2, 1e-9));
    expect(slots.fixed!.width, 72.4);
    // Its middle 37 in from the screen's edge: 353 from the bar's start,
    // 347 from the row's, 25 to its start.
    expect(slots.action, (start: 322.0, width: 50.0));
    expect(const DMobileDockGeometry(foot: 34).gridColumn(390), 72.4);
    expect(const DMobileDockGeometry(foot: 34).actionNameWidth(390), 64.4);
  });

  test('a capsule keeps the action at its row\'s end, 37 from the screen', () {
    final capsule = const DMobileDockGeometry(
      foot: 0,
    ).rowSlots(378, places: 3, fixed: true, action: true);
    expect(capsule.places.map((slot) => slot.width), [70.0, 70.0, 70.0]);
    expect(capsule.fixed, (start: 222.0, width: 70.0));
    expect(capsule.action, (start: 316.0, width: 50.0));
  });

  test('a narrow bar widens the last column so the action fits, the rest '
      'sharing what is left', () {
    final largeText = const DMobileDockGeometry(
      foot: 34,
      growth: 11,
    ).rowSlots(320, places: 3, fixed: true, action: true);
    // The action is 61 across and reaches 61.5 back from the row's end.
    expect(largeText.places.map((slot) => slot.width), [
      57.625,
      57.625,
      57.625,
    ]);
    expect(largeText.fixed, (start: 184.875, width: 57.625));
    expect(largeText.action, (start: 246.5, width: 61.0));
    expect(largeText.action!.start, greaterThanOrEqualTo(184.875 + 57.625));
  });

  test('without an action or a fixed place the columns stay the grid\'s', () {
    final noAction = const DMobileDockGeometry(
      foot: 0,
    ).rowSlots(378, places: 3, fixed: true, action: false);
    expect(noAction.places.map((slot) => slot.width), [70.0, 70.0, 70.0]);
    expect(noAction.fixed, (start: 222.0, width: 70.0));
    expect(noAction.action, isNull);
    final few = const DMobileDockGeometry(
      foot: 34,
    ).rowSlots(390, places: 2, fixed: true, action: true);
    expect(few.places, [(start: 0.0, width: 72.4), (start: 76.4, width: 72.4)]);
    expect(few.fixed, (start: 152.8, width: 72.4), reason: 'after the places');
    expect(few.action, (start: 322.0, width: 50.0));
    final unfixed = const DMobileDockGeometry(
      foot: 34,
    ).rowSlots(390, places: 3, action: true);
    expect(unfixed.fixed, isNull);
    expect(unfixed.places.last, (start: 152.8, width: 72.4));
  });

  test('the current page added shares the four columns\' room before the '
      'action, the action standing where it stood', () {
    final slots = const DMobileDockGeometry(
      foot: 34,
    ).rowSlots(390, places: 3, here: true, fixed: true, action: true);
    // (4 * 72.4 + 3 * 4 - 4 * 4) / 5, with the gaps kept.
    final shared = [...slots.places, slots.here!, slots.fixed!];
    for (final (index, slot) in shared.indexed) {
      expect(slot.start, closeTo(index * 61.12, 1e-9), reason: '$index');
      expect(slot.width, closeTo(57.12, 1e-9), reason: '$index');
    }
    expect(slots.action, (start: 322.0, width: 50.0));
    // With no fixed place, four share the four columns: each is a column.
    final unfixed = const DMobileDockGeometry(
      foot: 34,
    ).rowSlots(390, places: 3, here: true, action: true);
    expect(unfixed.here!.start, closeTo(229.2, 1e-9));
    expect(unfixed.here!.width, 72.4);
    expect(unfixed.fixed, isNull);
  });

  group('the panel the bar grows into', () {
    const round = DMobileDockGeometry(foot: 34);

    test('is laid out from the screen\'s foot on the bar\'s columns', () {
      final panel = round.panel(tiles: 6);
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
      expect(round.gridColumn(390), 72.4);
      expect(panel.tileRect(0, 390), const Rect.fromLTWH(6, 92, 72.4, 56));
      expect(panel.tileRect(4, 390), const Rect.fromLTWH(311.6, 92, 72.4, 56));
      expect(panel.tileRect(5, 390), const Rect.fromLTWH(6, 162, 72.4, 56));
    });

    test('measures what it holds, a row of five at a time', () {
      expect(round.panel(tiles: 1).height, 190);
      expect(round.panel(tiles: 5).height, 190);
      expect(round.panel(tiles: 11).rows, 3);
      expect(round.panel(tiles: 11).height, 330);
    });

    test('shows from the bar\'s top edge up as the bar rises', () {
      final panel = round.panel(tiles: 6);
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
      final panel = round.panel(tiles: 6);
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
      final capsule = const DMobileDockGeometry(foot: 0).panel(tiles: 6);
      expect(capsule.barTop, 68);
      expect(capsule.height, 226);
      expect(capsule.reveal, 158);
      expect(capsule.travel, 142);
    });

    test('larger text grows the tiles with the bar\'s row', () {
      final panel = const DMobileDockGeometry(
        foot: 34,
        growth: 11,
      ).panel(tiles: 6);
      expect(panel.tileHeight, 67);
      expect(panel.bar.headOverflow, 3);
      expect(panel.topPadding, 103);
      expect(panel.height, 293);
      expect(panel.tileRect(5, 390).top, 184);
    });

    test('its places\' slots are the head\'s tiles, then the grid\'s', () {
      final full = const DMobileDockGeometry(foot: 34).panel(tiles: 4);
      expect(full.placeRects(places: 6, width: 390, action: true), const [
        Rect.fromLTWH(6, 19, 72.4, 56),
        Rect.fromLTWH(82.4, 19, 72.4, 56),
        Rect.fromLTWH(158.8, 19, 72.4, 56),
        Rect.fromLTWH(6, 92, 72.4, 56),
        Rect.fromLTWH(82.4, 92, 72.4, 56),
        Rect.fromLTWH(158.8, 92, 72.4, 56),
      ]);
      // A capsule stands in from the panel's edges by its own margin, so the
      // head's tiles are set in and narrower than the grid's.
      final capsule = const DMobileDockGeometry(foot: 0).panel(tiles: 4);
      final slots = capsule.placeRects(places: 6, width: 390, action: true);
      expect(slots.take(3), const [
        Rect.fromLTWH(12, 19, 70, 56),
        Rect.fromLTWH(86, 19, 70, 56),
        Rect.fromLTWH(160, 19, 70, 56),
      ]);
      expect(slots[3], const Rect.fromLTWH(6, 92, 72.4, 56));
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
