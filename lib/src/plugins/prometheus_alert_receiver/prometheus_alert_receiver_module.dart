import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import 'alert_data.dart';
import 'prometheus_alert_receiver_plugin.dart';

const prometheusAlertReceiverModule = PrometheusAlertReceiverModule();

final class PrometheusAlertReceiverModule implements PluginModule {
  const PrometheusAlertReceiverModule();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: prometheusAlertReceiverPluginId);

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const PrometheusAlertReceiverPlugin());
    registrar.addSession(
      (bindings, _) => PluginSessionContribution(
        lifecycle: _AlertReceiverLifecycle(),
        services: [
          PluginService<Object>(
            alertSiteStateService,
            bindings.require(corePluginSiteStatePort),
          ),
          PluginService<Object>(
            alertQuoteService,
            bindings.require(corePluginPostQuotePort),
          ),
          PluginService<Object>(
            alertEmojiService,
            bindings.require(corePluginEmojiPort),
          ),
        ],
      ),
      requires: const [
        corePluginSiteStatePort,
        corePluginPostQuotePort,
        corePluginEmojiPort,
      ],
    );
  }
}

final class _AlertReceiverLifecycle extends PluginSessionLifecycle {}
