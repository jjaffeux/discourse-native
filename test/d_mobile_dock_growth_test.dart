import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('settling after a drag', () {
    bool opens(double start, double at, double velocity) =>
        DMobileDockDrag.settlesOpen(start: start, at: at, velocity: velocity);

    test('a flick goes the way it was moving, however far it got', () {
      expect(opens(0, .1, .3), isTrue);
      expect(opens(1, .9, -.3), isFalse);
      expect(opens(0, .9, -.3), isFalse);
      expect(opens(1, .1, .3), isTrue);
    });

    test('a slow release from closed opens only past a quarter', () {
      expect(opens(0, .2, 0), isFalse);
      expect(opens(0, .26, 0), isTrue);
      expect(opens(0, .2, .09), isFalse);
      expect(opens(0, .26, -.09), isTrue);
    });

    test('a slow release from open closes only past three quarters', () {
      expect(opens(1, .8, 0), isTrue);
      expect(opens(1, .7, 0), isFalse);
      expect(opens(.5, .7, 0), isFalse);
    });

    test('at the flick speed, upward is still and downward is a flick', () {
      expect(opens(0, .1, .1), isFalse);
      expect(opens(0, .3, .1), isTrue);
      expect(opens(1, .9, -.1), isFalse);
    });
  });

  group('settling after a trackpad swipe', () {
    bool opens(double pushed, double at) =>
        DMobileDockDrag.swipeSettlesOpen(pushed: pushed, at: at);

    test('an upward swipe opens once it has moved at all', () {
      expect(opens(40, .03), isTrue);
      expect(opens(40, .01), isFalse);
    });

    test('a downward swipe closes unless the panel stayed open', () {
      expect(opens(-40, .97), isFalse);
      expect(opens(-40, .99), isTrue);
    });
  });

  group('the drag trail', () {
    test('reads the velocity over its window, upward positive', () {
      final trail = DMobileDockDragTrail();
      trail.add(500, const Duration(milliseconds: 0));
      trail.add(480, const Duration(milliseconds: 40));
      trail.add(460, const Duration(milliseconds: 80));
      expect(trail.velocity, closeTo(.5, 1e-9));
      trail.clear();
      trail.add(400, const Duration(milliseconds: 0));
      trail.add(430, const Duration(milliseconds: 100));
      expect(trail.velocity, closeTo(-.3, 1e-9));
    });

    test('forgets samples older than its window but keeps two', () {
      final trail = DMobileDockDragTrail();
      trail.add(500, const Duration(milliseconds: 0));
      trail.add(300, const Duration(milliseconds: 50));
      trail.add(298, const Duration(milliseconds: 400));
      trail.add(296, const Duration(milliseconds: 450));
      // The fast stretch is long gone: only the last 50 ms count.
      expect(trail.velocity, closeTo(.04, 1e-9));
      trail.clear();
      trail.add(500, const Duration(milliseconds: 0));
      trail.add(300, const Duration(milliseconds: 500));
      expect(trail.velocity, closeTo(.4, 1e-9));
    });

    test('a finger rocking back as it lifts does not read as a flick', () {
      final trail = DMobileDockDragTrail();
      for (var i = 0; i <= 5; i++) {
        trail.add(500 - 10.0 * i, Duration(milliseconds: 16 * i));
      }
      trail.add(452, const Duration(milliseconds: 96));
      expect(trail.velocity, greaterThan(DMobileDockDrag.flick));
    });

    test('is still until two samples apart in time', () {
      final trail = DMobileDockDragTrail();
      expect(trail.velocity, 0);
      trail.add(500, const Duration(milliseconds: 10));
      expect(trail.velocity, 0);
      trail.add(400, const Duration(milliseconds: 10));
      expect(trail.velocity, 0);
    });
  });
}
