import 'assign/assign_api.dart';
import 'assign/assign_plugin.dart';
import 'assign/assignment_controller.dart';
import 'chat/chat_controller.dart';
import 'chat/chat_plugin.dart';
import 'chat/chat_search_controller.dart';
import 'discourse_ai/ai_summary_api.dart';
import 'discourse_ai/ai_summary_controller.dart';
import 'discourse_ai/ai_summary_plugin.dart';
import 'gifs/gifs_plugin.dart';
import 'local_dates/local_dates_plugin.dart';
import 'plugin_host_ports.dart';
import 'plugin_manifest.dart';
import 'plugin_services.dart';
import 'poll/poll_plugin.dart';
import 'reactions/reactions_api_client.dart';
import 'reactions/reactions_controller.dart';
import 'reactions/reactions_plugin.dart';
import 'resenha/resenha_api.dart';
import 'resenha/resenha_controller.dart';
import 'resenha/resenha_plugin.dart';
import 'site_plugin_api.dart';

/// The one deterministic composition root for the full application build.
const PluginManifest bundledPluginManifest = PluginManifest([
  _BundledModule(ReactionsPlugin(), session: _reactionsSession),
  _BundledModule(LocalDatesPlugin(), syntaxIds: {'date', 'date-range'}),
  _BundledModule(PollPlugin(), syntaxIds: {'poll'}),
  _BundledModule(GifsPlugin()),
  _BundledModule(AiSummaryPlugin(), session: _aiSummarySession),
  _BundledModule(AssignPlugin(), session: _assignmentSession),
  _BundledModule(
    ChatPlugin(),
    session: _chatSession,
    routeNamespaces: {'chat'},
  ),
  _BundledModule(
    ResenhaPlugin(),
    session: _resenhaSession,
    routeNamespaces: {'resenha'},
    exclusiveClaims: {'app-global-media-session'},
  ),
]);

/// Compatibility adapter while each feature moves richer registrations beside
/// its existing capability implementation.
final class _BundledModule implements PluginModule {
  const _BundledModule(
    this.plugin, {
    this.session,
    this.routeNamespaces = const {},
    this.syntaxIds = const {},
    this.exclusiveClaims = const {},
  });

  final SitePlugin plugin;
  final _BundledSession? session;
  final Set<String> routeNamespaces;
  final Set<String> syntaxIds;
  final Set<String> exclusiveClaims;

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
    id: PluginId(plugin.name),
    routeNamespaces: routeNamespaces,
    syntaxIds: syntaxIds,
    exclusiveClaims: exclusiveClaims,
  );

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(plugin);
    session?.call(registrar);
  }
}

typedef _BundledSession = void Function(PluginRegistrar registrar);

void _reactionsSession(PluginRegistrar registrar) {
  registrar.addSession(
    (bindings) {
      final controller = ReactionsController(
        api: ReactionsApiClient(
          bindings.require(discourseApiPort),
          bindings.require(discourseApiPort).models,
        ),
        credentials: bindings.require(credentialReaderPort),
        store: bindings.require(storePort),
        lifecycle: bindings.require(siteLifecyclePort),
      );
      return PluginSessionContribution(
        lifecycle: _ControllerLifecycle(
          forget: controller.forget,
          close: controller.dispose,
        ),
        services: [
          PluginService<Object>(reactionsControllerService, controller),
        ],
      );
    },
    requires: const [
      discourseApiPort,
      credentialReaderPort,
      storePort,
      siteLifecyclePort,
    ],
  );
}

void _assignmentSession(PluginRegistrar registrar) {
  registrar.addSession(
    (bindings) {
      final controller = AssignmentController(
        api: AssignApi(bindings.require(discourseApiPort)),
        credentials: bindings.require(credentialReaderPort),
        lifecycle: bindings.require(siteLifecyclePort),
        canAssign: bindings.require(assignmentPermissionPort),
        reloadTopic: bindings.require(assignmentTopicReloaderPort),
        invalidateLegacyFallback: bindings.require(
          assignmentFallbackInvalidatorPort,
        ),
      );
      return PluginSessionContribution(
        lifecycle: _ControllerLifecycle(
          forget: controller.forget,
          close: controller.dispose,
        ),
        services: [
          PluginService<Object>(assignmentControllerService, controller),
        ],
      );
    },
    requires: const [
      discourseApiPort,
      credentialReaderPort,
      siteLifecyclePort,
      assignmentPermissionPort,
      assignmentTopicReloaderPort,
      assignmentFallbackInvalidatorPort,
    ],
  );
}

