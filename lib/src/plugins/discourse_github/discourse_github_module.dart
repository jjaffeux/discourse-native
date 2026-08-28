import '../../plugin_api/plugin_manifest.dart';
import '../local_dates/local_dates_contract.dart';
import 'discourse_github_plugin.dart';

const discourseGithubPluginId = PluginId('discourse-github');
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
  }
}
