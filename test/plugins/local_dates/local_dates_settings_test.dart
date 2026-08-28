import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

final _registry = PluginRegistry([
  LocalDatesPlugin(environment: LocalDateEnvironment.instance),
]);

void main() {
  test('installed plugin decodes its site-settings wire keys', () {
    final config = SiteConfig.fromSettings(const {
      'discourse_local_dates_enabled': true,
      'discourse_local_dates_default_formats': 'LLL|YYYY-MM-DD [at] HH:mm',
      'discourse_local_dates_default_timezones': 'Etc/UTC|Asia/Tokyo',
    }, extensions: _registry);

    expect(
      config.localDatesSettings,
      const LocalDatesSettings(
        enabled: true,
        formats: ['LLL', 'YYYY-MM-DD [at] HH:mm'],
        timezones: ['Etc/UTC', 'Asia/Tokyo'],
      ),
    );
    expect(config.localDatesEnabled, isTrue);
    expect(config.localDateFormats, ['LLL', 'YYYY-MM-DD [at] HH:mm']);
    expect(config.localDateTimezones, ['Etc/UTC', 'Asia/Tokyo']);
  });

  test('namespaced settings round-trip without flat feature keys', () {
    final config = SiteConfig.fromJson({
      'plugins': {
        localDatesSettingsDataKey.id: const {
          'enabled': true,
          'formats': ['LLL', 'YYYY'],
          'timezones': ['Etc/UTC', 'Europe/Paris'],
        },
      },
    }, extensions: _registry);

    final stored = config.toJson(extensions: _registry);
    expect(stored, isNot(contains('localDatesEnabled')));
    expect(stored['plugins'], {
      localDatesSettingsDataKey.id: {
        'enabled': true,
        'formats': ['LLL', 'YYYY'],
        'timezones': ['Etc/UTC', 'Europe/Paris'],
      },
    });
    final restored = SiteConfig.fromJson(stored, extensions: _registry);
    expect(restored, config);
    expect(restored.hashCode, config.hashCode);
  });

  test('legacy flat settings migrate into the plugin namespace', () {
    final config = SiteConfig.fromJson(const {
      'localDatesEnabled': true,
      'localDateFormats': ['LLL', 'YYYY'],
      'localDateTimezones': ['Etc/UTC', 'Asia/Tokyo'],
    }, extensions: _registry);

    expect(
      config.localDatesSettings,
      const LocalDatesSettings(
        enabled: true,
        formats: ['LLL', 'YYYY'],
        timezones: ['Etc/UTC', 'Asia/Tokyo'],
      ),
    );
    expect(config.toJson(extensions: _registry)['plugins'], {
      localDatesSettingsDataKey.id: {
        'enabled': true,
        'formats': ['LLL', 'YYYY'],
        'timezones': ['Etc/UTC', 'Asia/Tokyo'],
      },
    });
  });
}
