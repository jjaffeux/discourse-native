import '../../plugin_api/plugin_manifest.dart';
import 'poll_plugin.dart';

const pollPluginId = PluginId('poll');
const pollModule = PollModule();

final class PollModule implements PluginModule {
  const PollModule();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: pollPluginId, syntaxIds: {'poll'});

  @override
  void register(PluginRegistrar registrar) {
    const plugin = PollPlugin();
    registrar.addCapability(plugin);
    registrar.addSyntaxId(plugin.syntaxId);
  }
}
