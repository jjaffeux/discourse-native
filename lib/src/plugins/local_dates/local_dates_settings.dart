import 'package:flutter/foundation.dart';

import '../../models/json.dart';
import '../../models/site_config.dart';
import '../../plugin_api/plugin_data.dart';

const localDatesSettingsDataKey = PluginDataKey<LocalDatesSettings>(
  owner: 'discourse-local-dates',
  name: 'site-settings',
);

/// Authoring and presentation defaults owned by discourse-local-dates.
@immutable
final class LocalDatesSettings {
  const LocalDatesSettings({
    this.enabled = false,
    this.formats = defaultFormats,
    this.timezones = defaultTimezones,
  });

  static const List<String> defaultFormats = ['LLL', 'LTS', 'LL', 'LLLL'];
  static const List<String> defaultTimezones = [
    'Europe/Paris',
    'America/Los_Angeles',
  ];

  factory LocalDatesSettings.fromSiteSettings(Map<String, dynamic> json) =>
      LocalDatesSettings(
        enabled: json['discourse_local_dates_enabled'] == true,
        formats: _pipeListOr(
          json['discourse_local_dates_default_formats'],
          defaultFormats,
        ),
        timezones: _pipeListOr(
          json['discourse_local_dates_default_timezones'],
          defaultTimezones,
        ),
      );

  static LocalDatesSettings? fromStored(Object? value) {
    final json = _objectFields(value);
    if (json == null) return null;
    return LocalDatesSettings(
      enabled: json['enabled'] == true,
      formats: _pipeListOr(json['formats'], defaultFormats),
      timezones: _pipeListOr(json['timezones'], defaultTimezones),
    );
  }

  final bool enabled;
  final List<String> formats;
  final List<String> timezones;

  Map<String, Object?> toStored() => {
    'enabled': enabled,
    'formats': formats,
    'timezones': timezones,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalDatesSettings &&
          other.enabled == enabled &&
          listEquals(other.formats, formats) &&
          listEquals(other.timezones, timezones);

  @override
  int get hashCode =>
      Object.hash(enabled, Object.hashAll(formats), Object.hashAll(timezones));
}

final class LocalDatesSettingsPersistenceCodec
    extends PluginDataPersistenceCodec<LocalDatesSettings> {
  const LocalDatesSettingsPersistenceCodec();

  @override
  PluginDataKey<LocalDatesSettings> get key => localDatesSettingsDataKey;

  @override
  LocalDatesSettings? decode(Object? value) =>
      LocalDatesSettings.fromStored(value);

  @override
  Object encode(LocalDatesSettings value) => value.toStored();

  @override
  LocalDatesSettings? decodeLegacy(Map<String, dynamic> json) {
    if (!json.containsKey('localDatesEnabled') &&
        !json.containsKey('localDateFormats') &&
        !json.containsKey('localDateTimezones')) {
      return null;
    }
    return LocalDatesSettings(
      enabled: json['localDatesEnabled'] == true,
      formats: _pipeListOr(
        json['localDateFormats'],
        LocalDatesSettings.defaultFormats,
      ),
      timezones: _pipeListOr(
        json['localDateTimezones'],
        LocalDatesSettings.defaultTimezones,
      ),
    );
  }
}

const localDatesSettingsPersistenceCodec = LocalDatesSettingsPersistenceCodec();

extension LocalDatesPluginDataRead on PluginData {
  LocalDatesSettings get localDatesSettings =>
      get(localDatesSettingsDataKey) ?? const LocalDatesSettings();
}

extension SiteConfigLocalDatesSettings on SiteConfig {
  LocalDatesSettings get localDatesSettings => plugins.localDatesSettings;

  bool get localDatesEnabled => localDatesSettings.enabled;

  List<String> get localDateFormats => localDatesSettings.formats;

  List<String> get localDateTimezones => localDatesSettings.timezones;
}

List<String> _pipeListOr(Object? raw, List<String> fallback) {
  final values = switch (raw) {
    final String value => value.split('|'),
    final List<dynamic> value => value.map(jsonText).whereType<String>(),
    _ => const <String>[],
  };
  final normalized = List<String>.unmodifiable(
    values.map((value) => value.trim()).where((value) => value.isNotEmpty),
  );
  return normalized.isEmpty ? List.unmodifiable(fallback) : normalized;
}

Map<String, Object?>? _objectFields(Object? value) {
  if (value is! Map) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}
