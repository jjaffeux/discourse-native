import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/plugin_transport.dart';
import 'package:discourse_native/src/plugin_api/category_settings.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://forum.example/community';
const _credential = PluginRequestCredentials(apiKey: 'key', clientId: 'client');

void main() {
  test(
    'reads authoritative category edit permission from the show endpoint',
    () async {
      final transport = _Transport()..response = _category(canEdit: false);
      final result = await PluginCategorySettingsApi(
        transport,
      ).read(siteUrl: _site, categoryId: 3, credentials: _credential);
      expect(result.canEdit, isFalse);
      expect(result.id, 3);
      expect(transport.gets.single, (site: _site, path: '/c/3/show.json'));
      await expectLater(
        PluginCategorySettingsApi(transport).save(
          siteUrl: _site,
          snapshot: result,
          settings: {'new_setting': true},
          credentials: _credential,
        ),
        throwsA(isA<WriteException>()),
      );
      expect(transport.writes, isEmpty);
    },
  );

  test(
    'saving one setting preserves unrelated settings and custom fields',
    () async {
      final transport = _Transport()..response = _category();
      final api = PluginCategorySettingsApi(transport);
      final initial = await api.read(
        siteUrl: _site,
        categoryId: 3,
        credentials: _credential,
      );
      transport.response = _category(
        settings: {
          'known': false,
          'unknown': {
            'future': [3, 4],
          },
        },
      );
      final result = await api.save(
        siteUrl: _site,
        snapshot: initial,
        settings: {'known': false},
        customFields: {'changed': 'new'},
        credentials: _credential,
      );
      expect(result.settings['known'], isFalse);
      expect(result.settings['unknown'], {
        'future': [3, 4],
      });
      expect(transport.writes.single.path, '/categories/3.json');
      expect(transport.writes.single.method, 'PUT');
      expect(transport.writes.single.body, {
        'category_setting_attributes': {'known': false},
        'custom_fields': {'changed': 'new'},
      });
      expect(initial.settings['known'], isTrue);
    },
  );

  test(
    'snapshots own immutable nested values and reject a different category',
    () async {
      final transport = _Transport()..response = _category();
      final api = PluginCategorySettingsApi(transport);
      final result = await api.read(
        siteUrl: _site,
        categoryId: 3,
        credentials: _credential,
      );
      final settings =
          ((transport.response['category'] as Map)['category_setting'] as Map);
      (settings['unknown'] as Map)['future'] = [99];
      expect(result.settings['unknown'], {
        'future': [1, 2],
      });
      expect(() => result.settings['extra'] = true, throwsUnsupportedError);
      transport.response = {
        'category': {'id': 4, 'name': 'Wrong'},
      };
      await expectLater(
        api.read(siteUrl: _site, categoryId: 3, credentials: _credential),
        throwsFormatException,
      );
    },
  );
}

Map<String, dynamic> _category({
  bool canEdit = true,
  Map<String, Object?>? settings,
}) => {
  'category': {
    'id': 3,
    'name': 'Sailing',
    if (canEdit) 'can_edit': true,
    'category_setting':
        settings ??
        {
          'known': true,
          'unknown': {
            'future': [1, 2],
          },
        },
    'custom_fields': {'other_plugin': 'keep', 'changed': 'old'},
  },
};

final class _Transport implements PluginApiTransport {
  Map<String, dynamic> response = {};
  final gets = <({String site, String path})>[];
  final writes = <({String path, String method, Map<String, Object?> body})>[];

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    gets.add((site: siteUrl, path: path));
    return response;
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    writes.add((path: path, method: method, body: body));
    return response;
  }
}
