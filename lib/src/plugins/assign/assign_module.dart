import '../../diagnostics/diagnostics_controller.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import 'assign_api.dart';
import 'assign_plugin.dart';
import 'assign_services.dart';
import 'assign_shell_service.dart';
import 'assigned_group_api.dart';
import 'assigned_group_controller.dart';
import 'assignment.dart';
import 'assignment_controller.dart';

const assignModule = AssignModule();

final class AssignModule implements PluginModule {
  const AssignModule();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: assignPluginId, routeNamespaces: {'assign'});

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const AssignPlugin());
    registrar.addRouteNamespace('assign');
    registrar.addSession(
      (bindings, _) {
        final targetHost = bindings.require(corePluginTargetPort);
        final freshAccount = bindings.require(corePluginFreshAccountPort);
        final topicRefresh = bindings.require(corePluginTopicRefreshPort);
        final siteState = bindings.require(corePluginSiteStatePort);
        final controller = AssignmentController(
          api: AssignApi(bindings.require(corePluginTransportPort)),
          requests: bindings.require(corePluginRequestPort),
          permissionSnapshot: (siteUrl, target) {
            final reference = switch (target.type) {
              AssignmentTargetType.topic => PluginTarget.topic(target.id),
              AssignmentTargetType.post => PluginTarget.post(
                target.id,
                topicId: target.topicId,
              ),
            };
            final snapshot = targetHost.recordFor(
              siteUrl,
              reference,
              assignmentsDataKey,
            );
            return (
              valid: snapshot.valid,
              recordPermission: snapshot.value?.canAssign,
              freshAccountCanAssign:
                  freshAccount
                      .recordFor(siteUrl, assignCurrentUserDataKey)
                      ?.canAssign ==
                  true,
            );
          },
          statusOptionsReader: (siteUrl) {
            final config = siteState.siteConfigFor(siteUrl);
            return (
              enabled: config.assignStatusesEnabled,
              values: config.assignStatuses,
            );
          },
          reloadTopic: topicRefresh.reloadTopic,
          diagnostics: bindings.require(pluginDiagnosticsReporterPort),
        );
        final shell = AssignShellService(
          host: bindings.require(corePluginRouteNavigationPort),
          canOpenGroupAssignments: (siteUrl) =>
              freshAccount
                  .recordFor(siteUrl, assignCurrentUserDataKey)
                  ?.canAssignGlobally ==
              true,
        );
        final assignedGroups = AssignedGroupController(
          api: AssignedGroupApiClient(
            bindings.require(corePluginTransportPort),
            bindings.require(corePluginModelCodecPort),
          ),
          requests: bindings.require(corePluginRequestPort),
          diagnostics: bindings.require(pluginDiagnosticsReporterPort),
        );
        return PluginSessionContribution(
          lifecycle: _AssignSessionLifecycle(controller, assignedGroups),
          services: [
            PluginService<Object>(assignmentControllerService, controller),
            PluginService<Object>(
              assignedGroupControllerService,
              assignedGroups,
            ),
            PluginService<Object>(assignGroupNavigationService, shell),
            PluginService<Object>(
              assignNotificationHostService,
              bindings.require(corePluginNotificationFeedPort),
            ),
          ],
          capabilities: [controller, shell],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginModelCodecPort,
        corePluginRequestPort,
        corePluginTargetPort,
        corePluginFreshAccountPort,
        corePluginTopicRefreshPort,
        corePluginSiteStatePort,
        corePluginRouteNavigationPort,
        corePluginNotificationFeedPort,
        pluginDiagnosticsReporterPort,
      ],
    );
  }
}

final class _AssignSessionLifecycle extends PluginSessionLifecycle {
  _AssignSessionLifecycle(this.controller, this.assignedGroups);

  final AssignmentController controller;
  final AssignedGroupController assignedGroups;

  @override
  void forget(String siteUrl) {
    controller.forget(siteUrl);
    assignedGroups.forget(siteUrl);
  }

  @override
  void close() {
    controller.dispose();
    assignedGroups.dispose();
  }
}
