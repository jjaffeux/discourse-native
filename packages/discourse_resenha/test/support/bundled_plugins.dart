import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_resenha/discourse_resenha.dart';

final PluginManifest fullManifest = PluginManifest([
  ...bundledPluginManifest.modules,
  resenhaModule,
]);

InstalledPlugins? _installedPlugins;

InstalledPlugins get installedPlugins =>
    _installedPlugins ??= PluginInstaller.install(fullManifest);

PluginRegistry get pluginRegistry => installedPlugins.registry;

List<SitePlugin> get sitePlugins => pluginRegistry.plugins;
