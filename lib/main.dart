import 'src/app_bootstrap.dart';
import 'src/plugins/bundled_plugin_manifest.dart';

/// Runs the bundled core package without separately packaged native plugins.
void main() => AppBootstrap.production(manifest: bundledPluginManifest).start();
