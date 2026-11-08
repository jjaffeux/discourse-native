import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

/// Lower layers never reach upward. An entry here is a known debt with the
/// exact edge named, so removing one shrinks the list and adding one is a
/// reviewed decision.
const Map<(String, String), Set<String>> _allowedUpwardEdges = {
  ('foundation', 'models'): {},
  ('foundation', 'data'): {},
  ('foundation', 'theme'): {},
  ('foundation', 'ui'): {},
  ('foundation', 'plugin_api'): {},
  ('foundation', 'shell'): {},
  ('foundation', 'styleguide'): {},
  ('foundation', 'plugins'): {},
  ('models', 'data'): {
    'lib/src/models/discover_site.dart -> lib/src/data/http_transport.dart',
    'lib/src/models/discover_site.dart -> lib/src/data/stored_forum_base.dart',
    'lib/src/models/post.dart -> lib/src/data/store.dart',
    'lib/src/models/post_likers.dart -> lib/src/data/store.dart',
    'lib/src/models/topic.dart -> lib/src/data/store.dart',
    'lib/src/models/user_card.dart -> lib/src/data/store.dart',
  },
  ('models', 'ui'): {
    'lib/src/models/shared_appearance.dart -> lib/discourse_ui.dart',
  },
  ('models', 'plugin_api'): {
    'lib/src/models/composer_draft.dart -> lib/src/plugin_api/preserved_json.dart',
    'lib/src/models/discourse_instance.dart -> lib/src/plugin_api/notification_counters.dart',
    'lib/src/models/discourse_instance.dart -> lib/src/plugin_api/plugin_data.dart',
    'lib/src/models/discourse_user.dart -> lib/src/plugin_api/plugin_data.dart',
    'lib/src/models/group.dart -> lib/src/plugin_api/plugin_data.dart',
    'lib/src/models/notification_totals.dart -> lib/src/plugin_api/notification_counters.dart',
    'lib/src/models/post.dart -> lib/src/plugin_api/plugin_data.dart',
    'lib/src/models/post_creation.dart -> lib/src/plugin_api/plugin_data.dart',
    'lib/src/models/sidebar.dart -> lib/src/plugin_api/plugin_icon_catalog.dart',
    'lib/src/models/site_config.dart -> lib/src/plugin_api/plugin_data.dart',
    'lib/src/models/topic.dart -> lib/src/plugin_api/plugin_data.dart',
    'lib/src/models/topic.dart -> lib/src/plugin_api/topic_recommendation_source.dart',
    'lib/src/models/user_card.dart -> lib/src/plugin_api/plugin_data.dart',
  },
  ('models', 'shell'): {},
  ('models', 'styleguide'): {},
  ('models', 'plugins'): {},
  ('theme', 'data'): {},
  ('theme', 'plugin_api'): {},
  ('theme', 'shell'): {},
  ('theme', 'styleguide'): {},
  ('theme', 'plugins'): {},
  ('ui', 'models'): {},
  ('ui', 'data'): {},
  ('ui', 'plugin_api'): {},
  ('ui', 'shell'): {},
  ('ui', 'styleguide'): {},
  ('ui', 'plugins'): {},
  ('data', 'ui'): {},
  ('data', 'plugin_api'): {
    'lib/src/data/application_cooking.dart -> lib/src/plugin_api/cooking_plugin.dart',
    'lib/src/data/application_cooking.dart -> lib/src/plugin_api/plugin_runtime.dart',
    'lib/src/data/current_user_reconciler.dart -> lib/src/plugin_api/discourse_model_codec.dart',
    'lib/src/data/current_user_reconciler.dart -> lib/src/plugin_api/plugin_data.dart',
    'lib/src/data/dashboard_api.dart -> lib/src/plugin_api/dashboard_report_source.dart',
    'lib/src/data/discourse_account_api.dart -> lib/src/plugin_api/discourse_model_codec.dart',
    'lib/src/data/discourse_api.dart -> lib/src/plugin_api/discourse_model_codec.dart',
    'lib/src/data/discourse_api_contracts.dart -> lib/src/plugin_api/discourse_model_codec.dart',
    'lib/src/data/discourse_composer_api.dart -> lib/src/plugin_api/composer_metadata.dart',
    'lib/src/data/discourse_composer_api.dart -> lib/src/plugin_api/discourse_model_codec.dart',
    'lib/src/data/discourse_site_api.dart -> lib/src/plugin_api/discourse_model_codec.dart',
    'lib/src/data/discourse_site_api.dart -> lib/src/plugin_api/topic_reading_policy.dart',
    'lib/src/data/discourse_topic_api.dart -> lib/src/plugin_api/discourse_model_codec.dart',
    'lib/src/data/emoji_picker_store.dart -> lib/src/plugin_api/emoji_preferences.dart',
    'lib/src/data/emoji_picker_store.dart -> lib/src/plugin_api/emoji_usage.dart',
    'lib/src/data/groups_api.dart -> lib/src/plugin_api/discourse_model_codec.dart',
    'lib/src/data/instance_store.dart -> lib/src/plugin_api/discourse_model_codec.dart',
    'lib/src/data/report_api.dart -> lib/src/plugin_api/dashboard_report_source.dart',
    'lib/src/data/shell_api_ports.dart -> lib/src/plugin_api/discourse_model_codec.dart',
    'lib/src/data/sidebar_icon_loader.dart -> lib/src/plugin_api/plugin_icon_catalog.dart',
    'lib/src/data/site_message_bus_bootstrap.dart -> lib/src/plugin_api/discourse_model_codec.dart',
    'lib/src/data/site_message_bus_bootstrap.dart -> lib/src/plugin_api/preserved_json.dart',
    'lib/src/data/site_tracker.dart -> lib/src/plugin_api/live_channels.dart',
    'lib/src/data/site_tracker.dart -> lib/src/plugin_api/plugin_manifest.dart',
    'lib/src/data/topic_recommendations_tab_store.dart -> lib/src/plugin_api/topic_recommendation_source.dart',
    'lib/src/data/user_directory_api.dart -> lib/src/plugin_api/discourse_model_codec.dart',
  },
  ('data', 'shell'): {},
  ('data', 'styleguide'): {},
  ('data', 'plugins'): {},
  ('plugin_api', 'shell'): {
    'lib/src/plugin_api/core_plugin_host.dart -> lib/src/shell/composer/controller.dart',
    'lib/src/plugin_api/global_search.dart -> lib/src/shell/global_search_filters.dart',
    'lib/src/plugin_api/global_search.dart -> lib/src/shell/global_search_models.dart',
    'lib/src/plugin_api/plugin_registry.dart -> lib/src/shell/composer/controller.dart',
    'lib/src/plugin_api/plugin_registry.dart -> lib/src/shell/post_action.dart',
    'lib/src/plugin_api/site_plugin_api.dart -> lib/src/shell/composer/controller.dart',
    'lib/src/plugin_api/site_plugin_api.dart -> lib/src/shell/global_search_models.dart',
    'lib/src/plugin_api/site_plugin_api.dart -> lib/src/shell/post_action.dart',
  },
  ('plugin_api', 'styleguide'): {},
  ('plugin_api', 'plugins'): {},
  ('shell', 'styleguide'): {},
  ('shell', 'plugins'): {},
};

