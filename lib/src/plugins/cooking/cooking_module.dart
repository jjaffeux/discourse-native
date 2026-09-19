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
  List<CookingModule> get cookingModules => [
    CookingModule.spoiler,
    CookingModule.missingUploads,
    for (final id in ['details', 'd-wrap'])
      CookingModule(
        id: id,
        owner: 'cooking',
        version: '1',
        profiles: const ['post'],
      ),
    for (final (index, id) in [
      'cooking-links',
      'cooking-bidi',
      'cooking-media',
      'cooking-mentions',
    ].indexed)
      CookingModule(id: id, owner: 'cooking', version: '1', order: 100 + index),
  ];
  @override
  List<CookingProfile> get cookingProfiles => const [];
  @override
  Map<String, Object?> projectCookingContext(CookingPluginData data) =>
      const {};
}
