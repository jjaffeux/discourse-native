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
    registrar.addSession((bindings, _) {
      final host = bindings.require(corePluginHostPort);
      final api = host.api is ReactionsApi
          ? host.api as ReactionsApi
          : ReactionsApiClient(host.api, host.api.models);
      final controller = ReactionsController(
        api: api,
        credentials: host.credentials,
        store: host.store,
        lifecycle: host.siteLifecycle,
      );
      return PluginSessionContribution(
        lifecycle: _ReactionsSessionLifecycle(controller),
        services: [
          PluginService<Object>(reactionsControllerService, controller),
        ],
      );
    }, requires: const [corePluginHostPort]);
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
