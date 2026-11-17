import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

const _contracts = 'lib/discourse_plugin_contracts.dart';
const _sdk = 'lib/discourse_plugin_sdk.dart';
const _shellController = 'lib/src/shell/shell_controller.dart';

void main() {
  final graph = LibraryGraph.load();
  final closure = graph.closureOf(_contracts);

  test('the contracts barrel compiles without the shell controller', () {
    expect(closure, isNot(contains(_shellController)));
  });

  test('the contracts barrel compiles without the UI kit', () {
    final kit = closure.where(
      (library) =>
          library == 'lib/discourse_ui.dart' ||
          library.startsWith('lib/src/ui/'),
    );
    expect(kit, isEmpty);
  });

  test('the only widgets the contracts barrel compiles are plugin scopes', () {
    expect(closure.intersection(graph.widgetLibraries), {
      'lib/src/plugin_api/composer_footer_layout.dart',
      'lib/src/plugin_api/plugin_ui_scope.dart',
    });
  });

  test('the contracts barrel leaves the plugin runtime to the full SDK', () {
    final exported = {
      for (final target in graph.edges[_contracts] ?? const <String>{})
        if (target.endsWith('/plugin_runtime.dart') ||
            target.endsWith('/plugin_scope.dart'))
          target,
    };
    expect(exported, isEmpty);
    expect(
      graph.edges[_sdk],
      containsAll([
        'lib/src/plugin_api/plugin_runtime.dart',
        'lib/src/plugin_api/plugin_scope.dart',
      ]),
    );
  });

  test('the full SDK re-exports the contracts barrel', () {
    expect(graph.edges[_sdk], contains(_contracts));
  });

  test('the contracts barrel stays within its closure budget', () {
    expect(closure.length, 169);
  });

  test('the plugin libraries on the full SDK stay within their budget', () {
    final fullSdkPluginLibraries = graph.edges.entries.where(
      (entry) =>
          entry.key.startsWith('lib/src/plugins/') &&
          entry.value.contains(_sdk),
    );
    expect(fullSdkPluginLibraries.length, 86);
  });
}
