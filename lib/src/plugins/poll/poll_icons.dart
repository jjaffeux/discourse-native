import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../plugin_api/plugin_icon_catalog.dart';
import '../../theme/d_icon.dart';

abstract final class PollIcons {
  static const DIconData squarePollHorizontal = DIconData(
    'square-poll-horizontal',
    LucideIcons.chartNoAxesColumnIncreasing,
  );
}

const pollIconCatalog = PluginIconCatalog(
  owner: PluginId('poll'),
  entries: {'square-poll-horizontal': PollIcons.squarePollHorizontal},
);
