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
  });

  group('the theme sits below the kit', () {
    test('no theme library imports the kit', () {
      expect(graph.edgesBetween('theme', 'ui'), isEmpty);
    });

    test('the kit reaches no model through the theme', () {
      final offenders = {
        for (final library in graph.edges.keys)
          if (LibraryGraph.areaOf(library) == 'ui')
            for (final reached in graph.closureOf(library))
              if (LibraryGraph.areaOf(reached) == 'models')
                '$library -> $reached',
      };
      expect(offenders, isEmpty);
    });

    test('no pair of layers depends on each other', () {
      expect(graph.mutualLayerPairs(), isEmpty);
    });
  });
}
