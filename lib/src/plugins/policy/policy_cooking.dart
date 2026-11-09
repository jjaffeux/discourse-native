import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'policy_data.dart';

class PolicyCookingPlugin implements CookingPlugin {
  const PolicyCookingPlugin();
  @override
  String get name => 'discourse-policy';
  @override
  List<CookingProfile> get cookingProfiles => const [];
  @override
  List<CookingModule> get cookingModules => [
    CookingModule(
      id: 'discourse-policy',
      owner: name,
      version: '1',
      profiles: const ['post'],
      enabledSetting: 'policy_enabled',
    ),
  ];
  @override
  Map<String, Object?> projectCookingContext(CookingPluginData data) => {
    'settings': {
      'policy_enabled': data.read(policySettingsKey)?.enabled == true,
    },
  };
}
