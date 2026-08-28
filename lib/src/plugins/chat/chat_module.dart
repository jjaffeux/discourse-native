import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../gifs/gifs_api.dart';
import '../gifs/gifs_services.dart';
import '../reactions/reactions_services.dart';
import 'chat_api.dart';
import 'chat_api_client.dart';
import 'chat_controller.dart';
import 'chat_plugin.dart';
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
    registrar.addSession((bindings, dependencies) {
      final host = bindings.require(corePluginHostPort);
      final chatApi = host.api is ChatApi
          ? host.api as ChatApi
          : ChatApiClient(host.api);
      final gifsApi = dependencies.maybe(gifsApiService);
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
        lifecycle: _ChatSessionLifecycle(
          controller: controller,
          searchController: searchController,
          shell: shell,
        ),
        services: [
          PluginService<Object>(chatApiService, chatApi),
          PluginService<Object>(chatControllerService, controller),
          PluginService<Object>(chatSearchControllerService, searchController),
          PluginService<Object>(chatShellService, shell),
          if (gifsApi case final GifsApi value)
            PluginService<Object>(chatGifsApiService, value),
        ],
        capabilities: [shell],
      );
    }, requires: const [corePluginHostPort]);
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
