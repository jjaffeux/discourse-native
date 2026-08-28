import '../../plugin_api/bookmark_host.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/notification_feed_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../gifs/gifs_contract.dart';
import 'chat_api.dart';
import 'chat_controller.dart';
import 'chat_search_controller.dart';

const chatPluginId = PluginId('chat');

const chatApiService = PluginServiceKey<ChatApi>(
  owner: chatPluginId,
  name: 'api',
);

const chatControllerService = PluginServiceKey<ChatController>(
  owner: chatPluginId,
  name: 'controller',
);

const chatSearchControllerService = PluginServiceKey<ChatSearchController>(
  owner: chatPluginId,
  name: 'search-controller',
);

const chatBookmarkHostService = PluginServiceKey<PluginBookmarkHost>(
  owner: chatPluginId,
  name: 'bookmark-host',
);

const chatComposerHostService = PluginServiceKey<PluginComposerHost>(
  owner: chatPluginId,
  name: 'composer-host',
);

const chatEmojiHostService = PluginServiceKey<PluginEmojiHost>(
  owner: chatPluginId,
  name: 'emoji-host',
);

const chatNotificationHostService =
    PluginServiceKey<PluginNotificationFeedHost>(
      owner: chatPluginId,
      name: 'notification-feed-host',
    );

/// The optional GIF dependency as exposed inside Chat's own service scope.
///
/// Chat widgets never reach into another module's global services. The Chat
/// module resolves the declared optional dependency while its session is
/// created and republishes it under this Chat-owned key when it is available.
const chatGifsApiService = PluginServiceKey<GifsApi>(
  owner: chatPluginId,
  name: 'gifs-api',
);
