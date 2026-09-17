import 'package:flutter/foundation.dart';

enum AppThemeMode { system, light, dark }

enum ContentAlignment { left, center, right }

enum TopicListDisplayMode { card, compact }

enum AppTextScale {
  percent80(0.8),
  percent90(0.9),
  percent100(1.0),
  percent110(1.1),
  percent125(1.25),
  percent150(1.5),
  percent175(1.75),
  percent200(2.0);

  const AppTextScale(this.factor);

  final double factor;
}

@immutable
final class AppSettings {
  const AppSettings({
    this.contentAlignment = ContentAlignment.center,
    this.disableGifAnimations = false,
    this.textScale = AppTextScale.percent100,
    this.themeMode = AppThemeMode.system,
    this.topicListLargerText = false,
    this.topicListMode = TopicListDisplayMode.card,
  });

  static const AppSettings defaults = AppSettings();

  final ContentAlignment contentAlignment;
  final bool disableGifAnimations;
  final AppTextScale textScale;
  final AppThemeMode themeMode;
  final bool topicListLargerText;
  final TopicListDisplayMode topicListMode;

  AppSettings copyWith({
    ContentAlignment? contentAlignment,
    bool? disableGifAnimations,
    AppTextScale? textScale,
    AppThemeMode? themeMode,
    bool? topicListLargerText,
    TopicListDisplayMode? topicListMode,
  }) => AppSettings(
    contentAlignment: contentAlignment ?? this.contentAlignment,
    disableGifAnimations: disableGifAnimations ?? this.disableGifAnimations,
    textScale: textScale ?? this.textScale,
    themeMode: themeMode ?? this.themeMode,
    topicListLargerText: topicListLargerText ?? this.topicListLargerText,
    topicListMode: topicListMode ?? this.topicListMode,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.contentAlignment == contentAlignment &&
      other.disableGifAnimations == disableGifAnimations &&
      other.textScale == textScale &&
      other.themeMode == themeMode &&
      other.topicListLargerText == topicListLargerText &&
      other.topicListMode == topicListMode;

  @override
  int get hashCode => Object.hash(
    contentAlignment,
    disableGifAnimations,
    textScale,
    themeMode,
    topicListLargerText,
    topicListMode,
  );
}
