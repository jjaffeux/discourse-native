import '../../data/plugin_transport.dart';
import '../../models/json.dart';
import 'gif.dart';
import 'gifs_api.dart';

final class GifsApiClient implements GifsApi {
  const GifsApiClient(this._transport);

  final PluginApiTransport _transport;

  @override
  Future<List<GifCategory>> gifCategories({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final body = await _transport.pluginGetJson(
      siteUrl: siteUrl,
      path: '/gifs/categories.json',
      apiKey: apiKey,
      clientId: clientId,
    );
    return List.unmodifiable(
      jsonArray(
        body['tags'],
      ).map(GifCategory.fromJson).whereType<GifCategory>(),
    );
  }

  @override
  Future<GifSearchPage> searchGifs({
    required String siteUrl,
    required String apiKey,
    required String query,
    required String fileDetail,
    String position = '0',
    String? clientId,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || normalizedQuery.length > 100) {
      throw ArgumentError.value(
        query,
        'query',
        'Must contain between 1 and 100 characters.',
      );
    }
    final normalizedPosition = position.trim();
    if (normalizedPosition.isEmpty) {
      throw ArgumentError.value(
        position,
        'position',
        'Must be a non-empty Klipy cursor.',
      );
    }
    if (fileDetail != 'webp' && fileDetail != 'gif') {
      throw ArgumentError.value(
        fileDetail,
        'fileDetail',
        "Must be either 'webp' or 'gif'.",
      );
    }
    final path = Uri(
      path: '/gifs/search.json',
      queryParameters: {'q': normalizedQuery, 'pos': normalizedPosition},
    ).toString();
    final body = await _transport.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
    return GifSearchPage.fromJson(body, fileDetail: fileDetail);
  }
}
