import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../plugin_api/plugin_icon_catalog.dart';
import '../../theme/d_icon.dart';

abstract final class GifsIcons {
  static const DIconData gif = DIconData('gif', LucideIcons.fileImage);
}

const gifsIconCatalog = PluginIconCatalog(
  owner: PluginId('gifs'),
  entries: {'gif': GifsIcons.gif},
);
