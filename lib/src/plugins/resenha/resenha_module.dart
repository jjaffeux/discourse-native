import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../chat/chat_contract.dart';
import 'resenha_api.dart';
import 'resenha_controller.dart';
import 'resenha_diagnostics.dart';
import 'resenha_diagnostics_plugin.dart';
import 'resenha_plugin.dart';
import 'resenha_services.dart';
import 'resenha_settings.dart';
import 'resenha_shell_extension.dart';

const resenhaModule = ResenhaModule();

/// Complete production registration for the bundled Resenha feature.
final class ResenhaModule implements PluginModule {
  const ResenhaModule({this.includeDiagnostics = true});

  final bool includeDiagnostics;

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
    id: resenhaPluginId,
    dependencies: [PluginDependency(chatPluginId)],
    routeNamespaces: {'resenha'},
    exclusiveClaims: {'app-global-media-session'},
  );

  @override
  void register(PluginRegistrar registrar) {
    final diagnostics = includeDiagnostics ? ResenhaDiagnosticsPlugin() : null;
    registrar.addCapability(const ResenhaPlugin());
    registrar.addRouteNamespace('resenha');
    registrar.addExclusiveClaim('app-global-media-session');
    if (diagnostics != null) {
      registrar.addCapability(diagnostics);
      registrar.addAppLifecycle(diagnostics);
    }
    registrar.addSession(
      (bindings, dependencies) {
        final transport = bindings.require(corePluginTransportPort);
        final siteState = bindings.require(corePluginSiteStatePort);
        final controller = ResenhaController(
          api: ResenhaApi(transport),
          chatApi: dependencies.require(chatApiService),
          requests: bindings.require(corePluginRequestPort),
          channelsFor: bindings.require(corePluginChannelPort),
          userIdFor: bindings.require(corePluginUserPort),
          capabilityEnabledFor: (siteUrl) async => (await bindings.require(
            corePluginPresentationPort,
          )(siteUrl))?.resenhaSettings.enabled,
          onCallSiteChanged: bindings.require(corePluginTrackingSyncPort),
          diagnostics: diagnostics ?? const NoopResenhaDiagnosticsRecorder(),
        );
        final shell = ResenhaShellService(
          controller: controller,
          host: bindings.require(corePluginRouteNavigationPort),
          recordingEnabled: (siteUrl) =>
              siteState.siteConfigFor(siteUrl).resenhaSettings.recordingEnabled,
        );
        return PluginSessionContribution(
          lifecycle: _ResenhaSessionLifecycle(controller: controller),
          services: [
            PluginService<Object>(resenhaControllerService, controller),
            PluginService<Object>(resenhaShellService, shell),
          ],
          capabilities: [shell],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginRequestPort,
        corePluginChannelPort,
        corePluginUserPort,
        corePluginPresentationPort,
        corePluginSiteStatePort,
        corePluginTrackingSyncPort,
        corePluginRouteNavigationPort,
      ],
    );
  }
}

final class _ResenhaSessionLifecycle extends PluginSessionLifecycle {
  _ResenhaSessionLifecycle({required this.controller});

  final ResenhaController controller;

  @override
  void setForeground(bool foreground) => controller.setForeground(foreground);

  @override
  void forget(String siteUrl) => controller.forget(siteUrl);

  @override
  void close() => controller.dispose();
}
