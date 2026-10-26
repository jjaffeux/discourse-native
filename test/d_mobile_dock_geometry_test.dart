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
