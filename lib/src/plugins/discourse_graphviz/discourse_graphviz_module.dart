import 'package:discourse_native/discourse_plugin_contracts.dart';

import 'discourse_graphviz_plugin.dart';

const discourseGraphvizModule = DiscourseGraphvizModule();

final class DiscourseGraphvizModule implements PluginModule {
  const DiscourseGraphvizModule();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('discourse-graphviz'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const DiscourseGraphvizPlugin());
  }
}
