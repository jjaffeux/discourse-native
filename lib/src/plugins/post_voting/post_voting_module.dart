import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'post_voting_api.dart';
import 'post_voting_composer.dart';
import 'post_voting_data.dart';
import 'post_voting_plugin.dart';
import 'post_voting_services.dart';

const postVotingModule = PostVotingModule();

final class PostVotingModule implements PluginModule {
  const PostVotingModule();
  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: postVotingPluginId);
  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const PostVotingPlugin());
    registrar.addCapability(const PostVotingPostPlugin());
    registrar.addCapability(const PostVotingCategoryPlugin());
    registrar.addCapability(const PostVotingUserPlugin());
    registrar.addCapability(const PostVotingComposerPlugin());
    registrar.addSession(
      (bindings, _) {
        final service = PostVotingServices(
          api: PostVotingApi(
            bindings.require(corePluginTransportPort),
            bindings.require(corePluginModelCodecPort),
          ),
          requests: bindings.require(corePluginRequestPort),
          posts: bindings.require(corePluginPostPort),
          siteState: bindings.require(corePluginSiteStatePort),
          readers: bindings.require(corePluginTopicReaderPort),
          records: bindings.require(corePluginTopicRecordsPort),
          topics: bindings.require(corePluginTopicRefreshPort),
          navigation: bindings.require(corePluginNavigationPort),
          accounts: bindings.require(corePluginAccountConnectionPort),
          flagCatalog: bindings.require(corePluginPostFlagCatalogPort),
        );
        return PluginSessionContribution(
          lifecycle: _Lifecycle(service),
          services: [PluginService<Object>(postVotingServicesKey, service)],
          capabilities: [service],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginModelCodecPort,
        corePluginRequestPort,
        corePluginPostPort,
        corePluginSiteStatePort,
        corePluginTopicReaderPort,
        corePluginTopicRecordsPort,
        corePluginTopicRefreshPort,
        corePluginNavigationPort,
        corePluginAccountConnectionPort,
        corePluginPostFlagCatalogPort,
      ],
    );
  }
}

final class _Lifecycle extends PluginSessionLifecycle {
  _Lifecycle(this.service);
  final PostVotingServices service;
  @override
  void forget(String siteUrl) => service.forget(siteUrl);
  @override
  void close() => service.dispose();
}
