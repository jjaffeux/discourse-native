import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import 'gif_picker_session_impl.dart';
import 'gifs_api.dart';
import 'gifs_api_client.dart';
import 'gifs_plugin.dart';
import 'gifs_services.dart';

const gifsModule = GifsModule();

typedef GifsApiFactory = GifsApi Function(PluginApiTransport transport);

final class GifsModule implements PluginModule {
  const GifsModule({this.apiFactory});

  final GifsApiFactory? apiFactory;

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(id: gifsPluginId);

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const GifsPlugin());
    registrar.addSession(
      (bindings, _) {
        final transport = bindings.require(corePluginTransportPort);
        return PluginSessionContribution(
          lifecycle: _GifsSessionLifecycle(),
          services: [
            PluginService<Object>(
              gifsPickerSessionService,
              createGifPickerSession(
                api: apiFactory?.call(transport) ?? GifsApiClient(transport),
                requests: bindings.require(corePluginRequestPort),
                siteConfigFor: bindings
                    .require(corePluginSiteStatePort)
                    .siteConfigFor,
              ),
            ),
          ],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginRequestPort,
        corePluginSiteStatePort,
      ],
    );
  }
}

final class _GifsSessionLifecycle extends PluginSessionLifecycle {}
