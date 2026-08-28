import '../../plugin_api/plugin_manifest.dart';
import '../chat/chat_preview_contract.dart';
import 'local_dates_plugin.dart';

const localDatesPluginId = PluginId('discourse-local-dates');
const localDatesModule = LocalDatesModule();

final class LocalDatesModule implements PluginModule {
  const LocalDatesModule();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
    id: localDatesPluginId,
    staticContributionTargets: [
      PluginStaticContributionTarget(PluginId('chat'), optional: true),
    ],
    syntaxIds: {'discourse-local-dates/local-date'},
  );

  @override
  void register(PluginRegistrar registrar) {
    const plugin = LocalDatesPlugin();
    registrar.addCapability(plugin);
    registrar.addStaticContribution(
      chatPreviewContributions,
      name: 'local-date',
      value: plugin,
    );
    registrar.addSyntaxId(plugin.composerSyntaxKind.id);
  }
}
