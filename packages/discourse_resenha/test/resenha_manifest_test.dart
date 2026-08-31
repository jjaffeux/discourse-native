import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_resenha/discourse_resenha.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InstalledPlugins installed;

  setUp(() {
    installed = PluginInstaller.install(
      PluginManifest([...bundledPluginManifest.modules, resenhaModule]),
    );
  });

  tearDown(() async {
    await installed.close();
  });

  test('installer orders Resenha after its Chat dependency', () {
    final descriptors = installed.descriptors;
    expect(descriptors.last.id.value, 'resenha');
    expect(
      descriptors.last.dependencies.map((dependency) => dependency.id.value),
      ['chat'],
    );
  });

  test(
    'module declares its routing, media, live, and diagnostics contracts',
    () {
      final descriptor = installed.descriptors.last;

      expect(descriptor.routeNamespaces, {'resenha'});
      expect(descriptor.exclusiveClaims, {'app-global-media-session'});
      expect(descriptor.liveChannelScopes.map((scope) => scope.path), [
        '/resenha',
      ]);
      expect(
        installed.registry.diagnosticsPlugins.map(
          (plugin) => plugin.diagnosticsId,
        ),
        ['resenha'],
      );
    },
  );
}
