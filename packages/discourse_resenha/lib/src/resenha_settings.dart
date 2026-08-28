import 'package:flutter/foundation.dart';

import 'package:discourse_native/discourse_plugin_sdk.dart';

const PluginDataKey<ResenhaClientConfig> resenhaSettingsDataKey = PluginDataKey(
  owner: 'resenha',
  name: 'site-settings',
);

const resenhaSettingsPersistenceCodec = ResenhaSettingsPersistenceCodec();

/// Resenha's client-marked site settings. These shape native controls but do
/// not claim the plugin is available; successful directory discovery remains
/// the capability signal.
@immutable
final class ResenhaClientConfig {
  const ResenhaClientConfig({
    this.enabled = false,
    this.videoEnabled = false,
    this.videoMaxPublishers = 8,
    this.recordingEnabled = false,
    this.maxVoiceQuality = 'maximum',
    this.maxCameraQuality = 'maximum',
    this.maxScreenShareQuality = 'maximum',
    this.idleThresholdMinutes = 5,
    this.afkAutoMuteThresholdMinutes = 15,
    this.afkDisconnectThresholdMinutes = 30,
    this.autoStatusEnabled = true,
    this.chatEnabled = true,
  });

  factory ResenhaClientConfig.fromSettings(Map<String, dynamic> json) =>
      ResenhaClientConfig(
        enabled: json['resenha_enabled'] == true,
        videoEnabled: json['resenha_video_enabled'] == true,
        videoMaxPublishers: _boundedInt(
          json['resenha_video_max_publishers'],
          fallback: 8,
          minimum: 2,
          maximum: 16,
        ),
        recordingEnabled: json['resenha_livekit_recording_enabled'] == true,
        maxVoiceQuality: _quality(json['resenha_max_voice_quality']),
        maxCameraQuality: _quality(json['resenha_max_camera_quality']),
        maxScreenShareQuality: _quality(
          json['resenha_max_screen_share_quality'],
        ),
        idleThresholdMinutes: _boundedInt(
          json['resenha_idle_threshold_minutes'],
          fallback: 5,
          minimum: 0,
          maximum: 60,
        ),
        afkAutoMuteThresholdMinutes: _boundedInt(
          json['resenha_afk_auto_mute_threshold_minutes'],
          fallback: 15,
          minimum: 0,
          maximum: 120,
        ),
        afkDisconnectThresholdMinutes: _boundedInt(
          json['resenha_afk_disconnect_threshold_minutes'],
          fallback: 30,
          minimum: 0,
          maximum: 240,
        ),
        autoStatusEnabled: json['resenha_auto_status_enabled'] != false,
        chatEnabled: json['resenha_chat_enabled'] != false,
      );

  factory ResenhaClientConfig.fromJson(Map<String, dynamic> json) =>
      ResenhaClientConfig(
        enabled: json['enabled'] == true,
        videoEnabled: json['videoEnabled'] == true,
        videoMaxPublishers: _boundedInt(
          json['videoMaxPublishers'],
          fallback: 8,
          minimum: 2,
          maximum: 16,
        ),
        recordingEnabled: json['recordingEnabled'] == true,
        maxVoiceQuality: _quality(json['maxVoiceQuality']),
        maxCameraQuality: _quality(json['maxCameraQuality']),
        maxScreenShareQuality: _quality(json['maxScreenShareQuality']),
        idleThresholdMinutes: _boundedInt(
          json['idleThresholdMinutes'],
          fallback: 5,
          minimum: 0,
          maximum: 60,
        ),
        afkAutoMuteThresholdMinutes: _boundedInt(
          json['afkAutoMuteThresholdMinutes'],
          fallback: 15,
          minimum: 0,
          maximum: 120,
        ),
        afkDisconnectThresholdMinutes: _boundedInt(
          json['afkDisconnectThresholdMinutes'],
          fallback: 30,
          minimum: 0,
          maximum: 240,
        ),
        autoStatusEnabled: json['autoStatusEnabled'] != false,
        chatEnabled: json['chatEnabled'] != false,
      );

