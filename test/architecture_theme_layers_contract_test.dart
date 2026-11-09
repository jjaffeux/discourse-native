import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

/// `foundation/icons/` holds the icon vocabulary so that a library naming an
/// icon compiles none of the widgets that draw one.
void main() {
  final graph = LibraryGraph.load();

  group('the icon vocabulary sits below the models', () {
    test('neither models nor the data layer imports the theme', () {
      expect(graph.edgesBetween('models', 'theme'), isEmpty);
      expect(graph.edgesBetween('data', 'theme'), isEmpty);
    });

    test('no model reaches the theme or the kit', () {
      final offenders = {
        for (final library in graph.edges.keys)
          if (LibraryGraph.areaOf(library) == 'models')
            for (final reached in graph.closureOf(library))
              if (const {'theme', 'ui'}.contains(LibraryGraph.areaOf(reached)))
                '$library -> $reached',
      };
      expect(offenders, isEmpty);
    });

    test('models and the theme do not depend on each other', () {
      expect(graph.mutualLayerPairs(), isNot(contains('models <-> theme')));
    });
  });
}
