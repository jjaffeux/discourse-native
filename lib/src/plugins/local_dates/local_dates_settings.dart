import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

const localDatesSettingsDataKey = PluginDataKey<LocalDatesSettings>(
  owner: 'discourse-local-dates',
  name: 'site-settings',
);

@immutable
final class LocalDatesSettings {
  const LocalDatesSettings({
    this.enabled = false,
    this.emailFormat = 'llll z',
    this.emailTimezone = 'Etc/UTC',
    this.formats = defaultFormats,
    this.timezones = defaultTimezones,
  });

  static const List<String> defaultFormats = ['LLL', 'LTS', 'LL', 'LLLL'];
  static const List<String> defaultTimezones = [
    'Europe/Paris',
    'America/Los_Angeles',
  ];

  // The web client previews UTC when the site's timezone list is blank; the
  // plugin's own defaults only apply while the setting has not been sent.
  static const List<String> _clearedTimezones = ['Etc/UTC'];

  factory LocalDatesSettings.fromSiteSettings(Map<String, dynamic> json) =>
      LocalDatesSettings(
        enabled: json['discourse_local_dates_enabled'] == true,
        emailFormat:
            jsonText(json['discourse_local_dates_email_format']) ??
            appL10n.llllZ,
        emailTimezone:
            jsonText(json['discourse_local_dates_email_timezone']) ?? 'Etc/UTC',
        formats: _listSetting(
          json['discourse_local_dates_default_formats'],
          absent: defaultFormats,
        ),
        timezones: _listSetting(
          json['discourse_local_dates_default_timezones'],
          absent: defaultTimezones,
          cleared: _clearedTimezones,
        ),
      );

  static LocalDatesSettings? fromStored(Object? value) {
    final json = jsonObjectFields(value);
    if (json == null) return null;
    return LocalDatesSettings(
      enabled: json['enabled'] == true,
      emailFormat: jsonText(json['emailFormat']) ?? appL10n.llllZ,
      emailTimezone: jsonText(json['emailTimezone']) ?? 'Etc/UTC',
      formats: _listSetting(json['formats'], absent: defaultFormats),
      timezones: _listSetting(
        json['timezones'],
        absent: defaultTimezones,
        cleared: _clearedTimezones,
      ),
    );
  }

  final bool enabled;
  final String emailFormat, emailTimezone;
  final List<String> formats;
  final List<String> timezones;

  Map<String, Object?> toStored() => {
    'enabled': enabled,
    'emailFormat': emailFormat,
    'emailTimezone': emailTimezone,
    'formats': formats,
    'timezones': timezones,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalDatesSettings &&
          other.enabled == enabled &&
          other.emailFormat == emailFormat &&
          other.emailTimezone == emailTimezone &&
          listEquals(other.formats, formats) &&
          listEquals(other.timezones, timezones);

  @override
  int get hashCode => Object.hash(
    emailFormat,
    emailTimezone,
    enabled,
    Object.hashAll(formats),
    Object.hashAll(timezones),
  );
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
      formats: _listSetting(
        json['localDateFormats'],
        absent: LocalDatesSettings.defaultFormats,
      ),
      timezones: _listSetting(
        json['localDateTimezones'],
        absent: LocalDatesSettings.defaultTimezones,
        cleared: LocalDatesSettings._clearedTimezones,
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

/// A list setting the site sent is the site's answer even when an admin
/// cleared it: [absent] only stands in for a value that is missing or not a
/// list, and a sent list with no entries means [cleared].
List<String> _listSetting(
  Object? raw, {
  required List<String> absent,
  List<String> cleared = const [],
}) {
  final values = switch (raw) {
    final String value => value.split('|'),
    final List<dynamic> value => value.map(jsonText).whereType<String>(),
    _ => null,
  };
  if (values == null) return List.unmodifiable(absent);
  final normalized = List<String>.unmodifiable(
    values.map((value) => value.trim()).where((value) => value.isNotEmpty),
  );
  return normalized.isEmpty ? List.unmodifiable(cleared) : normalized;
}
