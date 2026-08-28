import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_module.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_services.dart';

InstalledPlugins? _installedPlugins;

/// A lazily installed full manifest for tests which exercise bundled features.
InstalledPlugins get installedPlugins =>
    _installedPlugins ??= PluginInstaller.install(bundledPluginManifest);

PluginRegistry get pluginRegistry => installedPlugins.registry;

List<SitePlugin> get sitePlugins => pluginRegistry.plugins;

/// Full feature graph for widget hosts that cannot open platform persistence.
///
/// This is deliberately test-owned: production exposes one full composition
/// root, while widget tests replace only Resenha's diagnostics lifecycle.
final PluginManifest bundledWidgetTestManifest = PluginManifest([
  for (final module in bundledPluginManifest.modules)
    if (module.descriptor.id == resenhaPluginId)
      const ResenhaModule.withoutDiagnostics()
    else
      module,
]);
