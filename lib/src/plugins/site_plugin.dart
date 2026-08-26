import 'bundled_plugin_manifest.dart';
import 'plugin_runtime.dart';
import 'site_plugin_api.dart';

export 'assign/assignment_shell_extension.dart';
export 'bundled_plugin_manifest.dart';
export 'chat/chat_shell_extension.dart';
export 'plugin_data.dart';
export 'plugin_manifest.dart';
export 'plugin_registry.dart';
export 'plugin_runtime.dart';
export 'poll/poll_shell_extension.dart';
export 'reactions/reactions_shell_extension.dart';
export 'resenha/resenha_shell_extension.dart';
export 'site_plugin_api.dart';

/// Installed once after validating and snapshotting the full manifest.
final InstalledPlugins installedPlugins = PluginInstaller.install(
  bundledPluginManifest,
);

/// Compatibility names for consumers moving onto [installedPlugins].
final pluginRegistry = installedPlugins.registry;
final List<SitePlugin> sitePlugins = pluginRegistry.plugins;
