import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../plugin_api/plugin_icon_catalog.dart';
import '../../theme/d_icon.dart';

abstract final class AssignIcons {
  static const DIconData groupPlus = DIconData(
    'group-plus',
    LucideIcons.userRoundPlus,
  );
}

const assignIconCatalog = PluginIconCatalog(
  owner: PluginId('discourse-assign'),
  entries: {'group-plus': AssignIcons.groupPlus},
);
