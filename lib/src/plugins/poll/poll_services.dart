import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'poll_controller.dart';

const pollPluginId = PluginId('poll');

const pollControllerService = PluginServiceKey<PollController>(
  owner: pollPluginId,
  name: 'controller',
);
