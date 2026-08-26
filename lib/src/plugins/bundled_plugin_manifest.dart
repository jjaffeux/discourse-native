import '../plugin_api/core_plugin_host.dart';
import 'assign/assign_api.dart';
import 'assign/assign_plugin.dart';
import 'assign/assignment.dart';
import 'assign/assignment_controller.dart';
import 'chat/chat_api.dart';
import 'chat/chat_api_client.dart';
import 'chat/chat_controller.dart';
import 'chat/chat_plugin.dart';
import 'chat/chat_search_controller.dart';
import 'chat/chat_shell_extension.dart';
import 'discourse_ai/ai_summary_api.dart';
import 'discourse_ai/ai_summary_controller.dart';
import 'discourse_ai/ai_summary_plugin.dart';
import 'gifs/gifs_api.dart';
import 'gifs/gifs_api_client.dart';
import 'gifs/gifs_plugin.dart';
import 'local_dates/local_dates_plugin.dart';
import 'plugin_manifest.dart';
import 'plugin_services.dart';
import 'poll/poll_plugin.dart';
import 'reactions/reactions_api.dart';
import 'reactions/reactions_api_client.dart';
import 'reactions/reactions_controller.dart';
import 'reactions/reactions_plugin.dart';
import 'resenha/resenha_api.dart';
import 'resenha/resenha_controller.dart';
import 'resenha/resenha_diagnostics.dart';
import 'resenha/resenha_diagnostics_plugin.dart';
import 'resenha/resenha_plugin.dart';
import 'resenha/resenha_shell_extension.dart';
import 'site_plugin_api.dart';

const List<PluginModule> _bundledFeatureModules = [
  _BundledModule(ReactionsPlugin(), session: _reactionsSession),
  _BundledModule(LocalDatesPlugin(), syntaxIds: {'date', 'date-range'}),
  _BundledModule(PollPlugin(), syntaxIds: {'poll'}),
  _BundledModule(GifsPlugin(), session: _gifsSession),
  _BundledModule(AiSummaryPlugin(), session: _aiSummarySession),
  _BundledModule(AssignPlugin(), session: _assignmentSession),
  _BundledModule(
    ChatPlugin(),
    session: _chatSession,
    routeNamespaces: {'chat'},
  ),
];

/// The one deterministic composition root for the full application build.
const PluginManifest bundledPluginManifest = PluginManifest([
  ..._bundledFeatureModules,
  _ResenhaModule(),
]);

/// The full feature graph with app-global diagnostics ownership omitted.
///
/// Widget hosts which provide their own diagnostics lifecycle can use this
/// profile while retaining every forum feature and session capability.
const PluginManifest bundledPluginManifestWithoutDiagnostics = PluginManifest([
  ..._bundledFeatureModules,
  _ResenhaModule(includeDiagnostics: false),
]);

/// Compatibility adapter while each feature moves richer registrations beside
/// its existing capability implementation.
final class _BundledModule implements PluginModule {
  const _BundledModule(
    this.plugin, {
    this.session,
    this.routeNamespaces = const {},
    this.syntaxIds = const {},
  });

  final SitePlugin plugin;
  final _BundledSession? session;
  final Set<String> routeNamespaces;
  final Set<String> syntaxIds;

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
    id: PluginId(plugin.name),
    routeNamespaces: routeNamespaces,
    syntaxIds: syntaxIds,
  );

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(plugin);
    session?.call(registrar);
  }
}

typedef _BundledSession = void Function(PluginRegistrar registrar);

final class _ResenhaModule implements PluginModule {
  const _ResenhaModule({this.includeDiagnostics = true});

  final bool includeDiagnostics;

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
    id: PluginId('resenha'),
    routeNamespaces: {'resenha'},
    exclusiveClaims: {'app-global-media-session'},
  );

  @override
  void register(PluginRegistrar registrar) {
    final diagnostics = includeDiagnostics ? ResenhaDiagnosticsPlugin() : null;
    registrar.addCapability(const ResenhaPlugin());
    if (diagnostics != null) {
      registrar.addCapability(diagnostics);
      registrar.addAppLifecycle(diagnostics);
    }
    _resenhaSession(
      registrar,
      diagnostics ?? const NoopResenhaDiagnosticsRecorder(),
    );
  }
}

void _reactionsSession(PluginRegistrar registrar) {
  registrar.addSession((bindings) {
    final host = bindings.require(corePluginHostPort);
    final api = host.api is ReactionsApi
        ? host.api as ReactionsApi
        : ReactionsApiClient(host.api, host.api.models);
    final controller = ReactionsController(
      api: api,
      credentials: host.credentials,
      store: host.store,
      lifecycle: host.siteLifecycle,
    );
    return PluginSessionContribution(
      lifecycle: _ControllerLifecycle(
        forget: controller.forget,
        close: controller.dispose,
      ),
      services: [PluginService<Object>(reactionsControllerService, controller)],
    );
  }, requires: const [corePluginHostPort]);
}

