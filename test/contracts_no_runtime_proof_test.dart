import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

const _contracts = 'lib/discourse_plugin_contracts.dart';
const _registry = 'lib/src/plugin_api/plugin_registry.dart';

void main() {
  test('a registry API change recompiles only what needs the registry', () {
    final graph = LibraryGraph.load();
    final invalidated = graph.dependentsOf(_registry).length;
    final reach = graph.closureOf(_contracts).length;
    // ignore: avoid_print
    print(
      'PERF_PROOF contracts-no-runtime registry_invalidates=$invalidated '
      'contracts_reach=$reach',
    );
    // Exporting the runtime from the contracts barrel again costs about 240
    // libraries, so this leaves room for new plugin libraries.
    expect(invalidated, lessThanOrEqualTo(360));
    expect(reach, lessThanOrEqualTo(163));
  });
}
