import '../../data/store.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../gifs/gifs_contract.dart';
import '../reactions/reactions_contract.dart';
import 'chat_api.dart';
import 'chat_api_client.dart';
import 'chat_bookmark.dart';
import 'chat_controller.dart';
import 'chat_plugin.dart';
import 'chat_preview.dart';
import 'chat_search_controller.dart';
import 'chat_services.dart';
import 'chat_shell_extension.dart';

const chatModule = ChatModule();

/// Complete production registration for the bundled Chat feature.
final class ChatModule implements PluginModule {
  const ChatModule();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
    id: chatPluginId,
    dependencies: [
      PluginDependency(reactionsPluginId),
      PluginDependency(gifsPluginId, optional: true),
    ],
    routeNamespaces: {'chat'},
  );

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const ChatPlugin());
    registrar.addRouteNamespace('chat');
    registrar.addSession(
      (bindings, dependencies) {
        final transport = bindings.require(corePluginTransportPort);
        final requests = bindings.require(corePluginRequestPort);
        final store = Store();
        final siteState = bindings.require(corePluginSiteStatePort);
        final accountEvents = bindings.require(corePluginAccountEventsPort);
        final previewHost = bindings.require(corePluginPreviewPort);
        final chatApi = transport is ChatApi
            ? transport as ChatApi
            : ChatApiClient(transport);
        final gifs = dependencies.maybe(gifsSessionService);
        final controller = ChatController(
          api: chatApi,
          requests: requests,
          store: store,
          currentUserFor: siteState.currentUserFor,
          siteConfigFor: siteState.siteConfigFor,
          previewEngine: ChatPreviewEngine(plugins: previewHost.plugins),
          onChatNotificationsDelta: (siteUrl, delta) =>
              accountEvents.updateTotals(
                siteUrl,
                (held) => held.withChatNotificationsDelta(delta),
              ),
          onSiteUnreachable: accountEvents.markSiteUnreachable,
        );
        final searchController = ChatSearchController(
          api: chatApi,
          requests: requests,
          store: store,
        );
        final shell = ChatShellService(
          chat: controller,
          host: bindings.require(corePluginNavigationPort),
          postFlagCatalog: bindings.require(corePluginPostFlagCatalogPort),
        );
        return PluginSessionContribution(
          lifecycle: _ChatSessionLifecycle(
            controller: controller,
            searchController: searchController,
            shell: shell,
          ),
          services: [
            PluginService<Object>(chatApiService, chatApi),
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
            PluginService<Object>(
              chatComposerHostService,
              bindings.require(corePluginComposerPort),
            ),
            PluginService<Object>(
              chatEmojiHostService,
              bindings.require(corePluginEmojiPort),
            ),
            PluginService<Object>(
              chatNotificationHostService,
              bindings.require(corePluginNotificationFeedPort),
            ),
            PluginService<Object>(chatPreviewHostService, previewHost),
            if (gifs case final GifsSessionService value)
              PluginService<Object>(chatGifsService, value),
          ],
          capabilities: [shell],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginRequestPort,
        corePluginSiteStatePort,
        corePluginPreviewPort,
        corePluginAccountEventsPort,
        corePluginNavigationPort,
        corePluginBookmarkPort,
        corePluginComposerPort,
        corePluginEmojiPort,
        corePluginNotificationFeedPort,
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
