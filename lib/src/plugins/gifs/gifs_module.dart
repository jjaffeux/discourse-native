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
        final credentials = bindings.require(corePluginCredentialsPort);
        final lifecycle = bindings.require(corePluginSiteLifecyclePort);
        final api = transport is GifsApi
            ? transport as GifsApi
            : GifsApiClient(transport);
        return PluginSessionContribution(
          lifecycle: _GifsSessionLifecycle(),
          services: [
            PluginService<Object>(gifsApiService, api),
            PluginService<Object>(
              gifsPickerHostService,
              GifsPickerHost(
                api: api,
                credentials: credentials,
                lifecycle: lifecycle,
              ),
            ),
          ],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginCredentialsPort,
        corePluginSiteLifecyclePort,
      ],
    );
  }
}

final class _GifsSessionLifecycle extends PluginSessionLifecycle {}
