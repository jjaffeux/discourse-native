import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'boards_api.dart';
import 'boards_controller.dart';
import 'boards_data.dart';
import 'boards_navigation.dart';
import 'boards_plugin.dart';

const boardsModule = BoardsModule();

final class BoardsModule implements PluginModule {
  const BoardsModule();
  @override
  PluginDescriptor get descriptor => PluginDescriptor(
    id: boardsPluginId,
    routeNamespaces: {'boards'},
    liveChannelScopes: {const PluginLiveChannelScope.prefix('/boards')},
  );
  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const BoardsPlugin());
    registrar.addRouteNamespace('boards');
    registrar.addLiveChannelScope(
      const PluginLiveChannelScope.prefix('/boards'),
    );
    registrar.addSession(
      (bindings, _) {
        final controller = BoardsController(
          api: BoardsApi(bindings.require(corePluginTransportPort)),
          requests: bindings.require(corePluginRequestPort),
          siteState: bindings.require(corePluginSiteStatePort),
          trackers: bindings.require(corePluginTrackerPort),
          topics: bindings.require(corePluginTopicRefreshPort),
          composer: bindings.require(corePluginComposerPort),
        );
        final navigation = BoardsNavigation(
          host: bindings.require(corePluginRouteNavigationPort),
          topicLists: bindings.require(corePluginTopicListNavigationPort),
          controller: controller,
        );
        return PluginSessionContribution(
          lifecycle: _BoardsLifecycle(controller),
          services: [
            PluginService<Object>(boardsControllerKey, controller),
            PluginService<Object>(boardsNavigationKey, navigation),
          ],
          capabilities: [controller, navigation],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginRequestPort,
        corePluginSiteStatePort,
        corePluginTrackerPort,
        corePluginTopicRefreshPort,
        corePluginComposerPort,
        corePluginRouteNavigationPort,
        corePluginTopicListNavigationPort,
      ],
    );
  }
}

final class _BoardsLifecycle extends PluginSessionLifecycle {
  _BoardsLifecycle(this.controller);
  final BoardsController controller;
  @override
  void forget(String siteUrl) => controller.forget(siteUrl);
  @override
  void setForeground(bool foreground) => controller.setForeground(foreground);
  @override
  void close() => controller.dispose();
}
