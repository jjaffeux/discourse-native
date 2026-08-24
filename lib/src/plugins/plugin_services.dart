import 'assign/assignment_controller.dart';
import 'chat/chat_controller.dart';
import 'plugin_manifest.dart';
import 'plugin_runtime.dart';
import 'reactions/reactions_controller.dart';
import 'resenha/resenha_controller.dart';

const reactionsControllerService = PluginServiceKey<ReactionsController>(
  owner: PluginId('discourse-reactions'),
  name: 'controller',
);
const assignmentControllerService = PluginServiceKey<AssignmentController>(
  owner: PluginId('discourse-assign'),
  name: 'controller',
);
const chatControllerService = PluginServiceKey<ChatController>(
  owner: PluginId('chat'),
  name: 'controller',
);
const resenhaControllerService = PluginServiceKey<ResenhaController>(
  owner: PluginId('resenha'),
  name: 'controller',
);
