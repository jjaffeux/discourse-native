import 'package:flutter/foundation.dart';

enum ContentAlignment { left, center, right }

@immutable
final class AppSettings {
  const AppSettings({
    this.contentAlignment = ContentAlignment.center,
    this.disableGifAnimations = false,
  });

  static const AppSettings defaults = AppSettings();

  final ContentAlignment contentAlignment;
  final bool disableGifAnimations;

  AppSettings copyWith({
    ContentAlignment? contentAlignment,
    bool? disableGifAnimations,
  }) => AppSettings(
    contentAlignment: contentAlignment ?? this.contentAlignment,
    disableGifAnimations: disableGifAnimations ?? this.disableGifAnimations,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.contentAlignment == contentAlignment &&
      other.disableGifAnimations == disableGifAnimations;

  @override
  int get hashCode => Object.hash(contentAlignment, disableGifAnimations);
}
