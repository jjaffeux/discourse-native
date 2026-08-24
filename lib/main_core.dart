import 'src/app_bootstrap.dart';
import 'src/plugins/core_plugin_manifest.dart';

void main() => AppBootstrap.production(manifest: corePluginManifest).start();
