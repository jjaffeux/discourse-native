import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import 'gifs_api.dart';
import 'gifs_api_client.dart';
import 'gifs_plugin.dart';
import 'gifs_services.dart';

const gifsModule = GifsModule();

final class GifsModule implements PluginModule {
  const GifsModule();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(id: gifsPluginId);

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const GifsPlugin());
    registrar.addSession(
      (bindings, _) {
        final transport = bindings.require(corePluginTransportPort);
        final api = transport is GifsApi
            ? transport as GifsApi
            : GifsApiClient(transport);
        final session = GifsSessionService(
          api: api,
          requests: bindings.require(corePluginRequestPort),
          composer: bindings.require(corePluginComposerPort),
        );
        return PluginSessionContribution(
          lifecycle: _GifsSessionLifecycle(),
          services: [
            PluginService<Object>(gifsApiService, api),
            PluginService<Object>(gifsSessionService, session),
          ],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginRequestPort,
        corePluginComposerPort,
      ],
    );
  }
}

final class _GifsSessionLifecycle extends PluginSessionLifecycle {}
