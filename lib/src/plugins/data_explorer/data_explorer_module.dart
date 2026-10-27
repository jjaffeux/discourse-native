import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'data_explorer_reports.dart';

const dataExplorerModule = DataExplorerModule();

final class DataExplorerModule implements PluginModule {
  const DataExplorerModule();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('discourse-data-explorer'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const DataExplorerReports());
  }
}
