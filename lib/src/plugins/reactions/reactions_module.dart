import '../../diagnostics/diagnostics_controller.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/discourse_model_codec.dart';
import '../../plugin_api/plugin_manifest.dart';
import 'reactions_api.dart';
import 'reactions_api_client.dart';
import 'reactions_controller.dart';
import 'reactions_plugin.dart';
import 'reactions_services.dart';

const reactionsModule = ReactionsModule();

typedef ReactionsApiFactory =
    ({ReactionsApi reads, ReactionsWriteApi writes}) Function(
      PluginApiTransport transport,
      DiscourseModelCodec models,
    );

final class ReactionsModule implements PluginModule {
  const ReactionsModule({this.apiFactory});

  final ReactionsApiFactory? apiFactory;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: reactionsPluginId);

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const ReactionsPlugin());
    registrar.addSession(
      (bindings, _) {
        final transport = bindings.require(corePluginTransportPort);
        final models = bindings.require(corePluginModelCodecPort);
        final clients = switch (apiFactory) {
          final factory? => factory(transport, models),
          null => () {
            final client = ReactionsApiClient(transport, models);
            return (reads: client, writes: client);
          }(),
        };
        final emoji = bindings.require(corePluginEmojiPort);
        final controller = ReactionsController(
          api: clients.reads,
          writes: clients.writes,
          requests: bindings.require(corePluginRequestPort),
          posts: bindings.require(corePluginPostPort),
          siteState: bindings.require(corePluginSiteStatePort),
          resolveSiteConfig: bindings.require(corePluginPresentationPort),
          emoji: emoji,
          diagnostics: bindings.require(pluginDiagnosticsReporterPort),
        );
        return PluginSessionContribution(
          lifecycle: _ReactionsSessionLifecycle(controller),
          services: [
            PluginService<Object>(reactionsControllerService, controller),
            PluginService<Object>(reactionsEmojiHostService, emoji),
          ],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginModelCodecPort,
        corePluginRequestPort,
        corePluginPostPort,
        corePluginSiteStatePort,
        corePluginPresentationPort,
        corePluginEmojiPort,
        pluginDiagnosticsReporterPort,
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
