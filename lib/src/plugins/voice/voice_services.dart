import 'package:discourse_native/discourse_plugin_contracts.dart';

import 'voice_call_port.dart';
import 'voice_controller.dart';

const voicePluginId = PluginId('voice');

String voiceRoomRouteId(int roomId) => 'voice-room-$roomId';

int? voiceRoomIdIn(String routeId) {
  const prefix = 'voice-room-';
  return routeId.startsWith(prefix)
      ? int.tryParse(routeId.substring(prefix.length))
      : null;
}

const voiceEmojiHostService = PluginServiceKey<PluginEmojiHost>(
  owner: voicePluginId,
  name: 'emoji',
);

const voiceControllerService = PluginServiceKey<VoiceController>(
  owner: voicePluginId,
  name: 'controller',
);

const voiceCallPortService = PluginServiceKey<VoiceCallPort>(
  owner: voicePluginId,
  name: 'call-port',
);
