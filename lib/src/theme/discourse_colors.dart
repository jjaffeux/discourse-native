import 'package:flutter/material.dart';

const Color discourseBlue = Color(0xFF0088CC);

const Color discourseDarkBlue = Color(0xFF099DD7);

const Color discourseLove = Color(0xFFFA6C8D);

const Color discourseSuccess = Color(0xFF009900);

@immutable
class DiscourseColors extends ThemeExtension<DiscourseColors> {
  const DiscourseColors({
    required this.success,
    required this.unreadIndicator,
    required this.notificationIndicator,
    required this.notificationForeground,
    required this.love,
    required this.primaryLowMid,
    required this.primaryHigh,
    required this.whisper,
    required this.primaryVeryHigh,
  });

  final Color success;

  /// An ordinary unread dot, matching core's
  /// `--token-color-background-accent-subtle` role.
  final Color unreadIndicator;

  /// Header, topic and chat activity: core's `--tertiary-med-or-tertiary`.
  final Color notificationIndicator;

  /// Text on solid notification badges: core's `--secondary`.
  final Color notificationForeground;

  final Color love;

  /// Faint foregrounds such as Chat's direct-reply icon, matching core's
  /// `--primary-low-mid` role.
  final Color primaryLowMid;

  /// Muted foregrounds such as legacy GitHub onebox SVGs, matching core's
  /// `--primary-high` role.
  final Color primaryHigh;

  /// Whisper body text, mirroring Discourse's `--primary-medium` role.
  final Color whisper;

  /// Strong secondary copy, mirroring `--primary-very-high`.
  final Color primaryVeryHigh;

  static const DiscourseColors light = DiscourseColors(
    success: discourseSuccess,
    unreadIndicator: Color(0xFF66CCFF),
    notificationIndicator: Color(0xFF66CCFF),
    notificationForeground: Colors.white,
    love: discourseLove,
    primaryLowMid: Color(0xFFBDBDBD),
    primaryHigh: Color(0xFF646464),
    whisper: Color(0xFF919191),
    primaryVeryHigh: Color(0xFF414141),
  );

  static const DiscourseColors dark = DiscourseColors(
    success: Color(0xFF1CA551),
    unreadIndicator: discourseDarkBlue,
    notificationIndicator: discourseDarkBlue,
    notificationForeground: Color(0xFF222222),
    love: discourseLove,
    primaryLowMid: Color(0xFF7A7A7A),
    primaryHigh: Color(0xFFA6A6A6),
    whisper: Color(0xFF909090),
    primaryVeryHigh: Color(0xFFC7C7C7),
  );

  @override
  DiscourseColors copyWith({
    Color? success,
    Color? unreadIndicator,
    Color? notificationIndicator,
    Color? notificationForeground,
    Color? love,
    Color? primaryLowMid,
    Color? primaryHigh,
    Color? whisper,
    Color? primaryVeryHigh,
  }) => DiscourseColors(
    success: success ?? this.success,
    unreadIndicator: unreadIndicator ?? this.unreadIndicator,
    notificationIndicator: notificationIndicator ?? this.notificationIndicator,
    notificationForeground:
        notificationForeground ?? this.notificationForeground,
    love: love ?? this.love,
    primaryLowMid: primaryLowMid ?? this.primaryLowMid,
    primaryHigh: primaryHigh ?? this.primaryHigh,
    whisper: whisper ?? this.whisper,
    primaryVeryHigh: primaryVeryHigh ?? this.primaryVeryHigh,
  );

  @override
  DiscourseColors lerp(ThemeExtension<DiscourseColors>? other, double t) {
    if (other is! DiscourseColors) return this;
    return DiscourseColors(
      success: Color.lerp(success, other.success, t)!,
      unreadIndicator: Color.lerp(unreadIndicator, other.unreadIndicator, t)!,
      notificationIndicator: Color.lerp(
        notificationIndicator,
        other.notificationIndicator,
        t,
      )!,
      notificationForeground: Color.lerp(
        notificationForeground,
        other.notificationForeground,
        t,
      )!,
      love: Color.lerp(love, other.love, t)!,
      primaryLowMid: Color.lerp(primaryLowMid, other.primaryLowMid, t)!,
      primaryHigh: Color.lerp(primaryHigh, other.primaryHigh, t)!,
      whisper: Color.lerp(whisper, other.whisper, t)!,
      primaryVeryHigh: Color.lerp(primaryVeryHigh, other.primaryVeryHigh, t)!,
    );
  }
}
