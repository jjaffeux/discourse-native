import '../../plugin_api/plugin_manifest.dart';
import 'discourse_lazy_videos_plugin.dart';

const discourseLazyVideosPluginId = PluginId('discourse-lazy-videos');
const discourseLazyVideosModule = DiscourseLazyVideosModule();

/// Complete production registration for the bundled lazy-video feature.
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
