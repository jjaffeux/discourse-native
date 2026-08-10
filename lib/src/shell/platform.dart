import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Whether forum tab controls belong on this platform.
///
/// This is deliberately an operating-system capability, not a window-size
/// breakpoint: a narrow desktop window still has desktop tabs, while a wide
/// mobile or web viewport does not.
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

/// The difference between a finger and a pointer, as far as gestures care.
extension TouchPlatform on BuildContext {
  /// True on platforms whose only way in is a finger.
  ///
  /// A pointer is the only thing that can hover, so every affordance with a
  /// hover panel needs a sheet as the touch way in — and long press is the
  /// gesture each platform already means by "what else can this do". This is
  /// what decides between the two.
  bool get isTouch => switch (Theme.of(this).platform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    _ => false,
  };
}
