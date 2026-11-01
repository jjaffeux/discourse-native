import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'gamification_api.dart';
import 'gamification_controller.dart';
import 'gamification_models.dart';
import 'gamification_navigation.dart';
import 'gamification_plugin.dart';

const gamificationModule = GamificationModule();

final class GamificationModule implements PluginModule {
  const GamificationModule();
  @override
  PluginDescriptor get descriptor => PluginDescriptor(
    id: gamificationPluginId,
    routeNamespaces: {'gamification'},
    liveChannelScopes: {
      const PluginLiveChannelScope.prefix('/recalculate_scores'),
    },
  );
  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const GamificationPlugin());
    registrar.addRouteNamespace('gamification');
    registrar.addLiveChannelScope(
      const PluginLiveChannelScope.prefix('/recalculate_scores'),
    );
    registrar.addSession(
      (bindings, _) {
        final controller = GamificationController(
          api: GamificationApi(bindings.require(corePluginTransportPort)),
          requests: bindings.require(corePluginRequestPort),
          siteState: bindings.require(corePluginSiteStatePort),
        );
        final navigation = GamificationNavigation(
          host: bindings.require(corePluginRouteNavigationPort),
          controller: controller,
        );
        return PluginSessionContribution(
          lifecycle: _GamificationLifecycle(controller),
          services: [
            PluginService<Object>(gamificationControllerKey, controller),
            PluginService<Object>(gamificationNavigationKey, navigation),
          ],
          capabilities: [controller, navigation],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginRequestPort,
        corePluginSiteStatePort,
        corePluginRouteNavigationPort,
      ],
    );
  }
}

final class _GamificationLifecycle extends PluginSessionLifecycle {
  _GamificationLifecycle(this.controller);
  final GamificationController controller;
  @override
  void forget(String siteUrl) => controller.forget(siteUrl);
  @override
  void setForeground(bool foreground) => controller.setForeground(foreground);
  @override
  void close() => controller.dispose();
}
