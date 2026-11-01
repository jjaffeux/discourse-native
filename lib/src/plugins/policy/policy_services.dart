import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'policy_controller.dart';

const policyPluginId = PluginId('discourse-policy');
const policyControllerService = PluginServiceKey<PolicyController>(
  owner: policyPluginId,
  name: 'controller',
);
