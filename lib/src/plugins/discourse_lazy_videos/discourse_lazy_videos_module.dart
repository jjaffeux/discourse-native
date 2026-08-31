import '../../plugin_api/plugin_manifest.dart';
import 'discourse_lazy_videos_plugin.dart';

const discourseLazyVideosPluginId = PluginId('discourse-lazy-videos');
const discourseLazyVideosModule = DiscourseLazyVideosModule();

final class DiscourseLazyVideosModule implements PluginModule {
  const DiscourseLazyVideosModule();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: discourseLazyVideosPluginId);

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const DiscourseLazyVideosPlugin());
  }
}
