import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/voice/voice_plugin.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:flutter_test/flutter_test.dart';

const _registry = PluginRegistry([VoicePlugin()]);

void main() {
  test('installed plugin decodes Voice site-settings wire keys', () {
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
    }, extensions: _registry);

    expect(
      config.voiceSettings,
      const VoiceClientConfig(
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
      ),
    );
  });

  test('namespaced settings round-trip without the legacy nested field', () {
    final config = SiteConfig.fromJson({
      'plugins': {
        voiceSettingsDataKey.id: const {
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
        },
      },
    }, extensions: _registry);

    final stored = config.toJson(extensions: _registry);
    expect(stored, isNot(contains('voice')));
    expect(stored['plugins'], {
      voiceSettingsDataKey.id: {
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
    });
  });

  test('site-feature compatibility dispatch uses typed Voice settings', () {
    final enabled = SiteConfig.fromSettings(const {
      'voice_enabled': true,
    }, extensions: _registry);
    final disabled = SiteConfig.fromSettings(const {}, extensions: _registry);

    expect(_registry.siteFeatureEnabled('voice', enabled.plugins), isTrue);
    expect(_registry.siteFeatureEnabled('voice', disabled.plugins), isFalse);
    expect(
      PluginRegistry.empty.siteFeatureEnabled('voice', enabled.plugins),
      isFalse,
    );
  });
}
