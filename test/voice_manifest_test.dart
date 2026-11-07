import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InstalledPlugins installed;

  setUp(() {
    installed = PluginInstaller.install(bundledPluginManifest);
  });

  tearDown(() async {
    await installed.close();
  });

  test('installer orders Voice after its Chat dependency', () {
    final descriptors = installed.descriptors;
    final voice = descriptors.singleWhere(
      (descriptor) => descriptor.id.value == 'voice',
    );
    expect(
      descriptors.indexOf(voice),
      greaterThan(
        descriptors.indexWhere((descriptor) => descriptor.id.value == 'chat'),
      ),
    );
    expect(voice.dependencies.map((dependency) => dependency.id.value), [
      'chat',
    ]);
  });

  test('module declares its routing, media, and live contracts', () {
    final descriptor = installed.descriptors.singleWhere(
      (descriptor) => descriptor.id.value == 'voice',
    );

    expect(descriptor.routeNamespaces, {'live', 'voice'});
    expect(descriptor.exclusiveClaims, {'app-global-media-session'});
    expect(descriptor.liveChannelScopes.map((scope) => scope.path).toSet(), {
      '/live',
      '/voice',
    });
  });
}
