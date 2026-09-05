import '../models/group.dart';
import '../models/user_directory.dart';
import '../plugin_api/discourse_model_codec.dart';
import 'groups_api.dart';
import 'plugin_transport.dart';

final class UserDirectoryApi {
  const UserDirectoryApi(this._transport, this._models);

  static const int maximumPage = 10;
  static const int maximumQueryLength = 255;

  final PluginApiTransport _transport;
  final DiscourseModelCodec _models;

  Future<UserDirectoryMetadata> metadata({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    Iterable<String> fallbackGroupNames = const [],
  }) async {
    final columns = await _get(
      siteUrl: siteUrl,
      path: '/directory-columns.json',
      apiKey: apiKey,
      clientId: clientId,
    );
    var groupNames = <String>{...fallbackGroupNames};
    try {
      final groupPage = await GroupsApi(_transport, _models).directory(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        order: 'name',
      );
      groupNames = {
        ...groupNames,
        for (final Group group in groupPage.groups) group.name,
      };
    } catch (_) {
      // Group discovery is an enhancement to the directory filter. The
      // directory remains useful when a site hides or disables /groups.json.
    }
    return UserDirectoryMetadata.fromColumns(columns, groupNames: groupNames);
  }

  Future<UserDirectoryPage> directory({
    required String siteUrl,
    required UserDirectoryPeriod period,
    required List<UserDirectoryColumn> columns,
    String? apiKey,
    String? clientId,
    int page = 0,
    String order = 'likes_received',
    bool ascending = false,
    String? name,
    String? group,
  }) async {
    if (page < 0 || page > maximumPage) {
      throw RangeError.range(page, 0, maximumPage, 'page');
    }
    final normalizedOrder = _query(order, 'order', required: true)!;
    final normalizedName = _query(name, 'name');
    final normalizedGroup = _query(group, 'group');
    final userFieldIds = <int>[
      for (final column in columns)
        if (column.type == UserDirectoryColumnType.userField &&
            column.userFieldId != null)
          column.userFieldId!,
    ];
    final pluginColumnIds = <int>[
      for (final column in columns)
        if (column.type == UserDirectoryColumnType.plugin && column.id > 0)
          column.id,
    ];
    final body = await _get(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path: _withQuery('/directory_items.json', {
        'period': period.queryValue,
        'order': normalizedOrder,
        // Core treats the presence of this parameter as ascending. Omitting
        // it is therefore materially different from sending `asc=false`.
        if (ascending) 'asc': 'true',
        if (page > 0) 'page': '$page',
        'name': ?normalizedName,
        'group': ?normalizedGroup,
        if (userFieldIds.isNotEmpty) 'user_field_ids': userFieldIds.join('|'),
        if (pluginColumnIds.isNotEmpty)
          'plugin_column_ids': pluginColumnIds.join('|'),
      }),
    );
    return UserDirectoryPage.fromWire(body, siteUrl);
  }

  Future<Map<String, dynamic>> _get({
    required String siteUrl,
    required String path,
    required String? apiKey,
    required String? clientId,
  }) => _transport.pluginGetJson(
    siteUrl: siteUrl,
    path: path,
    apiKey: apiKey,
    clientId: clientId,
  );

  static String _withQuery(String path, Map<String, dynamic> query) =>
      Uri.parse(path).replace(queryParameters: query).toString();

  static String? _query(String? value, String name, {bool required = false}) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      if (required) {
        throw ArgumentError.value(value, name, 'A value is required.');
      }
      return null;
    }
    if (normalized.length > maximumQueryLength) {
      throw ArgumentError.value(value, name, 'Value is too long.');
    }
    return normalized;
  }
}
