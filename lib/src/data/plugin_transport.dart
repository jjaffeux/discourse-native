/// Narrow authenticated JSON transport used by repository-owned plugins.
///
/// Core retains ownership of same-origin enforcement, response bounds,
/// credential headers, and error mapping. Plugins own their endpoint paths and
/// payload parsing behind this boundary.
abstract interface class PluginApiTransport {
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  });

  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  });
}

/// Optional companion for compatibility routes whose successful JSON payload
/// is a top-level array rather than an object.
abstract interface class PluginJsonListTransport {
  Future<List<Map<String, dynamic>>> pluginGetJsonList({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  });
}
