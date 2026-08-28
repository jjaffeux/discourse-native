import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import 'poll_api.dart';
import 'poll_controller.dart';
import 'poll_plugin.dart';
import 'poll_services.dart';
import 'polls_api.dart';

const pollModule = PollModule();

final class PollModule implements PluginModule {
  const PollModule();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: pollPluginId, syntaxIds: {'poll'});

  @override
  void register(PluginRegistrar registrar) {
    const plugin = PollPlugin();
    registrar.addCapability(plugin);
    registrar.addSyntaxId(plugin.syntaxId);
    registrar.addSession(
      (bindings, _) {
        final transport = bindings.require(corePluginTransportPort);
        final PollsApi pollApi = transport is PollsApi
            ? transport as PollsApi
            : PollApi(transport);
        final controller = PollController(
          api: pollApi,
          requests: bindings.require(corePluginRequestPort),
          posts: bindings.require(corePluginPostPort),
          siteState: bindings.require(corePluginSiteStatePort),
          freshAccount: bindings.require(corePluginFreshAccountPort),
          accounts: bindings.require(corePluginAccountConnectionPort),
          composerHost: bindings.require(corePluginComposerPort),
        );
        return PluginSessionContribution(
          lifecycle: _PollSessionLifecycle(controller),
          services: [PluginService<Object>(pollControllerService, controller)],
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
        corePluginComposerPort,
      ],
    );
  }
}

final class _PollSessionLifecycle extends PluginSessionLifecycle {
  _PollSessionLifecycle(this.controller);

  final PollController controller;

  @override
  void forget(String siteUrl) => controller.forget(siteUrl);

  @override
  void close() => controller.dispose();
}
