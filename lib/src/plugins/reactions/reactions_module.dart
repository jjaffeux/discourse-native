import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import 'reactions_api.dart';
import 'reactions_api_client.dart';
import 'reactions_controller.dart';
import 'reactions_plugin.dart';
import 'reactions_services.dart';

const reactionsModule = ReactionsModule();

final class ReactionsModule implements PluginModule {
  const ReactionsModule();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: reactionsPluginId);

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const ReactionsPlugin());
    registrar.addSession(
      (bindings, _) {
        final transport = bindings.require(corePluginTransportPort);
        final api = transport is ReactionsApi
            ? transport as ReactionsApi
            : ReactionsApiClient(
                transport,
                bindings.require(corePluginModelCodecPort),
              );
        final controller = ReactionsController(
          api: api,
          credentials: bindings.require(corePluginCredentialsPort),
          store: bindings.require(corePluginStorePort),
          lifecycle: bindings.require(corePluginSiteLifecyclePort),
        );
        return PluginSessionContribution(
          lifecycle: _ReactionsSessionLifecycle(controller),
          services: [
            PluginService<Object>(reactionsControllerService, controller),
            PluginService<Object>(
              reactionsEmojiHostService,
              bindings.require(corePluginEmojiPort),
            ),
          ],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginModelCodecPort,
        corePluginCredentialsPort,
        corePluginStorePort,
        corePluginSiteLifecyclePort,
        corePluginEmojiPort,
      ],
    );
  }
}

final class _ReactionsSessionLifecycle extends PluginSessionLifecycle {
  _ReactionsSessionLifecycle(this.controller);

  final ReactionsController controller;

  @override
  void forget(String siteUrl) => controller.forget(siteUrl);

  @override
  void close() => controller.dispose();
}
