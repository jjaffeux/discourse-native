import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

/// Read-only access to the host's timezone database and reader preference.
/// Plugins cannot change the device zone or dispose the shared environment.
final class PluginTimezoneHost {
  const PluginTimezoneHost({
    required this.readerTimezone,
    required this.location,
    required this.timezoneNames,
    required this.changes,
  });

  final String Function([String? accountTimezone]) readerTimezone;
  final tz.Location? Function(String? name) location;
  final Iterable<String> Function() timezoneNames;
  final Listenable changes;
}
