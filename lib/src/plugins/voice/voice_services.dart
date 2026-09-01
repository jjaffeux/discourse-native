import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'voice_controller.dart';

const voicePluginId = PluginId('voice');

const voiceControllerService = PluginServiceKey<VoiceController>(
  owner: voicePluginId,
  name: 'controller',
);
