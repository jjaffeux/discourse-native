import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'event_data.dart';

final class DiscourseEventsCookingPlugin implements CookingPlugin {
  const DiscourseEventsCookingPlugin();

  @override
  String get name => 'discourse-events';

  @override
  List<CookingModule> get cookingModules => [
    CookingModule(
      id: 'post-event',
      owner: name,
      version: '1',
      profiles: const ['post'],
      enabledSetting: 'discourse_post_event_enabled',
    ),
    for (final id in ['calendar', 'livestream-preview'])
      CookingModule(
        id: id,
        owner: name,
        version: '1',
        profiles: const ['post'],
        enabledSetting: 'discourse_events_enabled',
      ),
    CookingModule(
      id: 'livestream-visibility',
      owner: name,
      version: '1',
      profiles: const ['post'],
      enabledSetting: 'discourse_events_enabled',
      dependencies: const ['livestream-preview'],
      order: 200,
    ),
  ];

  @override
  List<CookingProfile> get cookingProfiles => const [];

  @override
  Map<String, Object?> projectCookingContext(CookingPluginData data) {
    final settings = data.read(eventSettingsKey) ?? const EventSettings();
    return {
      'settings': {
        'discourse_events_enabled': settings.eventsEnabled,
        // The module has one gate; Post Events require both server switches.
        'discourse_post_event_enabled': settings.enabled,
      },
    };
  }
}
