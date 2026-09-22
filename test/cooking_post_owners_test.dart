import 'package:discourse_native/src/plugin_api/cooking_plugin.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/cooking/cooking_module.dart';
import 'package:discourse_native/src/plugins/discourse_events/discourse_events_cooking.dart';
import 'package:discourse_native/src/plugins/discourse_events/discourse_events_module.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/poll/poll_cooking.dart';
import 'package:discourse_native/src/plugins/poll/poll_data.dart';
import 'package:discourse_native/src/plugins/poll/poll_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('post cooking capabilities register once under their native owners', () {
    final installed = PluginInstaller.install(
      const PluginManifest([cookingModule, pollModule, discourseEventsModule]),
    );
    addTearDown(installed.close);
    expect(installed.cookingPlugins.map((plugin) => plugin.name), [
      'cooking',
      'poll',
      'discourse-events',
    ]);
    final configuration = cookingConfiguration(installed.cookingPlugins);
    const owners = {
      'details': 'cooking',
      'd-wrap': 'cooking',
      'poll': 'poll',
      'post-event': 'discourse-events',
      'calendar': 'discourse-events',
      'livestream-preview': 'discourse-events',
      'livestream-visibility': 'discourse-events',
    };
    for (final entry in owners.entries) {
      final module = configuration.modules.singleWhere(
        (m) => m.id == entry.key,
      );
      expect(module.owner, entry.value);
      expect(module.version, '1');
      expect(module.profiles, ['post']);
    }
    expect(configuration.profiles.map((profile) => profile.name), ['post']);
    expect(
      configuration.modules
          .firstWhere((module) => module.id == 'poll')
          .enabledSetting,
      'poll_enabled',
    );
    expect(
      configuration.modules
          .firstWhere((module) => module.id == 'post-event')
          .enabledSetting,
      'discourse_post_event_enabled',
    );
    for (final id in [
      'calendar',
      'livestream-preview',
      'livestream-visibility',
    ]) {
      expect(
        configuration.modules
            .firstWhere((module) => module.id == id)
            .enabledSetting,
        'discourse_events_enabled',
      );
    }
    final visibility = configuration.modules.firstWhere(
      (module) => module.id == 'livestream-visibility',
    );
    expect(visibility.dependencies, ['livestream-preview']);
    expect(visibility.order, 200);
  });

  test('Chat alone contributes its cooking profile when installed', () {
    final installed = PluginInstaller.install(
      const PluginManifest([chatModule]),
    );
    addTearDown(installed.close);
    expect(
      cookingConfiguration(
        installed.cookingPlugins,
      ).profiles.map((profile) => profile.name),
      ['post', 'chat'],
    );
    expect(
      cookingConfiguration(const []).profiles.map((profile) => profile.name),
      ['post'],
    );
  });

  test('removing an owner removes its cooking contributions', () {
    final installed = PluginInstaller.install(
      const PluginManifest([cookingModule]),
    );
    addTearDown(installed.close);
    final configuration = cookingConfiguration(installed.cookingPlugins);
    expect(
      configuration.modules.map((module) => module.owner),
      everyElement('cooking'),
    );
    expect(
      configuration.modules.map((module) => module.id),
      containsAll(['details', 'd-wrap']),
    );
  });

  test('Poll projects only its parser settings with compatible defaults', () {
    const plugin = PollCookingPlugin();
    expect(
      plugin.projectCookingContext(
        const CookingPluginData('poll', PluginData.none),
      ),
      {
        'settings': {'poll_enabled': true, 'poll_maximum_options': 20},
      },
    );
    final data = PluginData.none.withValue(
      pollSettingsDataKey,
      const PollSettings(
        enabled: false,
        maximumOptions: 37,
        defaultPublic: false,
      ),
    );
    expect(plugin.projectCookingContext(CookingPluginData('poll', data)), {
      'settings': {'poll_enabled': false, 'poll_maximum_options': 37},
    });
    expect(
      () => plugin.projectCookingContext(
        CookingPluginData('discourse-events', data),
      ),
      throwsStateError,
    );
  });

  test('Events defaults do not enable any syntax', () {
    expect(
      const DiscourseEventsCookingPlugin().projectCookingContext(
        const CookingPluginData('discourse-events', PluginData.none),
      ),
      {
        'settings': {
          'discourse_events_enabled': false,
          'discourse_post_event_enabled': false,
        },
      },
    );
  });

  for (final baseEnabled in [false, true]) {
    for (final postEnabled in [false, true]) {
      test(
        'Events projects independent calendar and effective post gate: $baseEnabled/$postEnabled',
        () {
          final data = PluginData.none.withValue(
            eventSettingsKey,
            EventSettings(
              eventsEnabled: baseEnabled,
              postEventEnabled: postEnabled,
            ),
          );
          final context = const DiscourseEventsCookingPlugin()
              .projectCookingContext(
                CookingPluginData('discourse-events', data),
              );
          expect(context, {
            'settings': {
              'discourse_events_enabled': baseEnabled,
              'discourse_post_event_enabled': baseEnabled && postEnabled,
            },
          });
        },
      );
    }
  }
}
