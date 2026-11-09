import 'package:discourse_native/discourse_plugin_contracts.dart';

import 'policies_api.dart';
import 'policy_api.dart';
import 'policy_composer.dart';
import 'policy_controller.dart';
import 'policy_cooking.dart';
import 'policy_groups.dart';
import 'policy_plugin.dart';
import 'policy_services.dart';

const policyModule = PolicyModule();

class PolicyModule implements PluginModule {
  const PolicyModule({this.apiFactory});
  final PoliciesApi Function(PluginApiTransport)? apiFactory;
  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
    id: policyPluginId,
    syntaxIds: {'discourse-policy/policy'},
  );
  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const PolicyPlugin());
    registrar.addCapability(const PolicyCookingPlugin());
    registrar.addSyntaxId(policyComposerKind.id);
    registrar.addSession(
      (bindings, _) {
        final transport = bindings.require(corePluginTransportPort);
        final requests = bindings.require(corePluginRequestPort);
        final controller = PolicyController(
          api: apiFactory?.call(transport) ?? PolicyApi(transport),
          requests: requests,
          posts: bindings.require(corePluginPostPort),
          siteState: bindings.require(corePluginSiteStatePort),
          freshAccount: bindings.require(corePluginFreshAccountPort),
          accounts: bindings.require(corePluginAccountConnectionPort),
        );
        return PluginSessionContribution(
          lifecycle: _PolicyLifecycle(controller),
          services: [
            PluginService<Object>(policyControllerService, controller),
            PluginService<Object>(
              policyGroupsService,
              PolicyGroups(transport, requests),
            ),
            PluginService<Object>(
              policyEditorService,
              bindings.require(corePluginPostEditorPort),
            ),
          ],
          capabilities: [controller],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginRequestPort,
        corePluginPostPort,
        corePluginSiteStatePort,
        corePluginFreshAccountPort,
        corePluginAccountConnectionPort,
        corePluginPostEditorPort,
      ],
    );
  }
}

final class _PolicyLifecycle extends PluginSessionLifecycle {
  _PolicyLifecycle(this.controller);
  final PolicyController controller;
  @override
  void setForeground(bool foreground) => controller.setForeground(foreground);
  @override
  void forget(String siteUrl) => controller.forget(siteUrl);
  @override
  void close() => controller.dispose();
}
