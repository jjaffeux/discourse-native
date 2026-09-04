import '../../diagnostics/diagnostics_controller.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import 'ai_proofreading_api.dart';
import 'ai_proofreading_controller.dart';
import 'ai_proofreading_plugin.dart';
import 'ai_summary_api.dart';
import 'ai_summary_controller.dart';
import 'ai_summary_plugin.dart';
import 'discourse_ai_services.dart';

const discourseAiModule = DiscourseAiModule();

final class DiscourseAiModule implements PluginModule {
  const DiscourseAiModule();

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
    id: discourseAiPluginId,
    liveChannelScopes: {const PluginLiveChannelScope.prefix('/discourse-ai')},
  );

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const AiSummaryPlugin());
    registrar.addCapability(const AiProofreadingPlugin());
    registrar.addLiveChannelScope(
      const PluginLiveChannelScope.prefix('/discourse-ai'),
    );
    registrar.addSession(
      (bindings, _) {
        final summary = AiSummaryController(
          api: AiSummaryApi(bindings.require(corePluginTransportPort)),
          requests: bindings.require(corePluginRequestPort),
          trackerFor: bindings.require(corePluginTrackerPort),
        );
        final proofreading = AiProofreadingController(
          api: AiProofreadingApi(bindings.require(corePluginTransportPort)),
          requests: bindings.require(corePluginRequestPort),
          siteState: bindings.require(corePluginSiteStatePort),
          freshAccount: bindings.require(corePluginFreshAccountPort),
          diagnostics: bindings.require(pluginDiagnosticsReporterPort),
        );
        return PluginSessionContribution(
          lifecycle: _DiscourseAiSessionLifecycle(proofreading),
          services: [
            PluginService<Object>(aiSummaryControllerService, summary),
            PluginService<Object>(
              aiProofreadingControllerService,
              proofreading,
            ),
          ],
          capabilities: [proofreading],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginRequestPort,
        corePluginTrackerPort,
        corePluginSiteStatePort,
        corePluginFreshAccountPort,
        pluginDiagnosticsReporterPort,
      ],
    );
  }
}

final class _DiscourseAiSessionLifecycle extends PluginSessionLifecycle {
  _DiscourseAiSessionLifecycle(this.proofreading);

  final AiProofreadingController proofreading;

  @override
  void close() => proofreading.dispose();
}
