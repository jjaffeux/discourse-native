import '../../data/store.dart';
import '../../diagnostics/diagnostics_controller.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../gifs/gifs_contract.dart';
import 'chat_api.dart';
import 'chat_api_client.dart';
import 'chat_bookmark.dart';
import 'chat_controller.dart';
import 'chat_conversation.dart';
import 'chat_notification_counter.dart';
import 'chat_plugin.dart';
import 'chat_preview.dart';
import 'chat_search_controller.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

const chatModule = ChatModule();

typedef ChatApiFactory = ChatApi Function(PluginApiTransport transport);

/// Complete production registration for the bundled Chat feature.
final class ChatModule implements PluginModule {
  const ChatModule({this.apiFactory});

  final ChatApiFactory? apiFactory;

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
    id: chatPluginId,
    dependencies: [const PluginDependency(gifsPluginId, optional: true)],
    routeNamespaces: {'chat'},
    liveChannelScopes: {
      const PluginLiveChannelScope.prefix('/chat'),
      const PluginLiveChannelScope.prefix('/presence/chat'),
    },
  );

  @override
  void register(PluginRegistrar registrar) {
    registrar.addStaticContributionPoint(chatPreviewContributions);
    registrar.addCapability(const ChatPlugin());
    registrar.addRouteNamespace('chat');
    registrar.addLiveChannelScope(const PluginLiveChannelScope.prefix('/chat'));
    registrar.addLiveChannelScope(
      const PluginLiveChannelScope.prefix('/presence/chat'),
    );
    registrar.addSession(
      (bindings, dependencies) {
        final transport = bindings.require(corePluginTransportPort);
        final requests = bindings.require(corePluginRequestPort);
        final store = Store();
        final siteState = bindings.require(corePluginSiteStatePort);
        final accountEvents = bindings.require(corePluginAccountEventsPort);
        final composerHost = bindings.require(corePluginComposerPort);
        final chatApi = apiFactory?.call(transport) ?? ChatApiClient(transport);
        final gifs = dependencies.maybe(gifsPickerSessionService);
        final controller = ChatController(
          api: chatApi,
          requests: requests,
          store: store,
          currentUserFor: siteState.currentUserFor,
          siteConfigFor: siteState.siteConfigFor,
          previewEngine: ChatPreviewEngine(
            plugins: bindings
                .require(corePluginStaticContributionsPort)
                .contributions(chatPreviewContributions),
            reporter: bindings.require(pluginDiagnosticsReporterPort),
          ),
          reporter: bindings.require(pluginDiagnosticsReporterPort),
          onChatNotificationsDelta: (siteUrl, delta) =>
              accountEvents.updateNotificationCounter(
                siteUrl,
                chatNotificationCounter.id,
                (current) => current + delta,
              ),
          onSiteUnreachable: accountEvents.markSiteUnreachable,
        );
        final conversations = ChatControllerConversationCapability(controller);
        final searchController = ChatSearchController(
          api: chatApi,
          requests: requests,
          store: store,
          reporter: bindings.require(pluginDiagnosticsReporterPort),
        );
        final shell = ChatShellService(
          chat: controller,
          host: bindings.require(corePluginNavigationPort),
          composerHost: composerHost,
          store: store,
          postFlagCatalog: bindings.require(corePluginPostFlagCatalogPort),
        );
        return PluginSessionContribution(
          lifecycle: _ChatSessionLifecycle(
            controller: controller,
            searchController: searchController,
            shell: shell,
          ),
          services: [
            PluginService<Object>(chatConversationService, conversations),
            PluginService<Object>(chatControllerService, controller),
            PluginService<Object>(
              chatSearchControllerService,
              searchController,
            ),
            PluginService<Object>(chatShellService, shell),
            PluginService<Object>(
              chatBookmarkHostService,
              bindings
                  .require(corePluginBookmarkPort)
                  .forTarget(chatMessageBookmarkTarget),
            ),
            PluginService<Object>(chatComposerHostService, composerHost),
            PluginService<Object>(
              chatEmojiHostService,
              bindings.require(corePluginEmojiPort),
            ),
            PluginService<Object>(
              chatNotificationHostService,
              bindings.require(corePluginNotificationFeedPort),
            ),
            if (gifs case final GifPickerSession value)
              PluginService<Object>(chatGifsService, value),
          ],
          capabilities: [shell],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginRequestPort,
        corePluginSiteStatePort,
        corePluginStaticContributionsPort,
        corePluginAccountEventsPort,
        corePluginNavigationPort,
        corePluginBookmarkPort,
        corePluginComposerPort,
        corePluginEmojiPort,
        corePluginNotificationFeedPort,
        pluginDiagnosticsReporterPort,
        corePluginPostFlagCatalogPort,
      ],
    );
  }
}

final class _ChatSessionLifecycle extends PluginSessionLifecycle {
  _ChatSessionLifecycle({
    required this.controller,
    required this.searchController,
    required this.shell,
  });

  final ChatController controller;
  final ChatSearchController searchController;
  final ChatShellService shell;

  @override
  void forget(String siteUrl) {
    controller.forget(siteUrl);
    searchController.forget(siteUrl);
  }

  @override
  void close() {
    shell.dispose();
    controller.dispose();
    searchController.dispose();
  }
}
