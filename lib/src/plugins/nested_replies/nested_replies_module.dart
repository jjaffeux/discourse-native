import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'nested_replies_api.dart';
import 'nested_replies_data.dart';
import 'nested_replies_plugin.dart';
import 'nested_replies_services.dart';

const nestedRepliesModule = NestedRepliesModule();

final class NestedRepliesModule implements PluginModule {
  const NestedRepliesModule();
  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: nestedRepliesPluginId);

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const NestedRepliesPlugin());
    registrar.addCapability(const NestedRepliesPostPlugin());
    registrar.addSession(
      (bindings, _) {
        final service = NestedRepliesServices(
          api: NestedRepliesApi(
            bindings.require(corePluginTransportPort),
            bindings.require(corePluginModelCodecPort),
          ),
          categories: PluginCategorySettingsApi(
            bindings.require(corePluginTransportPort),
          ),
          requests: bindings.require(corePluginRequestPort),
          siteState: bindings.require(corePluginSiteStatePort),
          readers: bindings.require(corePluginTopicReaderPort),
          records: bindings.require(corePluginTopicRecordsPort),
          topics: bindings.require(corePluginTopicRefreshPort),
          targets: bindings.require(corePluginTargetPort),
          navigation: bindings.require(corePluginRouteNavigationPort),
          accounts: bindings.require(corePluginFreshAccountPort),
        );
        return PluginSessionContribution(
          lifecycle: _NestedRepliesLifecycle(service),
          services: [PluginService<Object>(nestedRepliesServiceKey, service)],
          capabilities: [service],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginModelCodecPort,
        corePluginRequestPort,
        corePluginSiteStatePort,
        corePluginTopicReaderPort,
        corePluginTopicRecordsPort,
        corePluginTopicRefreshPort,
        corePluginTargetPort,
        corePluginRouteNavigationPort,
        corePluginFreshAccountPort,
      ],
    );
  }
}

final class _NestedRepliesLifecycle extends PluginSessionLifecycle {
  _NestedRepliesLifecycle(this.service);
  final NestedRepliesServices service;
  @override
  void forget(String siteUrl) => service.forget(siteUrl);
  @override
  void close() => service.dispose();
}
