import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:flutter_test/flutter_test.dart';

const _pluginId = PluginId('host-harness-test');
const _navigationService = PluginServiceKey<_TestNavigationService>(
  owner: _pluginId,
  name: 'navigation',
);

void main() {
  test('provides typed plugin services over real shell navigation', () async {
    final host = await PluginHostHarness.open(
      transport: RecordingPluginTransport(),
      manifest: const PluginManifest([_TestNavigationModule()]),
      sites: const [
        PluginHostSite(url: 'https://forum.example', apiKey: 'key'),
      ],
    );
    addTearDown(host.close);
    final destination = host.currentContent;

    host.require(_navigationService).open();

    expect(host.currentContent?.id, 'host-harness-test-route');
    expect(host.contentStack, hasLength(2));
    expect(host.popContent(), isTrue);
    expect(host.currentContent?.id, destination?.id);
  });
}

final class _TestNavigationModule implements PluginModule {
  const _TestNavigationModule();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(id: _pluginId);

  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession(
      (bindings, _) => PluginSessionContribution(
        lifecycle: _TestSessionLifecycle(),
        services: [
          PluginService<Object>(
            _navigationService,
            _TestNavigationService(
              bindings.require(corePluginRouteNavigationPort),
            ),
          ),
        ],
      ),
      requires: const [corePluginRouteNavigationPort],
    );
  }
}

final class _TestSessionLifecycle extends PluginSessionLifecycle {}

final class _TestNavigationService {
  const _TestNavigationService(this._navigation);

  final PluginRouteNavigationHost _navigation;

  void open() {
    _navigation.pushContent(
      const ContentRoute(
        id: 'host-harness-test-route',
        title: 'Plugin route',
        icon: DIcons.microphoneLines,
      ),
    );
  }
}
