/// How a phone's bar is dragged into its panel of places and settles once
/// let go. Growth runs from 0, the bar alone, to 1, the panel open.
abstract final class DMobileDockDrag {
  /// How far a touch moves before it is a drag rather than a press.
  static const slop = 8.0;

  /// The screen's very foot is the system's, for going home: a touch drag
  /// starting this close to the bottom edge is not the bar's.
  static const homeBand = 20.0;

  /// Faster than this, in pixels per millisecond, a release is a flick and
  /// goes the way it was moving.
  static const flick = .1;

  /// Still, a release goes by how far it has come: a pull up opens from
  /// well short of halfway, and a push down from open closes only once most
  /// of the way back.
  static const opensFromClosedPast = .25;
  static const opensFromOpenPast = .75;

  /// Whether the panel settles open after a drag that began at [start],
  /// ended at [at], and was moving at [velocity] (upward positive) as it was
  /// let go.
  static bool settlesOpen({
    required double start,
    required double at,
    required double velocity,
  }) =>
      velocity > flick ||
      (velocity > -flick &&
          (start == 0 ? at > opensFromClosedPast : at > opensFromOpenPast));

  /// Whether the panel settles open after a trackpad swipe that [pushed] it
  /// (upward positive, summed over the swipe) and left it at [at]: the way
  /// the swipe went says where it goes, however far it got.
  static bool swipeSettlesOpen({required double pushed, required double at}) =>
      pushed > 0 ? at > .02 : at > .98;
}

/// Where a finger has been lately, for how fast it was moving as it let go:
/// over the last stretch of samples rather than the last two, as a finger
/// lifting off rocks back a pixel or two that would read as a flick.
class DMobileDockDragTrail {
  DMobileDockDragTrail({this.window = const Duration(milliseconds: 100)});

  final Duration window;
  final _samples = <({double y, Duration at})>[];

  /// Records the finger at [y] (down the screen) at [at], and forgets what
  /// is older than [window], keeping at least two samples.
  void add(double y, Duration at) {
    _samples.add((y: y, at: at));
    while (_samples.length > 2 && at - _samples.first.at > window) {
      _samples.removeAt(0);
    }
  }

  /// Pixels per millisecond, upward positive. Nothing until two samples
  /// apart in time.
  double get velocity {
    if (_samples.length < 2) return 0;
    final first = _samples.first;
    final last = _samples.last;
    final milliseconds = (last.at - first.at).inMicroseconds / 1000;
    return milliseconds <= 0 ? 0 : (first.y - last.y) / milliseconds;
  }

  void clear() => _samples.clear();
}
