import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_resenha/discourse_resenha.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('full composition installs Resenha after its Chat dependency', () async {
    final installed = PluginInstaller.install(
      PluginManifest([...bundledPluginManifest.modules, resenhaModule]),
    );
    addTearDown(installed.close);

    final descriptors = installed.descriptors;
    expect(descriptors.last.id.value, 'resenha');
    expect(
      descriptors.last.dependencies.map((dependency) => dependency.id.value),
      ['chat'],
    );
    expect(descriptors.last.routeNamespaces, {'resenha'});
    expect(descriptors.last.exclusiveClaims, {'app-global-media-session'});
    expect(
      installed.registry.diagnosticsPlugins.map(
        (plugin) => plugin.diagnosticsId,
      ),
      ['resenha'],
    );
  });
}
