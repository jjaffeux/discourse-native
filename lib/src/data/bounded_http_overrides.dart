import 'dart:io';

/// One app-owned layer in the process-wide HTTP override stack.
///
/// Bootstrap can run again in tests or after dependency replacement. Marking
/// the layers lets the outer connection-budget installer discard the complete
/// previous app stack while preserving a host application's underlying proxy
/// or client override.
abstract interface class AppHttpOverridesLayer {
  HttpOverrides? get previous;
}

/// Applies a process-wide per-host connection budget.
///
/// Flutter's [NetworkImage] owns its own shared [HttpClient], outside the app's
/// JSON transport and byte caches. Installing this before any clients are
/// created keeps unique post, onebox, chat, and lightbox images from opening an
/// unbounded number of connections to the same Discourse origin.
final class BoundedHttpOverrides extends HttpOverrides
    implements AppHttpOverridesLayer {
  BoundedHttpOverrides({
    this.maxConnectionsPerHost = 4,
    HttpOverrides? previous,
  }) : assert(maxConnectionsPerHost > 0),
       previous = _withoutAppHttpOverrides(previous ?? HttpOverrides.current);

  final int maxConnectionsPerHost;

  @override
  final HttpOverrides? previous;

  static BoundedHttpOverrides install({int maxConnectionsPerHost = 4}) {
    final override = BoundedHttpOverrides(
      maxConnectionsPerHost: maxConnectionsPerHost,
      previous: HttpOverrides.current,
    );
    HttpOverrides.global = override;
    return override;
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client =
        previous?.createHttpClient(context) ?? super.createHttpClient(context);
    final inheritedLimit = client.maxConnectionsPerHost;
    if (inheritedLimit == null || inheritedLimit > maxConnectionsPerHost) {
      client.maxConnectionsPerHost = maxConnectionsPerHost;
    }
    return client;
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) {
    return previous?.findProxyFromEnvironment(url, environment) ??
        super.findProxyFromEnvironment(url, environment);
  }
}

HttpOverrides? _withoutAppHttpOverrides(HttpOverrides? override) {
  while (true) {
    final layer = override;
    if (layer is! AppHttpOverridesLayer) return override;
    override = (layer as AppHttpOverridesLayer).previous;
  }
}
