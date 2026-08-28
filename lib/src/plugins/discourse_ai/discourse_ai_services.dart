import '../../plugin_api/plugin_manifest.dart';
import 'ai_summary_controller.dart';

const discourseAiPluginId = PluginId('discourse-ai');

const aiSummaryControllerService = PluginServiceKey<AiSummaryController>(
  owner: discourseAiPluginId,
  name: 'controller',
);
