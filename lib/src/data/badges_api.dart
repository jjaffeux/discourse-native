import '../models/badge.dart';
import '../models/badge_route.dart';
import '../models/json.dart';
import 'plugin_transport.dart';

final class BadgesApi {
  const BadgesApi(this._transport);

  static const int pageSize = 96;
  final PluginApiTransport _transport;

  Future<BadgeCatalog> catalog({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async => BadgeCatalog.fromJson(
    await _get(siteUrl, '/badges.json?only_listable=true', apiKey, clientId),
    siteUrl,
  );

  Future<DiscourseBadge> badge({
    required String siteUrl,
    required int id,
    String? apiKey,
    String? clientId,
  }) async {
    if (id <= 0) throw ArgumentError.value(id, 'id');
    final body = await _get(siteUrl, '/badges/$id.json', apiKey, clientId);
    final badge = DiscourseBadge.fromJson(jsonObject(body['badge']), siteUrl);
    if (badge.id != id) throw const FormatException('Missing badge');
    return badge;
  }

  Future<BadgeGrantPage> grants({
    required String siteUrl,
    required BadgeRoute route,
    int offset = 0,
    String? apiKey,
    String? clientId,
  }) async {
    if (route.isDirectory || offset < 0) {
      throw ArgumentError('Invalid badge grants request');
    }
    final path = Uri(
      path: '/user_badges.json',
      queryParameters: {
        'badge_id': '${route.badgeId}',
        'offset': '$offset',
        if (route.username != null) 'username': route.username!,
      },
    ).toString();
    return BadgeGrantPage.fromJson(
      await _get(siteUrl, path, apiKey, clientId),
      siteUrl,
    );
  }

  Future<Map<String, dynamic>> _get(
    String siteUrl,
    String path,
    String? apiKey,
    String? clientId,
  ) => _transport.pluginGetJson(
    siteUrl: siteUrl,
    path: path,
    apiKey: apiKey,
    clientId: clientId,
  );
}
