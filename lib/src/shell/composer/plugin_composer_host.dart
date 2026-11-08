import 'package:discourse_plugin_api/discourse_plugin_api.dart';

import '../../plugin_api/core_plugin_host.dart';
import 'controller.dart';

typedef PluginComposerBuilder =
    ComposerController? Function(ComposerTargetRequest request);

/// This facade deliberately exposes no navigation, topic mutation, or shell
/// state. [siteConfigListenableFor] exposes only the configuration for the
/// composer's own site rather than a broad shell change signal. The core port
/// scopes [buildComposer] to target kinds owned by the consuming plugin.
final class PluginComposerHost {
  const PluginComposerHost({
    required this.buildComposer,
    required this.openNewTopic,
    required this.isActive,
    required this.siteConfigFor,
    required this.siteConfigListenableFor,
  });

  final PluginComposerBuilder buildComposer;
  final PluginNewTopicComposerOpener openNewTopic;
  final bool Function(ComposerController composer) isActive;
  final PluginSiteConfigReader siteConfigFor;
  final PluginSiteConfigListenableReader siteConfigListenableFor;
}

const corePluginComposerPort = PluginHostPortKey<PluginComposerHost>(
  owner: PluginId('core'),
  name: 'composer',
);
