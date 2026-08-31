import 'package:flutter/foundation.dart';

enum ContentAlignment { left, center, right }

@immutable
final class AppSettings {
  const AppSettings({this.contentAlignment = ContentAlignment.center});

  static const AppSettings defaults = AppSettings();

  final ContentAlignment contentAlignment;

  AppSettings copyWith({ContentAlignment? contentAlignment}) =>
      AppSettings(contentAlignment: contentAlignment ?? this.contentAlignment);

  @override
  bool operator ==(Object other) =>
      other is AppSettings && other.contentAlignment == contentAlignment;

  @override
  int get hashCode => contentAlignment.hashCode;
}
