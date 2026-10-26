import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/voice/voice_plugin.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:flutter_test/flutter_test.dart';

const _registry = PluginRegistry([VoicePlugin()]);

void main() {
  test('a current site sends its Voice settings under the Live name', () {
    final config = SiteConfig.fromSettings(const {
      'live_enabled': true,
      'live_video_max_publishers': 12,
      'live_livekit_recording_enabled': true,
      'live_max_voice_quality': 'high',
      'live_max_camera_quality': 'standard',
      'live_max_screen_share_quality': 'maximum',
      'live_idle_threshold_minutes': 7,
      'live_afk_auto_mute_threshold_minutes': 17,
      'live_afk_disconnect_threshold_minutes': 37,
      'live_auto_status_enabled': false,
      'live_chat_enabled': false,
      'live_mesh_privacy_warning_enabled': false,
    }, extensions: _registry);

    expect(
      config.voiceSettings,
      const VoiceClientConfig(
        enabled: true,
        videoMaxPublishers: 12,
        recordingEnabled: true,
        maxVoiceQuality: 'high',
        maxCameraQuality: 'standard',
        maxScreenShareQuality: 'maximum',
        idleThresholdMinutes: 7,
        afkAutoMuteThresholdMinutes: 17,
        afkDisconnectThresholdMinutes: 37,
        autoStatusEnabled: false,
        chatEnabled: false,
        meshPrivacyWarningEnabled: false,
      ),
    );
    expect(config.voiceSettings.namespace, VoiceNamespace.live);
  });

  test('a site from before the Live rename sends Voice settings', () {
    final config = SiteConfig.fromSettings(const {
      'voice_enabled': true,
      'voice_video_enabled': true,
      'voice_video_max_publishers': 12,
      'voice_livekit_recording_enabled': true,
      'voice_max_voice_quality': 'high',
      'voice_max_camera_quality': 'standard',
      'voice_max_screen_share_quality': 'maximum',
      'voice_idle_threshold_minutes': 7,
      'voice_afk_auto_mute_threshold_minutes': 17,
      'voice_afk_disconnect_threshold_minutes': 37,
      'voice_auto_status_enabled': false,
      'voice_chat_enabled': false,
      'voice_mesh_privacy_warning_enabled': false,
    }, extensions: _registry);

    expect(
      config.voiceSettings,
      const VoiceClientConfig(
        namespace: VoiceNamespace.voice,
        enabled: true,
        videoEnabled: true,
        videoMaxPublishers: 12,
        recordingEnabled: true,
        maxVoiceQuality: 'high',
        maxCameraQuality: 'standard',
        maxScreenShareQuality: 'maximum',
        idleThresholdMinutes: 7,
        afkAutoMuteThresholdMinutes: 17,
        afkDisconnectThresholdMinutes: 37,
        autoStatusEnabled: false,
        chatEnabled: false,
        meshPrivacyWarningEnabled: false,
      ),
    );
  });

  test('namespaced settings round-trip without the legacy nested field', () {
    final config = SiteConfig.fromJson({
      'plugins': {
        voiceSettingsDataKey.id: const {
          'namespace': 'live',
          'enabled': true,
          'videoEnabled': true,
          'videoMaxPublishers': 10,
          'recordingEnabled': true,
          'maxVoiceQuality': 'high',
          'maxCameraQuality': 'standard',
          'maxScreenShareQuality': 'maximum',
          'idleThresholdMinutes': 8,
          'afkAutoMuteThresholdMinutes': 18,
          'afkDisconnectThresholdMinutes': 38,
          'autoStatusEnabled': false,
          'chatEnabled': false,
          'meshPrivacyWarningEnabled': false,
        },
      },
    }, extensions: _registry);

    final stored = config.toJson(extensions: _registry);
    expect(stored, isNot(contains('voice')));
    expect(stored['plugins'], {
      voiceSettingsDataKey.id: {
        'namespace': 'live',
        'enabled': true,
        'videoEnabled': true,
        'videoMaxPublishers': 10,
        'recordingEnabled': true,
        'maxVoiceQuality': 'high',
        'maxCameraQuality': 'standard',
        'maxScreenShareQuality': 'maximum',
        'idleThresholdMinutes': 8,
        'afkAutoMuteThresholdMinutes': 18,
        'afkDisconnectThresholdMinutes': 38,
        'autoStatusEnabled': false,
        'chatEnabled': false,
        'meshPrivacyWarningEnabled': false,
      },
    });
    expect(SiteConfig.fromJson(stored, extensions: _registry), config);
  });

  test('legacy nested settings migrate into the Voice namespace', () {
    final config = SiteConfig.fromJson(const {
      'voice': {
        'enabled': true,
        'videoEnabled': true,
        'videoMaxPublishers': 6,
        'recordingEnabled': true,
        'maxVoiceQuality': 'standard',
        'maxCameraQuality': 'high',
        'maxScreenShareQuality': 'maximum',
        'idleThresholdMinutes': 4,
        'afkAutoMuteThresholdMinutes': 14,
        'afkDisconnectThresholdMinutes': 34,
        'autoStatusEnabled': true,
        'chatEnabled': false,
      },
    }, extensions: _registry);

    expect(
      config.voiceSettings,
      const VoiceClientConfig(
        namespace: VoiceNamespace.voice,
        enabled: true,
        videoEnabled: true,
        videoMaxPublishers: 6,
        recordingEnabled: true,
        maxVoiceQuality: 'standard',
        maxCameraQuality: 'high',
        maxScreenShareQuality: 'maximum',
        idleThresholdMinutes: 4,
        afkAutoMuteThresholdMinutes: 14,
        afkDisconnectThresholdMinutes: 34,
        autoStatusEnabled: true,
        chatEnabled: false,
      ),
    );
    expect(config.toJson(extensions: _registry)['plugins'], {
      voiceSettingsDataKey.id: {
        'namespace': 'voice',
        'enabled': true,
        'videoEnabled': true,
        'videoMaxPublishers': 6,
        'recordingEnabled': true,
        'maxVoiceQuality': 'standard',
        'maxCameraQuality': 'high',
        'maxScreenShareQuality': 'maximum',
        'idleThresholdMinutes': 4,
        'afkAutoMuteThresholdMinutes': 14,
        'afkDisconnectThresholdMinutes': 34,
        'autoStatusEnabled': true,
        'chatEnabled': false,
        'meshPrivacyWarningEnabled': true,
      },
    });
  });

  test('a config persisted before the Live rename stays on Voice routes', () {
    final config = SiteConfig.fromJson({
      'plugins': {
        voiceSettingsDataKey.id: const {'enabled': true},
      },
    }, extensions: _registry);

    expect(config.voiceSettings.enabled, isTrue);
    expect(config.voiceSettings.namespace, VoiceNamespace.voice);
  });

  test('a site without the plugin is assumed to be current', () {
    final config = SiteConfig.fromSettings(const {}, extensions: _registry);

    expect(config.voiceSettings.enabled, isFalse);
    expect(config.voiceSettings.namespace, VoiceNamespace.live);
  });

  test('site-feature compatibility dispatch uses typed Voice settings', () {
    final enabled = SiteConfig.fromSettings(const {
      'live_enabled': true,
    }, extensions: _registry);
    final enabledBeforeRename = SiteConfig.fromSettings(const {
      'voice_enabled': true,
    }, extensions: _registry);
    final disabled = SiteConfig.fromSettings(const {}, extensions: _registry);

    expect(_registry.siteFeatureEnabled('voice', enabled.plugins), isTrue);
    expect(
      _registry.siteFeatureEnabled('voice', enabledBeforeRename.plugins),
      isTrue,
    );
    expect(_registry.siteFeatureEnabled('voice', disabled.plugins), isFalse);
    expect(
      PluginRegistry.empty.siteFeatureEnabled('voice', enabled.plugins),
      isFalse,
    );
  });
}
