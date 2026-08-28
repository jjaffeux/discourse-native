import '../../diagnostics/diagnostics_controller.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import 'assign_api.dart';
import 'assign_plugin.dart';
import 'assign_services.dart';
import 'assignment.dart';
import 'assignment_controller.dart';

const assignModule = AssignModule();

final class AssignModule implements PluginModule {
  const AssignModule();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(id: assignPluginId);

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const AssignPlugin());
    registrar.addSession(
      (bindings, _) {
        final targetHost = bindings.require(corePluginTargetPort);
        final topicRefresh = bindings.require(corePluginTopicRefreshPort);
        final siteState = bindings.require(corePluginSiteStatePort);
        final controller = AssignmentController(
          api: AssignApi(bindings.require(corePluginTransportPort)),
          credentials: bindings.require(corePluginCredentialsPort),
          lifecycle: bindings.require(corePluginSiteLifecyclePort),
          permissionSnapshot: (siteUrl, target) {
            final reference = switch (target.type) {
              AssignmentTargetType.topic => PluginTarget.topic(target.id),
              AssignmentTargetType.post => PluginTarget.post(
                target.id,
                topicId: target.topicId,
              ),
            };
            final snapshot = targetHost.dataForTarget(siteUrl, reference);
            return (
              valid: snapshot.valid,
              recordPermission: snapshot.data
                  .get(assignmentsDataKey)
                  ?.canAssign,
              freshAccountCanAssign:
                  targetHost.freshCurrentUserFor(siteUrl)?.canAssign == true,
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
        return PluginSessionContribution(
          lifecycle: _AssignSessionLifecycle(controller),
          services: [
            PluginService<Object>(assignmentControllerService, controller),
          ],
          capabilities: [controller],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginCredentialsPort,
        corePluginSiteLifecyclePort,
        corePluginTargetPort,
        corePluginTopicRefreshPort,
        corePluginSiteStatePort,
        pluginDiagnosticsReporterPort,
      ],
    );
  }
}

final class _AssignSessionLifecycle extends PluginSessionLifecycle {
  _AssignSessionLifecycle(this.controller);

  final AssignmentController controller;

  @override
  void forget(String siteUrl) => controller.forget(siteUrl);

  @override
  void close() => controller.dispose();
}
