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

abstract interface class PluginJsonListTransport {
  Future<List<Map<String, dynamic>>> pluginGetJsonList({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  });
}

/// Optional authenticated text downloads, with the same origin, size, timeout,
/// and credential rules as JSON requests. Endpoint selection stays plugin-owned.
abstract interface class PluginTextTransport {
  Future<String> pluginGetText({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  });
}
