import 'assign/assignment_controller.dart';
import 'chat/chat_controller.dart';
import 'chat/chat_search_controller.dart';
import 'discourse_ai/ai_summary_controller.dart';
import 'gifs/gifs_api.dart';
import 'plugin_manifest.dart';
import 'plugin_runtime.dart';
import 'reactions/reactions_controller.dart';
import 'resenha/resenha_controller.dart';

const reactionsControllerService = PluginServiceKey<ReactionsController>(
  owner: PluginId('discourse-reactions'),
  name: 'controller',
);
const gifsApiService = PluginServiceKey<GifsApi>(
  owner: PluginId('gifs'),
  name: 'api',
);
const assignmentControllerService = PluginServiceKey<AssignmentController>(
  owner: PluginId('discourse-assign'),
  name: 'controller',
);
const chatControllerService = PluginServiceKey<ChatController>(
  owner: PluginId('chat'),
  name: 'controller',
);
const chatSearchControllerService = PluginServiceKey<ChatSearchController>(
  owner: PluginId('chat'),
  name: 'search-controller',
);
const aiSummaryControllerService = PluginServiceKey<AiSummaryController>(
  owner: PluginId('discourse-ai'),
  name: 'controller',
);
const resenhaControllerService = PluginServiceKey<ResenhaController>(
  owner: PluginId('resenha'),
  name: 'controller',
);
