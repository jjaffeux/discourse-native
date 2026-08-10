import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

/// Owns the process-wide IANA database and the device's current zone.
///
/// Source dates remain site-specific, but the reader zone is a property of the
/// device. Keeping detection here means every cooked fragment observes one
/// answer and a resume-time timezone change redraws all of them together.
class LocalDateEnvironment extends ChangeNotifier {
  LocalDateEnvironment._();

  static final LocalDateEnvironment instance = LocalDateEnvironment._();

  static const Map<String, String> aliases = {
    'UTC': 'Etc/UTC',
    'GMT': 'Etc/GMT',
    'IST': 'Asia/Kolkata',
    'KST': 'Asia/Seoul',
    'JST': 'Asia/Tokyo',
  };

  bool _databaseReady = false;
  String? _deviceTimezone;

  String? get deviceTimezone => _deviceTimezone;

  Iterable<String> get timezoneNames {
    ensureDatabase();
    return tz.timeZoneDatabase.locations.keys;
  }

  void ensureDatabase() {
    if (_databaseReady) return;
    timezone_data.initializeTimeZones();
    _databaseReady = true;
  }

  Future<void> initialize() async {
    ensureDatabase();
    await refreshDeviceTimezone();
  }

  Future<void> refreshDeviceTimezone({bool forceNotify = false}) async {
    ensureDatabase();
    String? detected;
    try {
      detected = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      // A platform without the plugin still renders in the account timezone,
      // then UTC. Rendering content must not make application startup fail.
    }
    final canonical = canonicalTimezone(detected);
    if (_deviceTimezone == canonical) {
      if (forceNotify) notifyListeners();
      return;
    }
    _deviceTimezone = canonical;
    notifyListeners();
  }

  /// Reader-zone precedence agreed with the web-compatible contract.
  String readerTimezone([String? accountTimezone]) =>
      canonicalTimezone(_deviceTimezone) ??
      canonicalTimezone(accountTimezone) ??
      'Etc/UTC';

  String? canonicalTimezone(String? name) {
    ensureDatabase();
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final candidate = aliases[trimmed] ?? trimmed;
    try {
      tz.getLocation(candidate);
      return candidate;
    } on tz.LocationNotFoundException {
      return null;
    }
  }

  tz.Location? location(String? name) {
    final canonical = canonicalTimezone(name);
    return canonical == null ? null : tz.getLocation(canonical);
  }

  @visibleForTesting
  void setDeviceTimezone(String? name) {
    ensureDatabase();
    final canonical = canonicalTimezone(name);
    if (_deviceTimezone == canonical) return;
    _deviceTimezone = canonical;
    notifyListeners();
  }
}
