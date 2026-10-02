import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'ai_conversations_plugin.dart';
import 'ai_conversations_service.dart';
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
    registrar.addCapability(const AiConversationsPlugin());
    registrar.addCapability(const AiSummaryPlugin());
    registrar.addCapability(const AiProofreadingPlugin());
    registrar.addLiveChannelScope(
      const PluginLiveChannelScope.prefix('/discourse-ai'),
    );
    registrar.addSession(
      (bindings, _) {
        final summary = AiSummaryController(
          cooking: bindings.require(corePluginCookingPort),
          api: AiSummaryApi(bindings.require(corePluginTransportPort)),
          requests: bindings.require(corePluginRequestPort),
          trackerFor: bindings.require(corePluginTrackerPort),
        );
        final proofreading = AiProofreadingController(
          api: AiProofreadingApi(bindings.require(corePluginTransportPort)),
          requests: bindings.require(corePluginRequestPort),
          siteState: bindings.require(corePluginSiteStatePort),
          freshAccount: bindings.require(corePluginFreshAccountPort),
          currentUserId: bindings.require(corePluginUserPort),
          diagnostics: bindings.require(pluginDiagnosticsReporterPort),
        );
        final conversations = AiConversationsService(
          transport: bindings.require(corePluginTransportPort),
          requests: bindings.require(corePluginRequestPort),
          siteState: bindings.require(corePluginSiteStatePort),
          navigation: bindings.require(corePluginRouteNavigationPort),
          topicLists: bindings.require(corePluginTopicListNavigationPort),
        );
        return PluginSessionContribution(
          lifecycle: _DiscourseAiSessionLifecycle(summary, proofreading),
          services: [
            PluginService<Object>(aiConversationsService, conversations),
            PluginService<Object>(aiSummaryControllerService, summary),
            PluginService<Object>(
              aiProofreadingControllerService,
              proofreading,
            ),
          ],
          capabilities: [proofreading, conversations],
        );
      },
      requires: const [
        corePluginCookingPort,
        corePluginTransportPort,
        corePluginRequestPort,
        corePluginTrackerPort,
        corePluginSiteStatePort,
        corePluginRouteNavigationPort,
        corePluginTopicListNavigationPort,
        corePluginFreshAccountPort,
        corePluginUserPort,
        pluginDiagnosticsReporterPort,
      ],
    );
  }
}

final class _DiscourseAiSessionLifecycle extends PluginSessionLifecycle {
  _DiscourseAiSessionLifecycle(this.summary, this.proofreading);

  final AiSummaryController summary;
  final AiProofreadingController proofreading;

  @override
  void forget(String siteUrl) {
    summary.forget(siteUrl);
    proofreading.forget(siteUrl);
  }

  @override
  void close() {
    summary.dispose();
    proofreading.dispose();
  }
}