const _largestImportCycle = 196;

/// A layer's whole transitive reach, so a barrel or a shared helper cannot
/// reintroduce what the direct-edge table forbids.
const Map<String, Set<String>> _unreachableFromLayer = {
  'theme': {'data', 'plugin_api', 'shell', 'styleguide', 'plugins'},
  'ui': {'data', 'plugin_api', 'shell', 'styleguide', 'plugins'},
  'shell': {'styleguide', 'plugins'},
};

void main() {
  final graph = LibraryGraph.load();

  group('layer contract', () {
    for (final entry in _allowedUpwardEdges.entries) {
      final (from, to) = entry.key;
      test('$from reaches $to only through named exceptions', () {
        expect(graph.edgesBetween(from, to), entry.value);
      });
    }

    for (final entry in _unreachableFromLayer.entries) {
      test('${entry.key} never reaches ${entry.value.join(', ')}', () {
        final offenders = {
          for (final library in graph.edges.keys)
            if (LibraryGraph.areaOf(library) == entry.key)
              for (final reached in graph.closureOf(library))
                if (entry.value.contains(LibraryGraph.areaOf(reached)))
                  '$library -> $reached',
        };
        expect(offenders, isEmpty);
      });
    }

    test('the import cycle stays within its budget', () {
      final cycles = graph.cycles();
      expect(cycles.isEmpty ? 0 : cycles.first.length, _largestImportCycle);
    });
  });

  group('detection', () {
    LibraryGraph sources(Map<String, String> files) =>
        LibraryGraph.fromSources(files);

    test('reports an upward edge', () {
      final seeded = sources({
        'lib/src/models/a.dart': "import '../shell/b.dart';",
        'lib/src/shell/b.dart': '',
      });
      expect(seeded.edgesBetween('models', 'shell'), {
        'lib/src/models/a.dart -> lib/src/shell/b.dart',
      });
    });

    test('resolves package URIs and folds parts into their owner', () {
      final seeded = sources({
        'lib/src/models/a.dart': "part 'a_part.dart';",
        'lib/src/models/a_part.dart':
            "part of 'a.dart';\n"
            "import 'package:discourse_native/src/shell/b.dart';",
        'lib/src/shell/b.dart': '',
      });
      expect(seeded.closureOf('lib/src/models/a.dart'), {
        'lib/src/models/a.dart',
        'lib/src/shell/b.dart',
      });
    });

    test('finds a cycle through a barrel export', () {
      final seeded = sources({
        'lib/discourse_ui.dart': "export 'src/shell/b.dart';",
        'lib/src/shell/b.dart': "import '../../discourse_ui.dart';",
        'lib/src/shell/c.dart': "import 'b.dart';",
      });
      expect(seeded.cycles(), [
        ['lib/discourse_ui.dart', 'lib/src/shell/b.dart'],
      ]);
    });

    test('reports the libraries invalidated by a change', () {
      final seeded = sources({
        'lib/a.dart': "import 'b.dart';",
        'lib/b.dart': "import 'c.dart';",
        'lib/c.dart': '',
      });
      expect(seeded.dependentsOf('lib/c.dart'), {
        'lib/a.dart',
        'lib/b.dart',
        'lib/c.dart',
      });
    });
  });
}
