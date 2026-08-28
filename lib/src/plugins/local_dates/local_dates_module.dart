import '../../plugin_api/plugin_manifest.dart';
import 'local_dates_contract.dart';
import 'local_dates_cooked_time_parser.dart';
import 'local_dates_plugin.dart';

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
    registrar.addSession(
      (_, _) => PluginSessionContribution(
        lifecycle: _LocalDatesSessionLifecycle(),
        services: const [
          PluginService<Object>(
            localDatesCookedTimeParserService,
            LocalDatesCookedTimeParser(),
          ),
        ],
      ),
    );
  }
}

final class _LocalDatesSessionLifecycle extends PluginSessionLifecycle {}
