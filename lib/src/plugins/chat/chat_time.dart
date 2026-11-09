import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:timezone/timezone.dart' as tz;

/// The reader's calendar and wall clock for one Chat presentation.
final class ChatTime {
  const ChatTime(this.location);
  const ChatTime.device() : location = null;

  final tz.Location? location;
  String get name => location?.name ?? 'device';

  DateTime local(DateTime instant) => switch (location) {
    final zone? => tz.TZDateTime.from(instant, zone),
    null => instant.toLocal(),
  };

  DateTime? day(DateTime? instant) {
    if (instant == null) return null;
    final value = local(instant);
    return DateTime(value.year, value.month, value.day);
  }

  static ChatTime forReader({
    PluginTimezoneHost? zones,
    String? accountTimezone,
  }) {
    if (zones == null) return const ChatTime.device();
    final name = zones.readerTimezone(accountTimezone);
    return ChatTime(zones.location(name));
  }
}