  final bool enabled;
  final bool videoEnabled;
  final int videoMaxPublishers;
  final bool recordingEnabled;
  final String maxVoiceQuality;
  final String maxCameraQuality;
  final String maxScreenShareQuality;
  final int idleThresholdMinutes;
  final int afkAutoMuteThresholdMinutes;
  final int afkDisconnectThresholdMinutes;
  final bool autoStatusEnabled;
  final bool chatEnabled;

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'videoEnabled': videoEnabled,
    'videoMaxPublishers': videoMaxPublishers,
    'recordingEnabled': recordingEnabled,
    'maxVoiceQuality': maxVoiceQuality,
    'maxCameraQuality': maxCameraQuality,
    'maxScreenShareQuality': maxScreenShareQuality,
    'idleThresholdMinutes': idleThresholdMinutes,
    'afkAutoMuteThresholdMinutes': afkAutoMuteThresholdMinutes,
    'afkDisconnectThresholdMinutes': afkDisconnectThresholdMinutes,
    'autoStatusEnabled': autoStatusEnabled,
    'chatEnabled': chatEnabled,
  };

  @override
  bool operator ==(Object other) =>
      other is ResenhaClientConfig &&
      other.enabled == enabled &&
      other.videoEnabled == videoEnabled &&
      other.videoMaxPublishers == videoMaxPublishers &&
      other.recordingEnabled == recordingEnabled &&
      other.maxVoiceQuality == maxVoiceQuality &&
      other.maxCameraQuality == maxCameraQuality &&
      other.maxScreenShareQuality == maxScreenShareQuality &&
      other.idleThresholdMinutes == idleThresholdMinutes &&
      other.afkAutoMuteThresholdMinutes == afkAutoMuteThresholdMinutes &&
      other.afkDisconnectThresholdMinutes == afkDisconnectThresholdMinutes &&
      other.autoStatusEnabled == autoStatusEnabled &&
      other.chatEnabled == chatEnabled;

  @override
  int get hashCode => Object.hash(
    enabled,
    videoEnabled,
    videoMaxPublishers,
    recordingEnabled,
    maxVoiceQuality,
    maxCameraQuality,
    maxScreenShareQuality,
    idleThresholdMinutes,
    afkAutoMuteThresholdMinutes,
    afkDisconnectThresholdMinutes,
    autoStatusEnabled,
    chatEnabled,
  );

  static String _quality(Object? value) => switch (jsonText(value)) {
    'standard' => 'standard',
    'high' => 'high',
    'maximum' => 'maximum',
    _ => 'maximum',
  };

  static int _boundedInt(
    Object? value, {
    required int fallback,
    required int minimum,
    required int maximum,
  }) {
    final parsed = jsonIntOrNull(value);
    if (parsed == null || parsed < minimum || parsed > maximum) return fallback;
    return parsed;
  }
}

final class ResenhaSettingsPersistenceCodec
    extends PluginDataPersistenceCodec<ResenhaClientConfig> {
  const ResenhaSettingsPersistenceCodec();

  @override
  PluginDataKey<ResenhaClientConfig> get key => resenhaSettingsDataKey;

  @override
  ResenhaClientConfig? decode(Object? value) {
    final json = _jsonMap(value);
    return json == null ? null : ResenhaClientConfig.fromJson(json);
  }

  @override
  Object? encode(ResenhaClientConfig value) => value.toJson();

  @override
  ResenhaClientConfig? decodeLegacy(Map<String, dynamic> json) {
    final legacy = _jsonMap(json['resenha']);
    return legacy == null ? null : ResenhaClientConfig.fromJson(legacy);
  }
}

extension ResenhaPluginDataRead on PluginData {
  ResenhaClientConfig get resenhaSettings =>
      get(resenhaSettingsDataKey) ?? const ResenhaClientConfig();
}

extension ResenhaSiteConfigData on SiteConfig {
  ResenhaClientConfig get resenhaSettings => plugins.resenhaSettings;

  ResenhaClientConfig get resenha => resenhaSettings;
}

Map<String, dynamic>? _jsonMap(Object? value) {
  if (value is! Map) return null;
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}
