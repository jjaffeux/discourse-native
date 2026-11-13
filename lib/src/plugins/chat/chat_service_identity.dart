import 'package:discourse_native/discourse_plugin_contracts.dart';

import 'chat_conversation_contract.dart';

const chatPluginId = PluginId('chat');

const chatConversationService = PluginServiceKey<ChatConversationCapability>(
  owner: chatPluginId,
  name: 'conversation',
);
