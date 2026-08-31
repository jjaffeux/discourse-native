import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

const _registry = PluginRegistry([GifsPlugin()]);

void main() {
  test('GIF plugin decodes its site-settings wire keys', () {
    final config = SiteConfig.fromSettings(const {
      'enable_gifs': true,
      'klipy_file_detail': 'gif',
      'klipy_limit_infinite_search_results': true,
      'klipy_max_results_limit': 96,
    }, extensions: _registry);

    expect(
      config.gifsSettings,
      const GifsSettings(
        enabled: true,
        fileDetail: 'gif',
        resultLimitEnabled: true,
        maxResults: 96,
      ),
    );
    expect(config.gifsEnabled, isTrue);
    expect(config.gifFileDetail, 'gif');
    expect(config.gifResultLimitEnabled, isTrue);
    expect(config.gifMaxResults, 96);
  });

  test('GIF settings round-trip without flat feature keys', () {
    final config = SiteConfig.fromJson({
      'plugins': {
        gifsSettingsDataKey.id: const {
          'enabled': true,
          'fileDetail': 'gif',
          'resultLimitEnabled': true,
          'maxResults': 72,
        },
      },
    }, extensions: _registry);

    final stored = config.toJson(extensions: _registry);
    expect(stored, isNot(contains('gifsEnabled')));
    expect(stored['plugins'], {
      gifsSettingsDataKey.id: {
        'enabled': true,
        'fileDetail': 'gif',
        'resultLimitEnabled': true,
        'maxResults': 72,
      },
    });
    final restored = SiteConfig.fromJson(stored, extensions: _registry);
    expect(restored, config);
    expect(restored.hashCode, config.hashCode);
  });

  test('legacy flat GIF settings migrate into the plugin namespace', () {
    final config = SiteConfig.fromJson(const {
      'gifsEnabled': true,
      'gifFileDetail': 'gif',
      'gifResultLimitEnabled': true,
      'gifMaxResults': 48,
    }, extensions: _registry);

    expect(
      config.gifsSettings,
      const GifsSettings(
        enabled: true,
        fileDetail: 'gif',
        resultLimitEnabled: true,
        maxResults: 48,
      ),
    );
    expect(config.toJson(extensions: _registry)['plugins'], {
      gifsSettingsDataKey.id: {
        'enabled': true,
        'fileDetail': 'gif',
        'resultLimitEnabled': true,
        'maxResults': 48,
      },
    });
  });
}
