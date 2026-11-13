import 'package:discourse_native/l10n/strings.dart';

import 'discourse_transport.dart';
import 'json_decode.dart';
import 'plugin_transport.dart';
import 'site_lookup_failure.dart';

/// Adapts public plugin HTTP capabilities to the application's shared transport.
final class DiscoursePluginTransport
    implements
        PluginApiTransport,
        PluginJsonListTransport,
        PluginCancellableJsonTransport,
        PluginJsonQueryTransport,
        PluginLongRunningWriteTransport,
        PluginTextTransport {
  DiscoursePluginTransport(
    this._transport, {
    this.searchTimeout = const Duration(seconds: 30),
  }) : assert(searchTimeout > Duration.zero);

  final DiscourseTransport _transport;
  final Duration searchTimeout;

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async => _transport.getObject(
    _resolvePluginPath(siteUrl, path),
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
    requestTimeout: _isForumSearchPath(path) ? searchTimeout : null,
  );

  @override
  Future<Map<String, dynamic>> pluginGetJsonCancellable({
    required String siteUrl,
    required String path,
    required String? apiKey,
    required Future<void> abortTrigger,
    String? clientId,
  }) async => _transport.getObject(
    _resolvePluginPath(siteUrl, path),
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
    requestTimeout: _isForumSearchPath(path) ? searchTimeout : null,
    abortTrigger: abortTrigger,
  );

  static bool _isForumSearchPath(String path) {
    final relative = Uri.tryParse(path);
    if (relative == null || relative.hasScheme || relative.hasAuthority) {
      return false;
    }
    return switch (relative.path) {
      '/search/query.json' ||
      'search/query.json' ||
      '/search.json' ||
      'search.json' => true,
      _ => false,
    };
  }

  @override
  Future<String> pluginGetText({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final response = await _transport.get(
      _resolvePluginPath(siteUrl, path),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return response.body;
  }

  @override
  Future<List<Map<String, dynamic>>> pluginGetJsonList({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final response = await _transport.get(
      _resolvePluginPath(siteUrl, path),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    try {
      final decoded = await decodeJsonHttpResponse(response);
      if (decoded is! List) throw FormatException(appL10n.expectedAJSONList);
      return List.unmodifiable([
        for (final value in decoded)
          if (value is Map<String, dynamic>) value,
      ]);
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> pluginQueryJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async => _transport.postObject(
    _resolvePluginPath(siteUrl, path),
    siteUrl: siteUrl,
    apiKey: apiKey,
    body: body,
    clientId: clientId,
  );

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async => _transport.write(
    _resolvePluginPath(siteUrl, path),
    siteUrl: siteUrl,
    method: method,
    apiKey: apiKey,
    clientId: clientId,
    body: body,
  );

  @override
  Future<Map<String, dynamic>> pluginLongRunningWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    required Duration requestTimeout,
    String? clientId,
  }) async => _transport.write(
    _resolvePluginPath(siteUrl, path),
    siteUrl: siteUrl,
    method: method,
    apiKey: apiKey,
    clientId: clientId,
    body: body,
    requestTimeout: requestTimeout,
  );

  static Uri _resolvePluginPath(String siteUrl, String path) {
    final site = Uri.parse(siteUrl);
    // Plugin paths are written from the forum root — `/voice/rooms.json` —
    // and a forum served from a subfolder keeps that prefix in front of
    // them, so the site is the directory the path is resolved in. A
    // scheme-relative path keeps both slashes and fails the origin check.
    final relative = path.startsWith('//')
        ? path
        : path.replaceFirst(RegExp(r'^/'), '');
    final target = Uri.parse('$siteUrl/').resolve(relative);
    if (target.origin != site.origin) {
      throw ArgumentError.value(
        path,
        'path',
        'Plugin API paths must stay on the connected site origin.',
      );
    }
    return target;
  }
}
