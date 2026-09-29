import 'package:flutter/foundation.dart';

enum AppThemeMode { system, light, dark }

/// Legacy persisted preference. Topic lists now always use full-width rows.
enum TopicListDisplayMode { card, compact }

enum AppTextScale {
  percent80(0.80),
  percent85(0.85),
  percent90(0.90),
  percent95(0.95),
  percent100(1.00),
  percent105(1.05),
  percent110(1.10),
  percent115(1.15),
  percent120(1.20),
  percent125(1.25),
  percent130(1.30),
  percent135(1.35),
  percent140(1.40),
  percent145(1.45),
  percent150(1.50),
  percent175(1.75),
  percent200(2.00);

  const AppTextScale(this.factor);

  final double factor;
}

@immutable
final class AppSettings {
  const AppSettings({
    this.limitContentSize = true,
    this.disableGifAnimations = false,
    this.textScale = AppTextScale.percent100,
    this.themeMode = AppThemeMode.system,
    this.topicListMode = TopicListDisplayMode.card,
  });

  static const AppSettings defaults = AppSettings();

  final bool limitContentSize;
  final bool disableGifAnimations;
  final AppTextScale textScale;
  // Legacy app-wide choice used only to seed existing forums on migration.
  final AppThemeMode themeMode;
  final TopicListDisplayMode topicListMode;

  AppSettings copyWith({
    bool? limitContentSize,
    bool? disableGifAnimations,
    AppTextScale? textScale,
    AppThemeMode? themeMode,
    TopicListDisplayMode? topicListMode,
  }) => AppSettings(
    limitContentSize: limitContentSize ?? this.limitContentSize,
    disableGifAnimations: disableGifAnimations ?? this.disableGifAnimations,
    textScale: textScale ?? this.textScale,
    themeMode: themeMode ?? this.themeMode,
    topicListMode: topicListMode ?? this.topicListMode,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.limitContentSize == limitContentSize &&
      other.disableGifAnimations == disableGifAnimations &&
      other.textScale == textScale &&
      other.themeMode == themeMode &&
      other.topicListMode == topicListMode;

  @override
  int get hashCode => Object.hash(
    limitContentSize,
    disableGifAnimations,
    textScale,
    themeMode,
    topicListMode,
  );
}
