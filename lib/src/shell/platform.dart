import 'package:flutter/material.dart';

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
