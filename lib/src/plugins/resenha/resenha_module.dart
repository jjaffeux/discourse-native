import '../../diagnostics/diagnostics_controller.dart';
import '../../plugin_api/background_retention.dart';
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
import 'resenha_shell_service.dart';

const resenhaModule = ResenhaModule();

/// Complete production registration for the bundled Resenha feature.
final class ResenhaModule implements PluginModule {
  const ResenhaModule() : _includeDiagnostics = true;

  const ResenhaModule.withoutDiagnostics() : _includeDiagnostics = false;

  final bool _includeDiagnostics;

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
    id: resenhaPluginId,
    dependencies: [const PluginDependency(chatPluginId)],
    routeNamespaces: {'resenha'},
    exclusiveClaims: {'app-global-media-session'},
    liveChannelScopes: {
      const PluginLiveChannelScope.prefix('/resenha'),
      const PluginLiveChannelScope.prefix('/chat'),
    },
  );

  @override
  void register(PluginRegistrar registrar) {
    final diagnostics = _includeDiagnostics ? ResenhaDiagnosticsPlugin() : null;
    registrar.addCapability(const ResenhaPlugin());
    registrar.addRouteNamespace('resenha');
    registrar.addExclusiveClaim('app-global-media-session');
    registrar.addLiveChannelScope(
      const PluginLiveChannelScope.prefix('/resenha'),
    );
    registrar.addLiveChannelScope(const PluginLiveChannelScope.prefix('/chat'));
    if (diagnostics != null) {
      registrar.addCapability(diagnostics);
      registrar.addAppLifecycle(
        diagnostics,
        requires: const [pluginDiagnosticsReporterPort],
      );
    }
    registrar.addSession(
      (bindings, dependencies) {
        final transport = bindings.require(corePluginTransportPort);
        final retention = _ResenhaBackgroundRetention(
          bindings.require(corePluginBackgroundRetentionPort),
        );
        late final ResenhaController controller;
        controller = ResenhaController(
          api: ResenhaApi(transport),
          chatConversations: dependencies.require(chatConversationService),
          credentials: bindings.require(corePluginCredentialsPort),
          trackerFor: bindings.require(corePluginTrackerPort),
          userIdFor: bindings.require(corePluginUserPort),
          capabilityEnabledFor: (siteUrl) async => (await bindings.require(
            corePluginPresentationPort,
          )(siteUrl))?.resenhaSettings.enabled,
          onCallSiteChanged: () => retention.sync(controller.activeSiteUrl),
          diagnostics: diagnostics ?? const NoopResenhaDiagnosticsRecorder(),
          reporter: bindings.require(pluginDiagnosticsReporterPort),
        );
        final shell = ResenhaShellService(
          controller: controller,
          host: bindings.require(corePluginRouteNavigationPort),
        );
        return PluginSessionContribution(
          lifecycle: _ResenhaSessionLifecycle(
            controller: controller,
            retention: retention,
          ),
          services: [
            PluginService<Object>(resenhaControllerService, controller),
            PluginService<Object>(resenhaShellService, shell),
          ],
          capabilities: [shell],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginCredentialsPort,
        corePluginTrackerPort,
        corePluginUserPort,
        corePluginPresentationPort,
        corePluginBackgroundRetentionPort,
        corePluginRouteNavigationPort,
        pluginDiagnosticsReporterPort,
      ],
    );
  }
}

final class _ResenhaSessionLifecycle extends PluginSessionLifecycle {
  _ResenhaSessionLifecycle({required this.controller, required this.retention});

  final ResenhaController controller;
  final _ResenhaBackgroundRetention retention;

  @override
  void setForeground(bool foreground) => controller.setForeground(foreground);

  @override
  void forget(String siteUrl) {
    controller.forget(siteUrl);
    retention.forget(siteUrl);
  }

  @override
  void close() {
    try {
      controller.dispose();
    } finally {
      retention.close();
    }
  }
}

/// Resenha alone decides when voice-call signalling needs background time.
/// Core sees only an ordinary owner-scoped lease and composes it with claims
/// from any other plugin.
final class _ResenhaBackgroundRetention {
  _ResenhaBackgroundRetention(this._host);

  final PluginBackgroundRetentionHost _host;
  PluginBackgroundRetentionLease? _lease;

  void sync(String? siteUrl) {
    final held = _lease;
    if (held?.siteUrl == siteUrl && held?.isReleased == false) return;
    held?.release();
    _lease = siteUrl == null ? null : _host.retain(siteUrl);
  }

  void forget(String siteUrl) {
    if (_lease?.siteUrl != siteUrl) return;
    _lease?.release();
    _lease = null;
  }

  void close() {
    _lease?.release();
    _lease = null;
  }
}
