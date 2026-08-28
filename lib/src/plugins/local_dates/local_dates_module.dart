import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import 'local_dates_plugin.dart';
import 'local_dates_services.dart';

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
      (bindings, _) => PluginSessionContribution(
        lifecycle: _LocalDatesSessionLifecycle(),
        services: [
          PluginService<Object>(
            localDatesUiService,
            LocalDatesUiService(
              composer: bindings.require(corePluginComposerPort),
              siteState: bindings.require(corePluginSiteStatePort),
              currentSite: bindings.require(corePluginCurrentSitePort),
            ),
          ),
        ],
      ),
      requires: const [
        corePluginComposerPort,
        corePluginSiteStatePort,
        corePluginCurrentSitePort,
      ],
    );
  }
}

final class _LocalDatesSessionLifecycle extends PluginSessionLifecycle {}
