import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'discourse_mermaid_plugin.dart';

const discourseMermaidPluginId = PluginId('discourse-mermaid');
const discourseMermaidModule = DiscourseMermaidModule();

final class DiscourseMermaidModule implements PluginModule {
  const DiscourseMermaidModule();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
    id: discourseMermaidPluginId,
    syntaxIds: {'discourse-mermaid/chart'},
  );

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const DiscourseMermaidPlugin());
    registrar.addSyntaxId('discourse-mermaid/chart');
  }
}
