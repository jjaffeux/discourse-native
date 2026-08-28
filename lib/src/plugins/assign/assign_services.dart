import '../../plugin_api/plugin_manifest.dart';
import 'assign_shell_service.dart';
import 'assigned_group_controller.dart';
import 'assignment_controller.dart';

const assignPluginId = PluginId('discourse-assign');

const assignmentControllerService = PluginServiceKey<AssignmentController>(
  owner: assignPluginId,
  name: 'controller',
);

const assignedGroupControllerService =
    PluginServiceKey<AssignedGroupController>(
      owner: assignPluginId,
      name: 'group-controller',
    );

const assignGroupNavigationService = PluginServiceKey<AssignShellService>(
  owner: assignPluginId,
  name: 'group-navigation',
);
