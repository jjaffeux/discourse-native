import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../plugin_api/plugin_icon_catalog.dart';
import '../../theme/d_icon.dart';

abstract final class DiscourseAiIcons {
  static const DIconData sparkles = DIconData(
    'discourse-sparkles',
    LucideIcons.sparkles,
  );
}

const discourseAiIconCatalog = PluginIconCatalog(
  owner: PluginId('discourse-ai'),
  entries: {'discourse-sparkles': DiscourseAiIcons.sparkles},
);
