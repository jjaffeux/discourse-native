import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
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
    registrar.addLiveChannelScope(
      const PluginLiveChannelScope.prefix('/discourse-ai'),
    );
    registrar.addSession(
      (bindings, _) {
        final controller = AiSummaryController(
          api: AiSummaryApi(bindings.require(corePluginTransportPort)),
          requests: bindings.require(corePluginRequestPort),
          trackerFor: bindings.require(corePluginTrackerPort),
        );
        return PluginSessionContribution(
          lifecycle: _DiscourseAiSessionLifecycle(),
          services: [
            PluginService<Object>(aiSummaryControllerService, controller),
          ],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginRequestPort,
        corePluginTrackerPort,
      ],
    );
  }
}

final class _DiscourseAiSessionLifecycle extends PluginSessionLifecycle {}
