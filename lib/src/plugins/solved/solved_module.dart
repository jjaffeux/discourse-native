import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'solved_global_search.dart';

const solvedModule = _Module();

final class _Module implements PluginModule {
  const _Module();
  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('discourse-solved'));
  @override
  void register(PluginRegistrar registrar) =>
      registrar.addCapability(const _Plugin());
}

final class _Plugin implements SitePlugin, GlobalSearchPlugin {
  const _Plugin();
  @override
  String get name => 'discourse-solved';
  @override
  List<GlobalSearchContribution> get searchContributions => const [
    SolvedGlobalSearch(),
  ];
}
