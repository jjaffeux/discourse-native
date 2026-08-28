import 'package:discourse_native/discourse_bundled.dart';

import 'full_plugin_manifest.dart';

void main() => AppBootstrap.production(manifest: fullPluginManifest).start();
