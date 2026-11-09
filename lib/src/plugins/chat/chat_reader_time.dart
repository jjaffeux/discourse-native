import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/widgets.dart';

import 'chat_services.dart';
import 'chat_time.dart';

ChatTime chatTimeFor(BuildContext context, String? siteUrl) {
  final chat = PluginUiScope.maybe(context, chatControllerService);
  return chat != null && siteUrl != null
      ? chat.timeFor(siteUrl)
      : ChatTime.forReader();
}
