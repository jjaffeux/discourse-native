import 'package:discourse_native/discourse_plugin_contracts.dart';
import '../gifs/gifs_contract.dart';
import 'chat_controller.dart';
import 'chat_search_controller.dart';
import 'chat_service_identity.dart';

export 'chat_service_identity.dart';

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
