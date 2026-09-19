import 'package:discourse_cooking/discourse_cooking.dart';

import '../../plugin_api/cooking_plugin.dart';
import '../../plugin_api/plugin_manifest.dart';

const cookingModule = CookingModulePlugin();

final class CookingModulePlugin implements PluginModule {
  const CookingModulePlugin();
  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('cooking'));
  @override
  void register(PluginRegistrar registrar) =>
      registrar.addCapability(const _CookingPlugin());
}

final class _CookingPlugin implements CookingPlugin {
  const _CookingPlugin();
  @override
  String get name => 'cooking';
  @override
  List<CookingModule> get cookingModules => const [
    CookingModule.spoiler,
    CookingModule.missingUploads,
  ];
  @override
  List<CookingProfile> get cookingProfiles => const [];
  @override
  Map<String, Object?> projectCookingContext(CookingPluginData data) =>
      const {};
}
