import 'package:discourse_native/discourse_plugin_sdk.dart';

import '../chat/chat_contract.dart';
import 'voice_api.dart';
import 'voice_call_controller_port.dart';
import 'voice_call_port.dart';
import 'voice_chat_inbox.dart';
import 'voice_controller.dart';

import 'voice_idle.dart';
import 'voice_plugin.dart';
import 'voice_services.dart';
import 'voice_settings.dart';
import 'voice_shell_service.dart';

const voiceModule = VoiceModule();

final class VoiceModule implements PluginModule {
  const VoiceModule();

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
    id: voicePluginId,
    dependencies: [const PluginDependency(chatPluginId)],
    routeNamespaces: {
      for (final namespace in VoiceNamespace.values) namespace.name,
    },
    exclusiveClaims: {'app-global-media-session'},
    liveChannelScopes: {
      for (final namespace in VoiceNamespace.values)
        PluginLiveChannelScope.prefix(namespace.root),
    },
  );

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const VoicePlugin());
    for (final namespace in VoiceNamespace.values) {
      registrar.addRouteNamespace(namespace.name);
      registrar.addLiveChannelScope(
        PluginLiveChannelScope.prefix(namespace.root),
      );
    }
    registrar.addExclusiveClaim('app-global-media-session');
    registrar.addSession(
      (bindings, dependencies) {
        final transport = bindings.require(corePluginTransportPort);
        final siteState = bindings.require(corePluginSiteStatePort);
        final retention = _VoiceBackgroundRetention(
          bindings.require(corePluginBackgroundRetentionPort),
        );
        final host = bindings.require(corePluginRouteNavigationPort);
        bool meshPrivacyWarningEnabled(String siteUrl) => siteState
            .siteConfigFor(siteUrl)
            .voiceSettings
            .meshPrivacyWarningEnabled;
        late final VoiceController controller;
        late final VoiceShellService shell;
        controller = VoiceController(
          api: VoiceApi(
            transport,
            namespaceFor: (siteUrl) =>
                siteState.siteConfigFor(siteUrl).voiceSettings.namespace,
          ),
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
          videoMaxPublishersFor: (siteUrl) =>
              siteState.siteConfigFor(siteUrl).voiceSettings.videoMaxPublishers,
          siteNameFor: (siteUrl) => host.sites
              .where((site) => site.url == siteUrl)
              .firstOrNull
              ?.title,
          meshPrivacyWarningEnabledFor: meshPrivacyWarningEnabled,
          // A call answered from the system's UI lands on its room page
          // when the app is next in front.
          onIncomingCallAnswered: (siteUrl, room) => shell.openRoom(
            siteUrl: siteUrl,
            route: ContentRoute(
              destination: ExtensionDestination(VoicePlugin.routeId(room.id)),
              title: room.name,
              icon: DIcons.microphoneLines,
            ),
          ),
        );
        shell = VoiceShellService(
          controller: controller,
          host: host,
          enabled: (siteUrl) =>
              siteState.siteConfigFor(siteUrl).voiceSettings.enabled,
          recordingEnabled: (siteUrl) =>
              siteState.siteConfigFor(siteUrl).voiceSettings.recordingEnabled,
          meshPrivacyWarningEnabled: meshPrivacyWarningEnabled,
          autoStatusEnabled: (siteUrl) =>
              siteState.siteConfigFor(siteUrl).voiceSettings.autoStatusEnabled,
          currentUsername: (siteUrl) =>
              siteState.currentUserFor(siteUrl)?.username,
        );
        final inboxRooms = dependencies.require(chatInboxRoomsService);
        final detachInbox = inboxRooms.attach(
          VoiceChatInbox(controller, shell),
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
            detachInbox: detachInbox,
          ),
          services: [
            PluginService<Object>(voiceChatInboxService, inboxRooms),
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
      ],
    );
  }
}

final class _VoiceSessionLifecycle extends PluginSessionLifecycle {
  _VoiceSessionLifecycle({
    required this.controller,
    required this.callPort,
    required this.retention,
    required this.detachInbox,
  });

  final VoiceController controller;
  final VoiceCallPort callPort;
  final _VoiceBackgroundRetention retention;
  final void Function() detachInbox;

  @override
  void setForeground(bool foreground) => controller.setForeground(foreground);

  @override
  void forget(String siteUrl) {
    controller.forget(siteUrl);
    retention.forget(siteUrl);
  }

  @override
  Future<void> close() async {
    detachInbox();
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