void _aiSummarySession(PluginRegistrar registrar) {
  registrar.addSession(
    (bindings) {
      final controller = AiSummaryController(
        api: AiSummaryApi(bindings.require(discourseApiPort)),
        credentials: bindings.require(credentialReaderPort),
        lifecycle: bindings.require(siteLifecyclePort),
        trackerFor: bindings.require(trackerReaderPort),
      );
      return PluginSessionContribution(
        lifecycle: _ControllerLifecycle(),
        services: [
          PluginService<Object>(aiSummaryControllerService, controller),
        ],
      );
    },
    requires: const [
      discourseApiPort,
      credentialReaderPort,
      siteLifecyclePort,
      trackerReaderPort,
    ],
  );
}

void _chatSession(PluginRegistrar registrar) {
  registrar.addSession(
    (bindings) {
      final controller = ChatController(
        api: bindings.require(discourseApiPort),
        credentials: bindings.require(credentialReaderPort),
        store: bindings.require(storePort),
        lifecycle: bindings.require(siteLifecyclePort),
        currentUserFor: bindings.require(currentUserReaderPort),
        siteConfigFor: bindings.require(siteConfigReaderPort),
        previewEngine: bindings.require(chatPreviewEnginePort),
        onChatNotificationsDelta: bindings.require(chatNotificationsDeltaPort),
        onSiteUnreachable: bindings.require(siteUnreachablePort),
      );
      final searchController = ChatSearchController(
        api: bindings.require(discourseApiPort),
        credentials: bindings.require(credentialReaderPort),
        store: bindings.require(storePort),
        lifecycle: bindings.require(siteLifecyclePort),
      );
      return PluginSessionContribution(
        lifecycle: _ControllerLifecycle(
          forget: (siteUrl) {
            controller.forget(siteUrl);
            searchController.forget(siteUrl);
          },
          close: () {
            controller.dispose();
            searchController.dispose();
          },
        ),
        services: [
          PluginService<Object>(chatControllerService, controller),
          PluginService<Object>(chatSearchControllerService, searchController),
        ],
      );
    },
    requires: const [
      discourseApiPort,
      credentialReaderPort,
      storePort,
      siteLifecyclePort,
      currentUserReaderPort,
      siteConfigReaderPort,
      chatPreviewEnginePort,
      chatNotificationsDeltaPort,
      siteUnreachablePort,
    ],
  );
}

void _resenhaSession(PluginRegistrar registrar) {
  registrar.addSession(
    (bindings) {
      final api = bindings.require(discourseApiPort);
      final controller = ResenhaController(
        api: ResenhaApi(api),
        chatApi: api,
        credentials: bindings.require(credentialReaderPort),
        trackerFor: bindings.require(trackerReaderPort),
        userIdFor: bindings.require(userIdReaderPort),
        capabilityEnabledFor: bindings.require(resenhaCapabilityPort),
        onCallSiteChanged: bindings.require(callSiteChangedPort),
        diagnostics: bindings.require(resenhaDiagnosticsPort),
      );
      return PluginSessionContribution(
        lifecycle: _ControllerLifecycle(
          foreground: controller.setForeground,
          forget: controller.forget,
          close: controller.dispose,
        ),
        services: [PluginService<Object>(resenhaControllerService, controller)],
      );
    },
    requires: const [
      discourseApiPort,
      credentialReaderPort,
      trackerReaderPort,
      userIdReaderPort,
      resenhaCapabilityPort,
      callSiteChangedPort,
      resenhaDiagnosticsPort,
    ],
  );
}

final class _ControllerLifecycle extends PluginSessionLifecycle {
  _ControllerLifecycle({
    void Function(bool foreground)? foreground,
    void Function(String siteUrl)? forget,
    void Function()? close,
  }) : _onForeground = foreground,
       _onForget = forget,
       _onClose = close;

  final void Function(bool foreground)? _onForeground;
  final void Function(String siteUrl)? _onForget;
  final void Function()? _onClose;

  @override
  void setForeground(bool foreground) => _onForeground?.call(foreground);

  @override
  void forget(String siteUrl) => _onForget?.call(siteUrl);

  @override
  void close() => _onClose?.call();
}
