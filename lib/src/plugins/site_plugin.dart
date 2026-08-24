import 'bundled_plugin_manifest.dart';
import 'plugin_runtime.dart';
import 'site_plugin_api.dart';

export 'bundled_plugin_manifest.dart';
export 'plugin_data.dart';
export 'plugin_manifest.dart';
export 'plugin_registry.dart';
export 'plugin_runtime.dart';
export 'site_plugin_api.dart';

/// Installed once after validating and snapshotting the full manifest.
final InstalledPlugins installedPlugins = PluginInstaller.install(
  bundledPluginManifest,
);

/// Compatibility names for consumers moving onto [installedPlugins].
final pluginRegistry = installedPlugins.registry;
final List<SitePlugin> sitePlugins = pluginRegistry.plugins;
