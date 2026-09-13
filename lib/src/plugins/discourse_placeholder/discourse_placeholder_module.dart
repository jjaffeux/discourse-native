import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import 'discourse_placeholder_plugin.dart';
import 'placeholder_session.dart';
import 'placeholder_store.dart';

const discoursePlaceholderModule = DiscoursePlaceholderModule();

final class DiscoursePlaceholderModule implements PluginModule {
  const DiscoursePlaceholderModule({this.persistence});
  final PlaceholderPersistence? persistence;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: placeholderPluginId);

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const DiscoursePlaceholderPlugin());
    registrar.addSession((bindings, _) {
      final session = PlaceholderSession(
        persistence: persistence ?? PlaceholderStore(),
        currentUser: bindings.require(corePluginUserPort),
      );
      return PluginSessionContribution(
        lifecycle: _PlaceholderLifecycle(session),
        services: [PluginService<Object>(placeholderSessionService, session)],
      );
    }, requires: const [corePluginUserPort]);
  }
}

final class _PlaceholderLifecycle extends PluginSessionLifecycle {
  _PlaceholderLifecycle(this.session);
  final PlaceholderSession session;
  @override
  Future<void> setForeground(bool foreground) async {
    if (!foreground) await session.flush();
  }

  @override
  Future<void> forget(String siteUrl) => session.forget(siteUrl);
  @override
  Future<void> close() => session.close();
}
