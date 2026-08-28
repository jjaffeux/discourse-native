import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../chat/chat_contract.dart';
import 'resenha_api.dart';
import 'resenha_controller.dart';
import 'resenha_diagnostics.dart';
import 'resenha_diagnostics_plugin.dart';
import 'resenha_plugin.dart';
import 'resenha_services.dart';
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
    registrar.addSession((bindings, dependencies) {
      final host = bindings.require(corePluginHostPort);
      final controller = ResenhaController(
        api: ResenhaApi(host.api),
        chatApi: dependencies.require(chatApiService),
        credentials: host.credentials,
        trackerFor: host.trackerFor,
        userIdFor: host.userIdFor,
        capabilityEnabledFor: (siteUrl) =>
            host.capabilityEnabledFor(siteUrl, 'resenha'),
        onCallSiteChanged: host.onCallSiteChanged,
        diagnostics: diagnostics ?? const NoopResenhaDiagnosticsRecorder(),
      );
      final shell = ResenhaShellService(
        controller: controller,
        host: host.navigation,
      );
      return PluginSessionContribution(
        lifecycle: _ResenhaSessionLifecycle(controller: controller),
        services: [
          PluginService<Object>(resenhaControllerService, controller),
          PluginService<Object>(resenhaShellService, shell),
        ],
        capabilities: [shell],
      );
    }, requires: const [corePluginHostPort]);
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
