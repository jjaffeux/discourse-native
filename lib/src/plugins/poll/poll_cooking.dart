import 'package:discourse_cooking/discourse_cooking.dart';

import '../../plugin_api/cooking_plugin.dart';
import 'poll_data.dart';

final class PollCookingPlugin implements CookingPlugin {
  const PollCookingPlugin();

  @override
  String get name => 'poll';

  @override
  List<CookingModule> get cookingModules => [
    CookingModule(
      id: 'poll',
      owner: name,
      version: '1',
      profiles: const ['post'],
      enabledSetting: 'poll_enabled',
    ),
  ];

  @override
  List<CookingProfile> get cookingProfiles => const [];

  @override
  Map<String, Object?> projectCookingContext(CookingPluginData data) {
    final settings = data.read(pollSettingsDataKey) ?? const PollSettings();
    return {
      'settings': {
        'poll_enabled': settings.enabled,
        'poll_maximum_options': settings.maximumOptions,
      },
    };
  }
}
