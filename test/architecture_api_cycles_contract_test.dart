import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

void main() {
  final graph = LibraryGraph.load();

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
