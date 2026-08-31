import '../../plugin_api/bookmark_host.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/notification_feed_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../gifs/gifs_contract.dart';
import 'chat_controller.dart';
import 'chat_conversation_contract.dart';
import 'chat_search_controller.dart';

const chatPluginId = PluginId('chat');

const chatConversationService = PluginServiceKey<ChatConversationCapability>(
  owner: chatPluginId,
  name: 'conversation',
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

const chatGifsService = PluginServiceKey<GifPickerSession>(
  owner: chatPluginId,
  name: 'gifs',
);
