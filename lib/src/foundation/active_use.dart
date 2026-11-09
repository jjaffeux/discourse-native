import 'elapsed_time.dart';

/// Whether a person is using the app right now.
///
/// Core records a visit from a user API key only on a request marked
/// `Discourse-Present: true`, and the web client marks one only while its
/// `userPresent()` holds: the page is on screen and input arrived within the
/// last minute. This is that rule, so an app left running does not read as
/// someone visiting.
final class ActiveUse {
  ActiveUse({required this._foreground, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _lastSeen = _clock();
  }

  static const Duration unseenAfter = Duration(minutes: 1);

  final DateTime Function() _clock;
  late DateTime _lastSeen;
  bool _foreground;

  bool get isActive =>
      _foreground && elapsedSince(_lastSeen, now: _clock()) < unseenAfter;

  void seen() => _lastSeen = _clock();

  void setForeground(bool foreground) {
    if (foreground && !_foreground) seen();
    _foreground = foreground;
  }
}
