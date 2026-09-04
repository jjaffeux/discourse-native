import 'package:lucide_flutter/lucide_flutter.dart';

import 'd_icon.dart';

abstract final class DNativeIcons {
  static const DIconData topic = DIconData(
    'discourse-native-topic',
    LucideIcons.layers3,
  );

  static const Map<String, DIconData> byName = {
    'discourse-native-topic': topic,
  };
}
