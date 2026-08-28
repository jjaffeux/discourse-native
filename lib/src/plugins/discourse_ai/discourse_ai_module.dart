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
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: discourseAiPluginId);

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const AiSummaryPlugin());
    registrar.addSession((bindings, _) {
      final host = bindings.require(corePluginHostPort);
      final controller = AiSummaryController(
        api: AiSummaryApi(host.api),
        credentials: host.credentials,
        lifecycle: host.siteLifecycle,
        trackerFor: host.trackerFor,
      );
      return PluginSessionContribution(
        lifecycle: _DiscourseAiSessionLifecycle(),
        services: [
          PluginService<Object>(aiSummaryControllerService, controller),
        ],
      );
    }, requires: const [corePluginHostPort]);
  }
}

final class _DiscourseAiSessionLifecycle extends PluginSessionLifecycle {}
