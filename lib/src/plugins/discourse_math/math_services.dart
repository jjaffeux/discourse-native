import 'package:discourse_native/discourse_plugin_sdk.dart';

const mathServiceKey = PluginServiceKey<MathService>(
  owner: PluginId('discourse-math'),
  name: 'rendering',
);

final class MathService {
  const MathService(this.sites);
  final PluginSiteStateHost sites;
}
