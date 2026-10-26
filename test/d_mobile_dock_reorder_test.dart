import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hitting a slot', () {
    const slots = [
      Rect.fromLTWH(0, 0, 100, 50),
      Rect.fromLTWH(100, 0, 100, 50),
    ];
    int? at(double x, double y) =>
        DMobileDockReorder.slotAt(slots, Offset(x, y));

    test('well inside a slot is that slot', () {
      expect(at(50, 25), 0);
      expect(at(150, 25), 1);
      expect(at(15.1, 8), 0);
      expect(at(184.9, 42), 1);
    });

    test('the outer 15% of each edge is no slot, so a border crossed does '
        'not flicker', () {
      expect(at(14.9, 25), isNull);
      expect(at(99, 25), isNull);
      expect(at(101, 25), isNull);
      expect(at(50, 7), isNull);
      expect(at(50, 43), isNull);
    });

    test('outside every slot is none', () {
      expect(at(50, 60), isNull);
      expect(at(-5, 25), isNull);
    });
  });

  group('moving a place', () {
    const order = ['a', 'b', 'c', 'd'];

    test('to an earlier slot pushes the ones between later', () {
      expect(DMobileDockReorder.moved(order, 3, 0), ['d', 'a', 'b', 'c']);
      expect(DMobileDockReorder.moved(order, 2, 1), ['a', 'c', 'b', 'd']);
    });

    test('to a later slot pulls the ones between earlier', () {
      expect(DMobileDockReorder.moved(order, 0, 3), ['b', 'c', 'd', 'a']);
      expect(DMobileDockReorder.moved(order, 1, 2), ['a', 'c', 'b', 'd']);
    });

    test(
      'to its own slot changes nothing, and leaves the given list alone',
      () {
        expect(DMobileDockReorder.moved(order, 2, 2), order);
        final copy = [...order];
        DMobileDockReorder.moved(copy, 3, 0);
        expect(copy, order);
      },
    );
  });
}
