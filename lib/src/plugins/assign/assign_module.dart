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
    registrar.addSession((bindings, _) {
      final host = bindings.require(corePluginHostPort);
      final controller = AssignmentController(
        api: AssignApi(host.api),
        credentials: host.credentials,
        lifecycle: host.siteLifecycle,
        canAssign: (siteUrl, target) {
          final reference = switch (target.type) {
            AssignmentTargetType.topic => PluginTarget.topic(target.id),
            AssignmentTargetType.post => PluginTarget.post(
              target.id,
              topicId: target.topicId,
            ),
          };
          final snapshot = host.dataForTarget(siteUrl, reference);
          if (!snapshot.valid) return false;
          final recordPermission = snapshot.data
              .get(assignmentsDataKey)
              ?.canAssign;
          return host.canPerform(siteUrl, 'assign', recordPermission);
        },
        reloadTopic: host.reloadTopic,
        invalidateLegacyFallback: (siteUrl) =>
            host.invalidateFallback(siteUrl, 'assign'),
      );
      return PluginSessionContribution(
        lifecycle: _AssignSessionLifecycle(controller),
        services: [
          PluginService<Object>(assignmentControllerService, controller),
        ],
      );
    }, requires: const [corePluginHostPort]);
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
