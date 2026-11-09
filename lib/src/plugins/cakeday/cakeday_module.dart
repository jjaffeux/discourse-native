import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'cakeday_api.dart';
import 'cakeday_controller.dart';
import 'cakeday_data.dart';
import 'cakeday_navigation.dart';
import 'cakeday_plugin.dart';

const cakedayModule = CakedayModule();

final class CakedayModule implements PluginModule {
  const CakedayModule();
  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: cakedayPluginId, routeNamespaces: {'cakeday'});
  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const CakedayPlugin());
    registrar.addRouteNamespace('cakeday');
    registrar.addSession(
      (bindings, _) {
        final controller = CakedayController(
          api: CakedayApi(bindings.require(corePluginTransportPort)),
          requests: bindings.require(corePluginRequestPort),
          siteState: bindings.require(corePluginSiteStatePort),
          timezone: bindings.require(corePluginTimezonePort),
          emoji: bindings.require(corePluginEmojiPort),
        );
        final navigation = CakedayNavigation(
          bindings.require(corePluginRouteNavigationPort),
          controller,
        );
        return PluginSessionContribution(
          lifecycle: _CakedayLifecycle(controller),
          services: [
            PluginService<Object>(cakedayControllerKey, controller),
            PluginService<Object>(cakedayNavigationKey, navigation),
          ],
          capabilities: [controller, navigation],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginRequestPort,
        corePluginSiteStatePort,
        corePluginTimezonePort,
        corePluginEmojiPort,
        corePluginRouteNavigationPort,
      ],
    );
  }
}

final class _CakedayLifecycle extends PluginSessionLifecycle {
  _CakedayLifecycle(this.controller);
  final CakedayController controller;
  @override
  void forget(String siteUrl) => controller.forget(siteUrl);
  @override
  void setForeground(bool foreground) => controller.setForeground(foreground);
  @override
  void close() => controller.dispose();
}
