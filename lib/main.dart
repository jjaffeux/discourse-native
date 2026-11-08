import 'src/app_bootstrap.dart';
import 'src/plugins/bundled_plugin_manifest.dart';
import 'src/styleguide/styleguide_page.dart';

void main() => AppBootstrap.production(
  manifest: bundledPluginManifest,
  openComponentStyleguide: showComponentStyleguide,
).start();
