import 'package:flutter/widgets.dart';

import '../foundation/surface_depth.dart';

/// How a place in a phone's open panel is moved: held still it lifts, follows
/// the finger over the panel's slots, each slot it is brought to making room
/// for it, and is set down where it is let go.
abstract final class DMobileDockReorder {
  /// How long a place is held still before it lifts. Moved past the bar's
  /// slop before then, the hold is the panel's own drag instead.
  static const hold = Duration(milliseconds: 320);

  /// A lifted place is drawn this much larger, over everything else in the
  /// panel, on the raised surface with this shadow under it.
  static const scale = 1.06;
  static const shadow = DCastShadow(Offset(0, 8), 24, Color(0x59000000));

  /// The places a lifted one displaces slide to their new slots, and a place
  /// let go settles into its slot, on this curve.
  static const slide = Duration(milliseconds: 220);
  static const settle = Duration(milliseconds: 200);
  static const curve = Cubic(.32, .72, 0, 1);

  /// A slot is hit only inside its inner 70%, this far in from each edge, so
  /// a finger crossing from one slot to the next does not flicker between
  /// them.
  static const slotInset = .15;

  /// The slot among [slots] whose inner 70% holds [at], or none.
  static int? slotAt(List<Rect> slots, Offset at) {
    for (final (index, slot) in slots.indexed) {
      final inner = Rect.fromCenter(
        center: slot.center,
        width: slot.width * (1 - 2 * slotInset),
        height: slot.height * (1 - 2 * slotInset),
      );
      if (inner.contains(at)) return index;
    }
    return null;
  }

  /// [order] with what stands at [from] standing at [to], the rest closing
  /// up behind it.
  static List<T> moved<T>(List<T> order, int from, int to) {
    final out = [...order]..removeAt(from);
    return out..insert(to, order[from]);
  }
}
