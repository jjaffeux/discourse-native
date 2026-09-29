import 'dart:ui';

/// Conservative linear cursor prediction. Call at most once per frame with
/// visible, clipped row bounds in the same coordinate space as the pointer.
final class TopicPointerPredictor<T extends Object> {
  static const horizon = Duration(milliseconds: 80);
  static const historyAge = Duration(milliseconds: 120);
  final _history = <({Offset point, Duration time})>[];
  T? _previousCandidate;

  void reset() {
    _history.clear();
    _previousCandidate = null;
  }

  T? sample(Offset point, Duration time, Map<T, Rect> targets) {
    if (_history.isNotEmpty) {
      final last = _history.last;
      if (time <= last.time || time - last.time > historyAge) reset();
    }
    if (_history.length >= 2) {
      final previous =
          _history.last.point - _history[_history.length - 2].point;
      final next = point - _history.last.point;
      if (previous.dx * next.dx + previous.dy * next.dy < 0) reset();
    }
    _history.removeWhere((sample) => time - sample.time > historyAge);
    _history.add((point: point, time: time));
    if (_history.length > 8) _history.removeAt(0);
    if (_history.length < 2) return null;
    final first = _history.first;
    final delta = point - first.point;
    final elapsed = (time - first.time).inMicroseconds;
    if (elapsed <= 0 || delta.distanceSquared < 1) {
      _previousCandidate = null;
      return null;
    }
    final end = point + delta * (horizon.inMicroseconds / elapsed);
    T? candidate;
    for (final target in targets.entries) {
      // Actual hover owns rows already under the pointer. A vertical sweep
      // through several rows is too ambiguous to justify early fetching.
      if (target.value.contains(point)) {
        _previousCandidate = null;
        return null;
      }
      if (!_intersects(point, end, target.value)) continue;
      if (candidate != null) {
        _previousCandidate = null;
        return null;
      }
      candidate = target.key;
    }
    final stable = candidate != null && candidate == _previousCandidate;
    _previousCandidate = candidate;
    return stable ? candidate : null;
  }

  // Clip the finite segment to the rectangle's horizontal and vertical slabs.
  static bool _intersects(Offset start, Offset end, Rect rect) {
    var entry = 0.0;
    var exit = 1.0;
    for (final (origin, delta, minimum, maximum) in [
      (start.dx, end.dx - start.dx, rect.left, rect.right),
      (start.dy, end.dy - start.dy, rect.top, rect.bottom),
    ]) {
      if (delta == 0) {
        if (origin < minimum || origin > maximum) return false;
        continue;
      }
      var near = (minimum - origin) / delta;
      var far = (maximum - origin) / delta;
      if (near > far) (near, far) = (far, near);
      if (near > entry) entry = near;
      if (far < exit) exit = far;
      if (entry > exit) return false;
    }
    return true;
  }
}
