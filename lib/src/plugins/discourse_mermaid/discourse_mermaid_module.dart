import '../../plugin_api/plugin_manifest.dart';
import 'discourse_mermaid_plugin.dart';

const discourseMermaidPluginId = PluginId('discourse-mermaid');
const discourseMermaidModule = DiscourseMermaidModule();

final class DiscourseMermaidModule implements PluginModule {
  const DiscourseMermaidModule();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: discourseMermaidPluginId);

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const DiscourseMermaidPlugin());
  }
}
