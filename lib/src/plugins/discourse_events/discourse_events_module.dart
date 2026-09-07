import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import 'discourse_events_plugin.dart';
import 'event_api.dart';
import 'event_composer.dart';
import 'event_controller.dart';
import 'event_data.dart';
import 'event_navigation.dart';

const discourseEventsModule = DiscourseEventsModule();

final class DiscourseEventsModule implements PluginModule {
  const DiscourseEventsModule();
  @override
  PluginDescriptor get descriptor => PluginDescriptor(
    id: eventsPluginId,
    syntaxIds: const {'discourse-events/event'},
    routeNamespaces: const {'events'},
    liveChannelScopes: {
      const PluginLiveChannelScope.prefix('/discourse-post-event'),
    },
  );
  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const DiscourseEventsPlugin());
    registrar.addCapability(const EventTopicPlugin());
    registrar.addSyntaxId(eventSyntaxKind.id);
    registrar.addRouteNamespace('events');
    registrar.addLiveChannelScope(
      const PluginLiveChannelScope.prefix('/discourse-post-event'),
    );
    registrar.addSession(
      (bindings, _) {
        final controller = EventController(
          api: EventApi(bindings.require(corePluginTransportPort)),
          requests: bindings.require(corePluginRequestPort),
          posts: bindings.require(corePluginPostPort),
          siteState: bindings.require(corePluginSiteStatePort),
          accounts: bindings.require(corePluginAccountConnectionPort),
          topics: bindings.require(corePluginTopicRefreshPort),
          trackers: bindings.require(corePluginTrackerPort),
          zones: bindings.require(corePluginTimezonePort),
        );
        final navigation = EventNavigation(
          host: bindings.require(corePluginRouteNavigationPort),
          editor: bindings.require(corePluginPostEditorPort),
          controller: controller,
        );
        return PluginSessionContribution(
          lifecycle: _EventsLifecycle(controller),
          services: [
            PluginService<Object>(eventControllerKey, controller),
            PluginService<Object>(eventNavigationKey, navigation),
          ],
          capabilities: [controller, navigation, const EventSubmitPreparer()],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginRequestPort,
        corePluginPostPort,
        corePluginSiteStatePort,
        corePluginAccountConnectionPort,
        corePluginTopicRefreshPort,
        corePluginTrackerPort,
        corePluginTimezonePort,
        corePluginRouteNavigationPort,
        corePluginPostEditorPort,
      ],
    );
  }
}

final class _EventsLifecycle extends PluginSessionLifecycle {
  _EventsLifecycle(this.controller);
  final EventController controller;
  @override
  void setForeground(bool foreground) => controller.setForeground(foreground);
  @override
  void forget(String siteUrl) => controller.forget(siteUrl);
  @override
  void close() => controller.dispose();
}
