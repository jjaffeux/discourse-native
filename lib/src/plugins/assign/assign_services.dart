import '../../plugin_api/plugin_manifest.dart';
import 'assignment_controller.dart';

const assignPluginId = PluginId('discourse-assign');

const assignmentControllerService = PluginServiceKey<AssignmentController>(
  owner: assignPluginId,
  name: 'controller',
);
