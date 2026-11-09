import 'package:discourse_native/discourse_plugin_contracts.dart';
import '../chat/chat_preview_contract.dart';
import 'discourse_math_plugin.dart';
import 'math_services.dart';

const discourseMathId = PluginId('discourse-math');
const discourseMathModule = DiscourseMathModule();

final class DiscourseMathModule implements PluginModule {
  const DiscourseMathModule();
  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
    id: discourseMathId,
    syntaxIds: {'discourse-math/expression'},
    staticContributionTargets: [
      PluginStaticContributionTarget(PluginId('chat'), optional: true),
    ],
  );
  @override
  void register(PluginRegistrar registrar) {
    const plugin = DiscourseMathPlugin();
    registrar.addCapability(plugin);
    registrar.addSyntaxId('discourse-math/expression');
    registrar.addStaticContribution(
      chatPreviewContributions,
      name: 'math',
      value: plugin,
    );
    registrar.addSession(
      (bindings, _) => PluginSessionContribution(
        lifecycle: _MathLifecycle(),
        services: [
          PluginService<Object>(
            mathServiceKey,
            MathService(bindings.require(corePluginSiteStatePort)),
          ),
        ],
      ),
      requires: const [corePluginSiteStatePort],
    );
  }
}

final class _MathLifecycle extends PluginSessionLifecycle {}
