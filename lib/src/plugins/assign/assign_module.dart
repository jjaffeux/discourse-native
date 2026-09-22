import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'assign_api.dart';
import 'assign_plugin.dart';
import 'assign_preferences.dart';
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
        final preferences = AssignPreferences(
          diagnostics: bindings.require(pluginDiagnosticsReporterPort),
        );
        unawaited(preferences.load());
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
            var snapshot = targetHost.recordFor(
              siteUrl,
              reference,
              assignmentsDataKey,
            );
            if (!snapshot.valid && target.type == AssignmentTargetType.post) {
              final topicSnapshot = targetHost.recordFor(
                siteUrl,
                PluginTarget.topic(target.topicId),
                assignmentsDataKey,
              );
              final knownAssignment =
                  topicSnapshot.value?.postAssignments[target.id];
              final postNumber = knownAssignment?.postNumber;
              // Topic-level Assign controls upstream manage every assigned
              // post using the topic permission. Use that same category-scoped
              // permission only for a post the topic payload identifies, while
              // still preferring an authoritative loaded-post denial above.
              if (topicSnapshot.valid && postNumber != null && postNumber > 1) {
                snapshot = topicSnapshot;
              }
            }
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
          lifecycle: _AssignSessionLifecycle(
            controller,
            assignedGroups,
            preferences,
          ),
          services: [
            PluginService<Object>(
              assignTopicListPreferencesService,
              preferences,
            ),
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
  _AssignSessionLifecycle(
    this.controller,
    this.assignedGroups,
    this.preferences,
  );

  final AssignPreferences preferences;

  final AssignmentController controller;
  final AssignedGroupController assignedGroups;

  @override
  void forget(String siteUrl) {
    controller.forget(siteUrl);
    assignedGroups.forget(siteUrl);
  }

  @override
  void close() {
    preferences.dispose();
    controller.dispose();
    assignedGroups.dispose();
  }
}
