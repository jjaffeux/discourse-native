import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool forumTabsEnabledFor({
  required TargetPlatform platform,
  required bool isWeb,
}) {
  if (isWeb) return false;
  return switch (platform) {
    TargetPlatform.macOS ||
    TargetPlatform.linux ||
    TargetPlatform.windows => true,
    TargetPlatform.iOS ||
    TargetPlatform.android ||
    TargetPlatform.fuchsia => false,
  };
}

bool get forumTabsEnabledForCurrentPlatform =>
    forumTabsEnabledFor(platform: defaultTargetPlatform, isWeb: kIsWeb);

extension TouchPlatform on BuildContext {
  bool get isTouch => switch (Theme.of(this).platform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    _ => false,
  };
}
