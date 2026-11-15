import '../models/reviewable.dart';
import 'plugin_transport.dart';

abstract interface class ReviewApi {
  Future<ReviewablePage> list({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required ReviewFilters filters,
    int offset,
  });

  /// Null when the site answers without a readable item.
  Future<Reviewable?> item({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required int id,
  });

  /// [version] is the lock the item was read at; the site refuses with a
  /// conflict when someone else acted on it since.
  Future<ReviewablePerformResult> perform({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required int id,
    required String action,
    required int version,
  });
}

final class DiscourseReviewApi implements ReviewApi {
  const DiscourseReviewApi(this.transport);
  final PluginApiTransport transport;

  @override
  Future<ReviewablePage> list({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required ReviewFilters filters,
    int offset = 0,
  }) async {
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    return ReviewablePage.fromJson(
      await transport.pluginGetJson(
        siteUrl: siteUrl,
        path: Uri(
          path: '/review.json',
          queryParameters: filters.query(offset: offset),
        ).toString(),
        apiKey: apiKey,
        clientId: clientId,
      ),
      offset: offset,
    );
  }

  @override
  Future<Reviewable?> item({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required int id,
  }) async {
    if (id <= 0) throw ArgumentError.value(id, 'id');
    return reviewableFromDetailJson(
      await transport.pluginGetJson(
        siteUrl: siteUrl,
        path: '/review/$id.json',
        apiKey: apiKey,
        clientId: clientId,
      ),
    );
  }

  @override
  Future<ReviewablePerformResult> perform({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required int id,
    required String action,
    required int version,
  }) async {
    if (id <= 0) throw ArgumentError.value(id, 'id');
    if (version < 0) throw ArgumentError.value(version, 'version');
    if (!RegExp(r'^[a-z_]{1,100}$').hasMatch(action)) {
      throw ArgumentError.value(action, 'action');
    }
    return ReviewablePerformResult.fromJson(
      await transport.pluginWriteJson(
        siteUrl: siteUrl,
        path: Uri(
          path: '/review/$id/perform/$action',
          queryParameters: {'version': '$version'},
        ).toString(),
        method: 'PUT',
        apiKey: apiKey,
        clientId: clientId,
        body: const {},
      ),
    );
  }
}
