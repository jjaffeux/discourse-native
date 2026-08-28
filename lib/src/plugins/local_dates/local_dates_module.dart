import '../../plugin_api/plugin_manifest.dart';
import 'local_date_environment.dart';
import 'local_dates_plugin.dart';

const localDatesPluginId = PluginId('discourse-local-dates');

/// Production composition injects the process-owned timezone facility here;
/// tests and alternate hosts can construct [LocalDatesModule] with an isolated
/// environment instead.
final localDatesModule = LocalDatesModule(
  environment: LocalDateEnvironment.instance,
);

final class LocalDatesModule implements PluginModule {
  const LocalDatesModule({required this.environment});

  final LocalDateEnvironment environment;

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
    id: localDatesPluginId,
    syntaxIds: {'local-dates'},
  );

  @override
  void register(PluginRegistrar registrar) {
    final plugin = LocalDatesPlugin(environment: environment);
    registrar.addCapability(plugin);
    registrar.addSyntaxId(plugin.syntaxId);
  }
}
