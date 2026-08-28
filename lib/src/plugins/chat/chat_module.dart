import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../gifs/gifs_contract.dart';
import '../reactions/reactions_contract.dart';
import 'chat_api.dart';
import 'chat_api_client.dart';
import 'chat_bookmark.dart';
import 'chat_controller.dart';
import 'chat_notification_counter.dart';
import 'chat_plugin.dart';
import 'chat_preview.dart';
import 'chat_search_controller.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

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
    registrar.addStaticContributionPoint(chatPreviewContributions);
    registrar.addCapability(const ChatPlugin());
    registrar.addRouteNamespace('chat');
    registrar.addSession(
      (bindings, dependencies) {
        final transport = bindings.require(corePluginTransportPort);
        final credentials = bindings.require(corePluginCredentialsPort);
        final store = bindings.require(corePluginStorePort);
        final lifecycle = bindings.require(corePluginSiteLifecyclePort);
        final siteState = bindings.require(corePluginSiteStatePort);
        final accountEvents = bindings.require(corePluginAccountEventsPort);
        final composerHost = bindings.require(corePluginComposerPort);
        final chatApi = transport is ChatApi
            ? transport as ChatApi
            : ChatApiClient(transport);
        final gifsApi = dependencies.maybe(gifsApiService);
        final controller = ChatController(
          api: chatApi,
          credentials: credentials,
          store: store,
          lifecycle: lifecycle,
          currentUserFor: siteState.currentUserFor,
          siteConfigFor: siteState.siteConfigFor,
          previewEngine: ChatPreviewEngine(
            plugins: bindings
                .require(corePluginStaticContributionsPort)
                .contributions(chatPreviewContributions),
          ),
          onChatNotificationsDelta: (siteUrl, delta) =>
              accountEvents.updateNotificationCounter(
                siteUrl,
                chatNotificationCounter.id,
                (current) => current + delta,
              ),
          onSiteUnreachable: accountEvents.markSiteUnreachable,
        );
        final searchController = ChatSearchController(
          api: chatApi,
          credentials: credentials,
          store: store,
          lifecycle: lifecycle,
        );
        final shell = ChatShellService(
          chat: controller,
          host: bindings.require(corePluginNavigationPort),
          composerHost: composerHost,
          store: store,
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
            PluginService<Object>(chatComposerHostService, composerHost),
            PluginService<Object>(
              chatEmojiHostService,
              bindings.require(corePluginEmojiPort),
            ),
            PluginService<Object>(
              chatNotificationHostService,
              bindings.require(corePluginNotificationFeedPort),
            ),
            if (gifsApi case final GifsApi value)
              PluginService<Object>(chatGifsApiService, value),
          ],
          capabilities: [shell],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginCredentialsPort,
        corePluginStorePort,
        corePluginSiteLifecyclePort,
        corePluginSiteStatePort,
        corePluginStaticContributionsPort,
        corePluginAccountEventsPort,
        corePluginNavigationPort,
        corePluginBookmarkPort,
        corePluginComposerPort,
        corePluginEmojiPort,
        corePluginNotificationFeedPort,
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
