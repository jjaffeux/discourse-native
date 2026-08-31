import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

class TimezoneEnvironment extends ChangeNotifier {
  TimezoneEnvironment._({Future<String?> Function()? detectDeviceTimezone})
    : _detectDeviceTimezone =
          detectDeviceTimezone ?? _readPlatformDeviceTimezone;

  @visibleForTesting
  factory TimezoneEnvironment.forTesting({
    required Future<String?> Function() detectDeviceTimezone,
  }) => TimezoneEnvironment._(detectDeviceTimezone: detectDeviceTimezone);

  static final TimezoneEnvironment instance = TimezoneEnvironment._();

  final Future<String?> Function() _detectDeviceTimezone;

  static const Map<String, String> aliases = {
    'UTC': 'Etc/UTC',
    'GMT': 'Etc/GMT',
    'IST': 'Asia/Kolkata',
    'KST': 'Asia/Seoul',
    'JST': 'Asia/Tokyo',
  };

  bool _databaseReady = false;
  String? _deviceTimezone;
  int _refreshGeneration = 0;

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
    final generation = ++_refreshGeneration;
    ensureDatabase();
    String? detected;
    try {
      detected = await _detectDeviceTimezone();
    } catch (_) {
      // Platform detection is optional; account timezones and UTC remain.
    }
    if (generation != _refreshGeneration) return;
    final canonical = canonicalTimezone(detected);
    if (_deviceTimezone == canonical) {
      if (forceNotify) notifyListeners();
      return;
    }
    _deviceTimezone = canonical;
    notifyListeners();
  }

  static Future<String?> _readPlatformDeviceTimezone() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;

  String readerTimezone([String? accountTimezone]) =>
      canonicalTimezone(accountTimezone) ??
      canonicalTimezone(_deviceTimezone) ??
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
