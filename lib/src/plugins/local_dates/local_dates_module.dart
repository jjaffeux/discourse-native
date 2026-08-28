import '../../plugin_api/plugin_manifest.dart';
import 'local_dates_plugin.dart';

const localDatesPluginId = PluginId('discourse-local-dates');
const localDatesModule = LocalDatesModule();

final class LocalDatesModule implements PluginModule {
  const LocalDatesModule();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
    id: localDatesPluginId,
    syntaxIds: {'local-dates'},
  );

  @override
  void register(PluginRegistrar registrar) {
    const plugin = LocalDatesPlugin();
    registrar.addCapability(plugin);
    registrar.addSyntaxId(plugin.syntaxId);
  }
}
