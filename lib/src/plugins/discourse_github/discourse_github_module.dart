import '../../plugin_api/plugin_manifest.dart';
import 'discourse_github_plugin.dart';

const discourseGithubPluginId = PluginId('discourse-github');
const discourseGithubModule = DiscourseGithubModule();

/// Complete production registration for the bundled discourse-github feature.
final class DiscourseGithubModule implements PluginModule {
  const DiscourseGithubModule();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: discourseGithubPluginId);

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const DiscourseGithubPlugin());
  }
}
