import 'package:discourse_native/discourse_plugin_sdk.dart';

const chatMessageComposerTarget = ComposerTargetKind(
  owner: PluginId('chat'),
  name: 'message',
);
const chatMessageUploadType = ComposerUploadType('chat-composer');
const chatComposerChannelId = 'channelId';
const chatComposerThreadId = 'threadId';
