import 'src/app_bootstrap.dart';
import 'src/plugins/bundled_plugin_manifest.dart';

void main() => AppBootstrap.production(manifest: bundledPluginManifest).start();
