import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_resenha/discourse_resenha.dart';

final PluginManifest fullManifest = PluginManifest([
  ...bundledPluginManifest.modules,
  resenhaModule,
]);
