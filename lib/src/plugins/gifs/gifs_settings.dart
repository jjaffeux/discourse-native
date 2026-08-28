import 'package:flutter/foundation.dart';

import '../../models/json.dart';
import '../../models/site_config.dart';
import '../../plugin_api/plugin_data.dart';

const gifsSettingsDataKey = PluginDataKey<GifsSettings>(
  owner: 'gifs',
  name: 'site-settings',
);

/// Client settings for Discourse's authenticated Klipy proxy.
@immutable
final class GifsSettings {
  const GifsSettings({
    this.enabled = false,
    this.fileDetail = defaultFileDetail,
    this.resultLimitEnabled = false,
    this.maxResults = defaultMaxResults,
  });

  static const String defaultFileDetail = 'webp';
  static const int defaultMaxResults = 240;

  factory GifsSettings.fromSiteSettings(Map<String, dynamic> json) =>
      GifsSettings(
        enabled: json['enable_gifs'] == true,
        fileDetail: _fileDetail(json['klipy_file_detail']),
        resultLimitEnabled: json['klipy_limit_infinite_search_results'] == true,
        maxResults: _maxResults(json['klipy_max_results_limit']),
      );

  static GifsSettings? fromStored(Object? value) {
    final json = _objectFields(value);
    if (json == null) return null;
    return GifsSettings(
      enabled: json['enabled'] == true,
      fileDetail: _fileDetail(json['fileDetail']),
      resultLimitEnabled: json['resultLimitEnabled'] == true,
      maxResults: _maxResults(json['maxResults']),
    );
  }

  final bool enabled;
  final String fileDetail;
  final bool resultLimitEnabled;
  final int maxResults;

  Map<String, Object?> toStored() => {
    'enabled': enabled,
    'fileDetail': fileDetail,
    'resultLimitEnabled': resultLimitEnabled,
    'maxResults': maxResults,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GifsSettings &&
          other.enabled == enabled &&
          other.fileDetail == fileDetail &&
          other.resultLimitEnabled == resultLimitEnabled &&
          other.maxResults == maxResults;

  @override
  int get hashCode =>
      Object.hash(enabled, fileDetail, resultLimitEnabled, maxResults);
}

final class GifsSettingsPersistenceCodec
    extends PluginDataPersistenceCodec<GifsSettings> {
  const GifsSettingsPersistenceCodec();

  @override
  PluginDataKey<GifsSettings> get key => gifsSettingsDataKey;

  @override
  GifsSettings? decode(Object? value) => GifsSettings.fromStored(value);

  @override
  Object encode(GifsSettings value) => value.toStored();

  @override
  GifsSettings? decodeLegacy(Map<String, dynamic> json) {
    if (!json.containsKey('gifsEnabled') &&
        !json.containsKey('gifFileDetail') &&
        !json.containsKey('gifResultLimitEnabled') &&
        !json.containsKey('gifMaxResults')) {
      return null;
    }
    return GifsSettings(
      enabled: json['gifsEnabled'] == true,
      fileDetail: _fileDetail(json['gifFileDetail']),
      resultLimitEnabled: json['gifResultLimitEnabled'] == true,
      maxResults: _maxResults(json['gifMaxResults']),
    );
  }
}

const gifsSettingsPersistenceCodec = GifsSettingsPersistenceCodec();

extension SiteConfigGifsSettings on SiteConfig {
  GifsSettings get gifsSettings =>
      plugins.get(gifsSettingsDataKey) ?? const GifsSettings();

  bool get gifsEnabled => gifsSettings.enabled;

  String get gifFileDetail => gifsSettings.fileDetail;

  bool get gifResultLimitEnabled => gifsSettings.resultLimitEnabled;

  int get gifMaxResults => gifsSettings.maxResults;
}

String _fileDetail(Object? raw) => switch (jsonText(raw)) {
  'gif' => 'gif',
  'webp' => 'webp',
  _ => GifsSettings.defaultFileDetail,
};

int _maxResults(Object? raw) => switch (jsonIntOrNull(raw)) {
  final value? when value >= 24 => value,
  _ => GifsSettings.defaultMaxResults,
};

Map<String, Object?>? _objectFields(Object? value) {
  if (value is! Map) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}
