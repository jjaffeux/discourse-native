import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_plugin.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_settings.dart';
import 'package:flutter_test/flutter_test.dart';

const _registry = PluginRegistry([ResenhaPlugin()]);

void main() {
  test('installed plugin decodes Resenha site-settings wire keys', () {
    final config = SiteConfig.fromSettings(const {
      'resenha_enabled': true,
      'resenha_video_enabled': true,
      'resenha_video_max_publishers': 12,
      'resenha_livekit_recording_enabled': true,
      'resenha_max_voice_quality': 'high',
      'resenha_max_camera_quality': 'standard',
      'resenha_max_screen_share_quality': 'maximum',
      'resenha_idle_threshold_minutes': 7,
      'resenha_afk_auto_mute_threshold_minutes': 17,
      'resenha_afk_disconnect_threshold_minutes': 37,
      'resenha_auto_status_enabled': false,
      'resenha_chat_enabled': false,
    }, extensions: _registry);

    expect(
      config.resenhaSettings,
      const ResenhaClientConfig(
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
        resenhaSettingsDataKey.id: const {
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
    expect(stored, isNot(contains('resenha')));
    expect(stored['plugins'], {
      resenhaSettingsDataKey.id: {
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

  test('legacy nested settings migrate into the Resenha namespace', () {
    final config = SiteConfig.fromJson(const {
      'resenha': {
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

    expect(config.resenhaSettings.enabled, isTrue);
    expect(config.resenhaSettings.videoMaxPublishers, 6);
    expect(config.resenhaSettings.maxCameraQuality, 'high');
    expect(config.resenhaSettings.chatEnabled, isFalse);
    expect(
      config.toJson(extensions: _registry)['plugins'],
      contains(resenhaSettingsDataKey.id),
    );
  });

  test('site-feature compatibility dispatch uses typed Resenha settings', () {
    final enabled = SiteConfig.fromSettings(const {
      'resenha_enabled': true,
    }, extensions: _registry);
    final disabled = SiteConfig.fromSettings(const {}, extensions: _registry);

    expect(_registry.siteFeatureEnabled('resenha', enabled.plugins), isTrue);
    expect(_registry.siteFeatureEnabled('resenha', disabled.plugins), isFalse);
    expect(
      PluginRegistry.empty.siteFeatureEnabled('resenha', enabled.plugins),
      isFalse,
    );
  });
}
