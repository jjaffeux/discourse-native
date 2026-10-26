import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

const PluginDataKey<VoiceClientConfig> voiceSettingsDataKey = PluginDataKey(
  owner: 'voice',
  name: 'site-settings',
);

const voiceSettingsPersistenceCodec = VoiceSettingsPersistenceCodec();

/// The name a site's server plugin routes, publishes and configures under.
/// Discourse renamed the plugin from Voice to Live (discourse 8560d4ac0e9);
/// sites from before the rename still answer under `voice`.
enum VoiceNamespace {
  live,
  voice;

  /// The site-relative root of the plugin's routes and message-bus channels.
  String get root => '/$name';
}

/// Voice's client-marked site settings. These shape native controls but do
/// not claim the plugin is available; successful directory discovery remains
/// the capability signal.
@immutable
final class VoiceClientConfig {
  const VoiceClientConfig({
    this.namespace = VoiceNamespace.live,
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
    this.meshPrivacyWarningEnabled = true,
  });

  /// Every client setting carries the server plugin's name, so the one that
  /// enables it tells which name the site answers under. A site without the
  /// plugin sends neither and is treated as current.
  factory VoiceClientConfig.fromSettings(Map<String, dynamic> json) {
    final namespace =
        json.containsKey('voice_enabled') && !json.containsKey('live_enabled')
        ? VoiceNamespace.voice
        : VoiceNamespace.live;
    Object? setting(String suffix) => json['${namespace.name}_$suffix'];
    return VoiceClientConfig(
      namespace: namespace,
      enabled: setting('enabled') == true,
      videoEnabled: setting('video_enabled') == true,
      videoMaxPublishers: _boundedInt(
        setting('video_max_publishers'),
        fallback: 8,
        minimum: 2,
        maximum: 16,
      ),
      recordingEnabled: setting('livekit_recording_enabled') == true,
      maxVoiceQuality: _quality(setting('max_voice_quality')),
      maxCameraQuality: _quality(setting('max_camera_quality')),
      maxScreenShareQuality: _quality(setting('max_screen_share_quality')),
      idleThresholdMinutes: _boundedInt(
        setting('idle_threshold_minutes'),
        fallback: 5,
        minimum: 0,
        maximum: 60,
      ),
      afkAutoMuteThresholdMinutes: _boundedInt(
        setting('afk_auto_mute_threshold_minutes'),
        fallback: 15,
        minimum: 0,
        maximum: 120,
      ),
      afkDisconnectThresholdMinutes: _boundedInt(
        setting('afk_disconnect_threshold_minutes'),
        fallback: 30,
        minimum: 0,
        maximum: 240,
      ),
      autoStatusEnabled: setting('auto_status_enabled') != false,
      chatEnabled: setting('chat_enabled') != false,
      meshPrivacyWarningEnabled:
          setting('mesh_privacy_warning_enabled') != false,
    );
  }

  /// A config stored without its namespace was read from `voice_*` settings,
  /// so any site it found Voice enabled on predates the rename.
  factory VoiceClientConfig.fromJson(Map<String, dynamic> json) =>
      VoiceClientConfig(
        namespace:
            VoiceNamespace.values.asNameMap()[json['namespace']] ??
            VoiceNamespace.voice,
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
        meshPrivacyWarningEnabled: json['meshPrivacyWarningEnabled'] != false,
      );

  final VoiceNamespace namespace;
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

  /// Whether to warn before joining a peer-to-peer room that other
  /// participants may learn the user's IP address.
  final bool meshPrivacyWarningEnabled;

  Map<String, Object?> toJson() => {
    'namespace': namespace.name,
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
    'meshPrivacyWarningEnabled': meshPrivacyWarningEnabled,
  };

  @override
  bool operator ==(Object other) =>
      other is VoiceClientConfig &&
      other.namespace == namespace &&
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
      other.chatEnabled == chatEnabled &&
      other.meshPrivacyWarningEnabled == meshPrivacyWarningEnabled;

  @override
  int get hashCode => Object.hash(
    namespace,
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
    meshPrivacyWarningEnabled,
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
    final json = jsonObjectFields(value);
    return json == null ? null : VoiceClientConfig.fromJson(json);
  }

  @override
  Object? encode(VoiceClientConfig value) => value.toJson();

  @override
  VoiceClientConfig? decodeLegacy(Map<String, dynamic> json) {
    final legacy = jsonObjectFields(json['voice']);
    return legacy == null ? null : VoiceClientConfig.fromJson(legacy);
  }
}

extension VoicePluginDataRead on PluginData {
  VoiceClientConfig get voiceSettings =>
      get(voiceSettingsDataKey) ?? const VoiceClientConfig();
}

extension VoiceSiteConfigData on SiteConfig {
  VoiceClientConfig get voiceSettings => plugins.voiceSettings;
}
