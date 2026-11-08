import 'dart:developer' show Timeline;

/// Receives every point of a cold start. Only the startup profiling entrypoint
/// sets this.
void Function(String point)? startupMarkObserver;

/// Records a named point of a cold start on the VM timeline, where
/// `tool/profile_startup.py` reads it back.
void markStartup(String point) {
  Timeline.instantSync('startup: $point');
  startupMarkObserver?.call(point);
}
