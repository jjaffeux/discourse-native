import 'dart:developer' as developer;

/// Opt-in prefetch outcomes, without site URLs, topic IDs, or content.
/// Pair these with TRACE_SURFACE_OPENING for click-to-content timings.
abstract final class TopicPrefetchTrace {
  static const _enabled = bool.fromEnvironment('TRACE_TOPIC_PREFETCH');
  static void Function(String event, Map<String, Object> data)? observer;
  static int _sequence = 0;

  static bool get enabled => _enabled || observer != null;

  static int nextId() => ++_sequence;

  static void record(String event, Map<String, Object> data) {
    if (_enabled) {
      developer.Timeline.instantSync('topicPrefetch.$event', arguments: data);
    }
    observer?.call(event, data);
  }
}
