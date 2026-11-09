import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

void main() {
  final graph = LibraryGraph.load();

  Iterable<List<String>> cyclesThrough(String directory) => graph
      .cycles()
      .where((cycle) => cycle.any((library) => library.startsWith(directory)));

  test('no data library participates in an import cycle', () {
    expect(cyclesThrough('lib/src/data/'), isEmpty);
  });

  test('no plugin API library participates in an import cycle', () {
    expect(cyclesThrough('lib/src/plugin_api/'), isEmpty);
  });

  test('plugin UI ownership compiles without any application library', () {
    const scope = 'lib/src/plugin_api/plugin_ui_scope.dart';
    expect(graph.closureOf(scope), {scope});
  });

  test('the API contracts stay below every transport implementation', () {
    expect(
      graph
          .closureOf('lib/src/data/discourse_api_contracts.dart')
          .intersection(const {
            'lib/src/data/discourse_api.dart',
            'lib/src/data/discourse_get_sender.dart',
            'lib/src/data/discourse_transport.dart',
            'lib/src/data/dsa_notices_api.dart',
            'lib/src/data/http_transport.dart',
            'lib/src/data/site_appearance_loader.dart',
          }),
      isEmpty,
    );
  });
}
