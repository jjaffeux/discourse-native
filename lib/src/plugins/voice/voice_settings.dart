import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

const PluginDataKey<VoiceClientConfig> voiceSettingsDataKey = PluginDataKey(
  owner: 'voice',
  name: 'site-settings',
);

const voiceSettingsPersistenceCodec = VoiceSettingsPersistenceCodec();

/// Voice's client-marked site settings. These shape native controls but do
/// not claim the plugin is available; successful directory discovery remains
/// the capability signal.
@immutable
final class VoiceClientConfig {
  const VoiceClientConfig({
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

  factory VoiceClientConfig.fromSettings(Map<String, dynamic> json) =>
      VoiceClientConfig(
        enabled: json['voice_enabled'] == true,
        videoEnabled: json['voice_video_enabled'] == true,
        videoMaxPublishers: _boundedInt(
          json['voice_video_max_publishers'],
          fallback: 8,
          minimum: 2,
          maximum: 16,
        ),
        recordingEnabled: json['voice_livekit_recording_enabled'] == true,
        maxVoiceQuality: _quality(json['voice_max_voice_quality']),
        maxCameraQuality: _quality(json['voice_max_camera_quality']),
        maxScreenShareQuality: _quality(json['voice_max_screen_share_quality']),
        idleThresholdMinutes: _boundedInt(
          json['voice_idle_threshold_minutes'],
          fallback: 5,
          minimum: 0,
          maximum: 60,
        ),
        afkAutoMuteThresholdMinutes: _boundedInt(
          json['voice_afk_auto_mute_threshold_minutes'],
          fallback: 15,
          minimum: 0,
          maximum: 120,
        ),
        afkDisconnectThresholdMinutes: _boundedInt(
          json['voice_afk_disconnect_threshold_minutes'],
          fallback: 30,
          minimum: 0,
          maximum: 240,
        ),
        autoStatusEnabled: json['voice_auto_status_enabled'] != false,
        chatEnabled: json['voice_chat_enabled'] != false,
      );

  factory VoiceClientConfig.fromJson(Map<String, dynamic> json) =>
      VoiceClientConfig(
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
      other is VoiceClientConfig &&
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

final class VoiceSettingsPersistenceCodec
    extends PluginDataPersistenceCodec<VoiceClientConfig> {
  const VoiceSettingsPersistenceCodec();

  @override
  PluginDataKey<VoiceClientConfig> get key => voiceSettingsDataKey;

  @override
  VoiceClientConfig? decode(Object? value) {
    final json = _jsonMap(value);
    return json == null ? null : VoiceClientConfig.fromJson(json);
  }

  @override
  Object? encode(VoiceClientConfig value) => value.toJson();

  @override
  VoiceClientConfig? decodeLegacy(Map<String, dynamic> json) {
    final legacy = _jsonMap(json['voice']);
    return legacy == null ? null : VoiceClientConfig.fromJson(legacy);
  }
}

extension VoicePluginDataRead on PluginData {
  VoiceClientConfig get voiceSettings =>
      get(voiceSettingsDataKey) ?? const VoiceClientConfig();
}

extension VoiceSiteConfigData on SiteConfig {
  VoiceClientConfig get voiceSettings => plugins.voiceSettings;

  VoiceClientConfig get voice => voiceSettings;
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
