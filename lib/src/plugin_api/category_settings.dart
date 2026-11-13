import '../data/plugin_transport.dart';
import '../data/write_failure.dart';
import '../models/preserved_json.dart';
import 'core_plugin_host.dart';

final class PluginCategorySettingsSnapshot {
  PluginCategorySettingsSnapshot({
    required this.id,
    required this.name,
    required this.canEdit,
    required Map<String, Object?> settings,
    required Map<String, Object?> customFields,
  }) : settings = _immutableObject(settings),
       customFields = _immutableObject(customFields);

  final int id;
  final String name;
  final bool canEdit;
  final Map<String, Object?> settings;
  final Map<String, Object?> customFields;
}

final class PluginCategorySettingsApi {
  const PluginCategorySettingsApi(this.transport);

  final PluginApiTransport transport;

  Future<PluginCategorySettingsSnapshot> read({
    required String siteUrl,
    required int categoryId,
    required PluginRequestCredentials credentials,
  }) async {
    if (categoryId <= 0) throw ArgumentError.value(categoryId, 'categoryId');
    final response = await credentials.run(
      () => transport.pluginGetJson(
        siteUrl: siteUrl,
        path: '/c/$categoryId/show.json',
        apiKey: credentials.apiKey,
        clientId: credentials.clientId,
      ),
    );
    return _decode(response, categoryId);
  }

  Future<PluginCategorySettingsSnapshot> save({
    required String siteUrl,
    required PluginCategorySettingsSnapshot snapshot,
    required Map<String, Object?> settings,
    Map<String, Object?> customFields = const {},
    required PluginRequestCredentials credentials,
  }) async {
    final apiKey = credentials.apiKey;
    if (!snapshot.canEdit || apiKey == null) {
      throw const WriteException(WriteFailure.forbidden);
    }
    final response = await credentials.run(
      () => transport.pluginWriteJson(
        siteUrl: siteUrl,
        path: '/categories/${snapshot.id}.json',
        method: 'PUT',
        apiKey: apiKey,
        clientId: credentials.clientId,
        body: {
          'category_setting_attributes': _immutableObject(settings),
          if (customFields.isNotEmpty)
            'custom_fields': _immutableObject(customFields),
        },
      ),
    );
    return _decode(response, snapshot.id);
  }

  static PluginCategorySettingsSnapshot _decode(
    Map<String, dynamic> response,
    int expectedId,
  ) {
    final category = response['category'];
    if (category is! Map || category['id'] != expectedId) {
      throw const FormatException('Invalid category settings identity.');
    }
    final name = category['name'];
    if (name is! String) {
      throw const FormatException('Invalid category settings name.');
    }
    return PluginCategorySettingsSnapshot(
      id: expectedId,
      name: name,
      canEdit: category['can_edit'] == true,
      settings: _immutableObject(category['category_setting']),
      customFields: _immutableObject(category['custom_fields']),
    );
  }
}

Map<String, Object?> _immutableObject(Object? value) {
  if (value == null) return const {};
  final frozen = freezeJson(value);
  if (!frozen.valid || frozen.value is! Map<String, Object?>) {
    throw const FormatException('Invalid category settings object.');
  }
  return frozen.value! as Map<String, Object?>;
}
