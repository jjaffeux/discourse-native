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
  ('models', 'data'): {},
  ('models', 'ui'): {},
  ('models', 'plugin_api'): {},
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
  ('data', 'plugin_api'): {},
  ('data', 'shell'): {},
  ('data', 'styleguide'): {},
  ('data', 'plugins'): {},
  ('plugin_api', 'shell'): {},
  ('plugin_api', 'styleguide'): {},
  ('plugin_api', 'plugins'): {},
  ('shell', 'styleguide'): {},
  ('shell', 'plugins'): {},
};

const _largestImportCycle = 84;

/// A layer's whole transitive reach, so a barrel or a shared helper cannot
/// reintroduce what the direct-edge table forbids.
const Map<String, Set<String>> _unreachableFromLayer = {
  'data': {'plugin_api', 'shell', 'styleguide', 'plugins'},
  'models': {'data', 'plugin_api', 'shell', 'styleguide', 'plugins'},
  'theme': {'data', 'plugin_api', 'shell', 'styleguide', 'plugins'},
  'ui': {'data', 'plugin_api', 'shell', 'styleguide', 'plugins'},
  'plugin_api': {'shell', 'styleguide', 'plugins'},
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

    test('ShellController imports no widget library but its tab scope', () {
      expect(
        graph.edges['lib/src/shell/shell_controller.dart']!.intersection(
          graph.widgetLibraries,
        ),
        {'lib/src/shell/forum_tab_scope.dart'},
      );
    });

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

    test('classifies widget libraries through their parts', () {
      final seeded = sources({
        'lib/a.dart': "part 'a_part.dart';",
        'lib/a_part.dart':
            "part of 'a.dart';\nclass W extends State<StatefulWidget> {}",
        'lib/b.dart': 'class Plain extends Object {}',
      });
      expect(seeded.widgetLibraries, {'lib/a.dart'});
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
