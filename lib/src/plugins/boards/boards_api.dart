import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'boards_data.dart';

final class BoardsApi {
  const BoardsApi(this.transport);
  final PluginApiTransport transport;

  Future<Map<String, dynamic>> _get(
    String site,
    String path,
    PluginRequestCredentials credentials,
  ) => transport.pluginGetJson(
    siteUrl: site,
    path: '/boards/api/$path',
    apiKey: credentials.apiKey,
    clientId: credentials.clientId,
  );

  Future<List<BoardSnapshot>> list(
    String site,
    PluginRequestCredentials credentials, {
    int? topicId,
  }) async {
    final json = await _get(
      site,
      topicId == null
          ? 'boards.json'
          : 'boards/available.json?allowed_permissions=edit,manage&topic_id=$topicId',
      credentials,
    );
    if (json['boards'] is! List) {
      throw const FormatException('Invalid board directory');
    }
    return List.unmodifiable([
      for (final raw in json['boards'] as List) ?BoardSnapshot.decode(raw),
    ]);
  }

  Future<BoardSnapshot> read(
    String site,
    int id,
    PluginRequestCredentials credentials,
  ) async {
    final json = await _get(site, 'boards/$id.json', credentials);
    final board = BoardSnapshot.decode(json['board'], columns: json['columns']);
    if (board == null || board.id != id || json['columns'] is! List) {
      throw const FormatException('Invalid board response');
    }
    return board;
  }

  Future<BoardConstraintCheck> constraints(
    String site,
    int boardId,
    int topicId,
    int columnId,
    PluginRequestCredentials credentials,
  ) async {
    final json = await write(
      site,
      'boards/$boardId/check-constraint-mismatches',
      credentials,
      method: 'PUT',
      body: {'topic_id': topicId, 'target_column_id': columnId},
    );
    return BoardConstraintCheck(
      categoryIds: boardIds(json['categories_needed']),
      tagNames: boardTexts(json['tags_needed']),
    );
  }

  Future<Map<String, dynamic>> write(
    String site,
    String path,
    PluginRequestCredentials credentials, {
    required String method,
    required Map<String, Object?> body,
  }) {
    final key = credentials.apiKey;
    if (key == null) throw const WriteException(WriteFailure.forbidden);
    return transport.pluginWriteJson(
      siteUrl: site,
      path: '/boards/api/$path',
      apiKey: key,
      clientId: credentials.clientId,
      method: method,
      body: body,
    );
  }
}
