import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'voice_call_port.dart';
import 'voice_controller.dart';

const voicePluginId = PluginId('voice');

const voiceControllerService = PluginServiceKey<VoiceController>(
  owner: voicePluginId,
  name: 'controller',
);

const voiceCallPortService = PluginServiceKey<VoiceCallPort>(
  owner: voicePluginId,
  name: 'call-port',
);
