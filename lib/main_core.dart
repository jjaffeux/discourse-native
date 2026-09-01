import 'src/app_bootstrap.dart';
import 'src/plugins/bundled_plugin_manifest.dart';

/// Kept as a compatibility target for older launch configurations.
///
/// Production features, including Voice, are never removed from an app
/// build. Tests which need an empty manifest construct one directly.
void main() => AppBootstrap.production(manifest: bundledPluginManifest).start();
