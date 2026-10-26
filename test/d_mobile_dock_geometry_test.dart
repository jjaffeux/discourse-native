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

  test('a lifted bar floats as the capsule over the lift and the foot', () {
    const geometry = DMobileDockGeometry(foot: 34, lift: 60);
    expect(geometry.margin, const EdgeInsetsDirectional.fromSTEB(6, 6, 6, 100));
    expect(geometry.padding, const EdgeInsetsDirectional.all(6));
    expect(geometry.barHeight, 62);
    expect(geometry.footerExtent, 168);
    expect(geometry.borderRadius, BorderRadius.circular(31));
    expect(geometry.ground, 94);
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
    expect(const DMobileDockGeometry(foot: 34, lift: 60).cornerAt(48), 6);
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
