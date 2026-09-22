import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'cooking_settings.dart';

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

final class _CookingPlugin
    implements SitePlugin, CookingPlugin, SiteSettingsPlugin<CookingSettings> {
  const _CookingPlugin();
  @override
  String get name => 'cooking';
  @override
  List<CookingModule> get cookingModules => [
    CookingModule.spoiler,
    CookingModule.missingUploads,
    CookingModule(
      id: 'checklist',
      owner: 'cooking',
      version: '1',
      profiles: const ['post'],
      enabledSetting: 'checklist_enabled',
    ),
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
  Map<String, Object?> projectCookingContext(CookingPluginData data) => {
    'settings': {
      'checklist_enabled':
          (data.read(cookingSettingsKey) ?? const CookingSettings())
              .checklistEnabled,
    },
  };

  @override
  PluginDataPersistenceCodec<CookingSettings> get siteSettingsCodec =>
      const CookingSettingsCodec();

  @override
  CookingSettings readSiteSettings(Map<String, dynamic> json, String siteUrl) =>
      CookingSettings(checklistEnabled: json['checklist_enabled'] != false);
}
