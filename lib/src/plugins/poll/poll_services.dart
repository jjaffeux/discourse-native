import '../../plugin_api/plugin_manifest.dart';
import 'poll_controller.dart';

const pollPluginId = PluginId('poll');

const pollControllerService = PluginServiceKey<PollController>(
  owner: pollPluginId,
  name: 'controller',
);
