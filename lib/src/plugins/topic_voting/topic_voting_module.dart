import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'topic_voting_global_search.dart';

const topicVotingModule = _Module();

final class _Module implements PluginModule {
  const _Module();
  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('discourse-topic-voting'));
  @override
  void register(PluginRegistrar registrar) =>
      registrar.addCapability(const _Plugin());
}

final class _Plugin implements SitePlugin, GlobalSearchPlugin {
  const _Plugin();
  @override
  String get name => 'discourse-topic-voting';
  @override
  List<GlobalSearchContribution> get searchContributions => const [
    TopicVotingGlobalSearch(),
  ];
}
