import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'voice_api.dart';
import 'voice_call_controller_port.dart';
import 'voice_call_port.dart';
import 'voice_controller.dart';
import 'voice_diagnostics.dart';
import 'voice_diagnostics_plugin.dart';
import 'voice_idle.dart';
import 'voice_plugin.dart';
import 'voice_services.dart';
import 'voice_settings.dart';
import 'voice_shell_service.dart';

const voiceModule = VoiceModule();

final class VoiceModule implements PluginModule {
  const VoiceModule() : _includeDiagnostics = true;

  const VoiceModule.withoutDiagnostics() : _includeDiagnostics = false;

  final bool _includeDiagnostics;

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
    id: voicePluginId,
    dependencies: [const PluginDependency(chatPluginId)],
    routeNamespaces: {'voice'},
    exclusiveClaims: {'app-global-media-session'},
    liveChannelScopes: {const PluginLiveChannelScope.prefix('/voice')},
  );

  @override
  void register(PluginRegistrar registrar) {
    final diagnostics = _includeDiagnostics ? VoiceDiagnosticsPlugin() : null;
    registrar.addCapability(const VoicePlugin());
    registrar.addRouteNamespace('voice');
    registrar.addExclusiveClaim('app-global-media-session');
    registrar.addLiveChannelScope(
      const PluginLiveChannelScope.prefix('/voice'),
    );
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
        final siteState = bindings.require(corePluginSiteStatePort);
        final retention = _VoiceBackgroundRetention(
          bindings.require(corePluginBackgroundRetentionPort),
        );
        late final VoiceController controller;
        controller = VoiceController(
          api: VoiceApi(transport),
          chatConversations: dependencies.require(chatConversationService),
          requests: bindings.require(corePluginRequestPort),
          trackerFor: bindings.require(corePluginTrackerPort),
          userIdFor: bindings.require(corePluginUserPort),
          capabilityEnabledFor: (siteUrl) async => (await bindings.require(
            corePluginPresentationPort,
          )(siteUrl))?.voiceSettings.enabled,
          onCallSiteChanged: () => retention.sync(controller.activeSiteUrl),
          idleThresholdsFor: (siteUrl) => voiceIdleThresholds(
            siteState.siteConfigFor(siteUrl).voiceSettings,
          ),
          diagnostics: diagnostics ?? const NoopVoiceDiagnosticsRecorder(),
          reporter: bindings.require(pluginDiagnosticsReporterPort),
        );
        final shell = VoiceShellService(
          controller: controller,
          host: bindings.require(corePluginRouteNavigationPort),
          recordingEnabled: (siteUrl) =>
              siteState.siteConfigFor(siteUrl).voiceSettings.recordingEnabled,
          meshPrivacyWarningEnabled: (siteUrl) => siteState
              .siteConfigFor(siteUrl)
              .voiceSettings
              .meshPrivacyWarningEnabled,
          autoStatusEnabled: (siteUrl) =>
              siteState.siteConfigFor(siteUrl).voiceSettings.autoStatusEnabled,
        );
        final callPort = VoiceCallControllerPort(
          controller: controller,
          shell: shell,
        );
        return PluginSessionContribution(
          lifecycle: _VoiceSessionLifecycle(
            controller: controller,
            callPort: callPort,
            retention: retention,
          ),
          services: [
            PluginService<Object>(voiceControllerService, controller),
            PluginService<Object>(voiceShellService, shell),
            PluginService<Object>(voiceCallPortService, callPort),
          ],
          capabilities: [shell],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginRequestPort,
        corePluginTrackerPort,
        corePluginUserPort,
        corePluginPresentationPort,
        corePluginSiteStatePort,
        corePluginBackgroundRetentionPort,
        corePluginRouteNavigationPort,
        pluginDiagnosticsReporterPort,
      ],
    );
  }
}

final class _VoiceSessionLifecycle extends PluginSessionLifecycle {
  _VoiceSessionLifecycle({
    required this.controller,
    required this.callPort,
    required this.retention,
  });

  final VoiceController controller;
  final VoiceCallPort callPort;
  final _VoiceBackgroundRetention retention;

  @override
  void setForeground(bool foreground) => controller.setForeground(foreground);

  @override
  void forget(String siteUrl) {
    controller.forget(siteUrl);
    retention.forget(siteUrl);
  }

  @override
  Future<void> close() async {
    try {
      await Future.wait([callPort.close(), controller.close()]);
    } finally {
      retention.close();
    }
  }
}

/// Voice alone decides when voice-call signalling needs background time.
/// Core sees only an ordinary owner-scoped lease and composes it with claims
/// from any other plugin.
final class _VoiceBackgroundRetention {
  _VoiceBackgroundRetention(this._host);

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