void _gifsSession(PluginRegistrar registrar) {
  registrar.addSession((bindings) {
    final host = bindings.require(corePluginHostPort);
    return PluginSessionContribution(
      lifecycle: _ControllerLifecycle(),
      services: [
        PluginService<Object>(
          gifsApiService,
          host.api is GifsApi ? host.api as GifsApi : GifsApiClient(host.api),
        ),
      ],
    );
  }, requires: const [corePluginHostPort]);
}

void _assignmentSession(PluginRegistrar registrar) {
  registrar.addSession((bindings) {
    final host = bindings.require(corePluginHostPort);
    final controller = AssignmentController(
      api: AssignApi(host.api),
      credentials: host.credentials,
      lifecycle: host.siteLifecycle,
      canAssign: (siteUrl, target) {
        final reference = switch (target.type) {
          AssignmentTargetType.topic => PluginTarget.topic(target.id),
          AssignmentTargetType.post => PluginTarget.post(
            target.id,
            topicId: target.topicId,
          ),
        };
        final snapshot = host.dataForTarget(siteUrl, reference);
        if (!snapshot.valid) return false;
        final recordPermission = snapshot.data
            .get(assignmentsDataKey)
            ?.canAssign;
        return host.canPerform(siteUrl, 'assign', recordPermission);
      },
      reloadTopic: host.reloadTopic,
      invalidateLegacyFallback: (siteUrl) =>
          host.invalidateFallback(siteUrl, 'assign'),
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
  }, requires: const [corePluginHostPort]);
}

void _aiSummarySession(PluginRegistrar registrar) {
  registrar.addSession((bindings) {
    final host = bindings.require(corePluginHostPort);
    final controller = AiSummaryController(
      api: AiSummaryApi(host.api),
      credentials: host.credentials,
      lifecycle: host.siteLifecycle,
      trackerFor: host.trackerFor,
    );
    return PluginSessionContribution(
      lifecycle: _ControllerLifecycle(),
      services: [PluginService<Object>(aiSummaryControllerService, controller)],
    );
  }, requires: const [corePluginHostPort]);
}

void _chatSession(PluginRegistrar registrar) {
  registrar.addSession((bindings) {
    final host = bindings.require(corePluginHostPort);
    final chatApi = host.api is ChatApi
        ? host.api as ChatApi
        : ChatApiClient(host.api);
    final controller = ChatController(
      api: chatApi,
      credentials: host.credentials,
      store: host.store,
      lifecycle: host.siteLifecycle,
      currentUserFor: host.currentUserFor,
      siteConfigFor: host.siteConfigFor,
      previewEngine: host.previewEngine,
      onChatNotificationsDelta: host.applyNotificationDelta,
      onSiteUnreachable: host.markSiteUnreachable,
    );
    final searchController = ChatSearchController(
      api: chatApi,
      credentials: host.credentials,
      store: host.store,
      lifecycle: host.siteLifecycle,
    );
    final shell = ChatShellService(
      chat: controller,
      host: host.navigation,
      store: host.store,
    );
    return PluginSessionContribution(
      lifecycle: _ControllerLifecycle(
        forget: (siteUrl) {
          controller.forget(siteUrl);
          searchController.forget(siteUrl);
        },
        close: () {
          shell.dispose();
          controller.dispose();
          searchController.dispose();
        },
      ),
      services: [
        PluginService<Object>(chatControllerService, controller),
        PluginService<Object>(chatSearchControllerService, searchController),
        PluginService<Object>(chatShellService, shell),
      ],
      capabilities: [shell],
    );
  }, requires: const [corePluginHostPort]);
}

void _resenhaSession(
  PluginRegistrar registrar,
  ResenhaDiagnosticsRecorder diagnostics,
) {
  registrar.addSession((bindings) {
    final host = bindings.require(corePluginHostPort);
    final api = host.api;
    final controller = ResenhaController(
      api: ResenhaApi(api),
      chatApi: ChatApiClient(api),
      credentials: host.credentials,
      trackerFor: host.trackerFor,
      userIdFor: host.userIdFor,
      capabilityEnabledFor: (siteUrl) =>
          host.capabilityEnabledFor(siteUrl, 'resenha'),
      onCallSiteChanged: host.onCallSiteChanged,
      diagnostics: diagnostics,
    );
    final shell = ResenhaShellService(
      controller: controller,
      host: host.navigation,
    );
    return PluginSessionContribution(
      lifecycle: _ControllerLifecycle(
        foreground: controller.setForeground,
        forget: controller.forget,
        close: controller.dispose,
      ),
      services: [
        PluginService<Object>(resenhaControllerService, controller),
        PluginService<Object>(resenhaShellService, shell),
      ],
      capabilities: [shell],
    );
  }, requires: const [corePluginHostPort]);
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
