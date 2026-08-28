import '../../plugin_api/plugin_manifest.dart';
import '../local_dates/local_dates_contract.dart';
import 'discourse_github_plugin.dart';
import 'discourse_github_services.dart';

const discourseGithubModule = DiscourseGithubModule();

/// Complete production registration for the bundled discourse-github feature.
final class DiscourseGithubModule implements PluginModule {
  const DiscourseGithubModule();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
    id: discourseGithubPluginId,
    dependencies: [PluginDependency(localDatesPluginId, optional: true)],
  );

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const DiscourseGithubPlugin());
    registrar.addSession((_, dependencies) {
      final parser = dependencies.maybe(localDatesCookedTimeParserService);
      return PluginSessionContribution(
        lifecycle: _DiscourseGithubSessionLifecycle(),
        services: [
          if (parser case final CookedTimeParser value)
            PluginService<Object>(
              discourseGithubCookedTimeParserService,
              value,
            ),
        ],
      );
    });
  }
}

final class _DiscourseGithubSessionLifecycle extends PluginSessionLifecycle {}
