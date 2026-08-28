import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';

InstalledPlugins? _installedPlugins;

/// A lazily installed full manifest for tests which exercise bundled features.
InstalledPlugins get installedPlugins =>
    _installedPlugins ??= PluginInstaller.install(bundledPluginManifest);

PluginRegistry get pluginRegistry => installedPlugins.registry;

List<SitePlugin> get sitePlugins => pluginRegistry.plugins;
