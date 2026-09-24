import 'package:flutter/foundation.dart';

import 'forum_background.dart';
import 'forum_font.dart';

/// What every forum shares: the reading font and the window effects. Only a
/// forum's colours, and whether it shows them light or dark, are its own, so
/// moving between forums never changes the font or the window's opacity.
@immutable
final class SharedAppearance {
  const SharedAppearance({
    this.font = ForumFont.system,
    this.effects = const ForumBackground.appearance(),
  });

  /// Damaged effects fall back to none rather than discarding the font.
  factory SharedAppearance.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Invalid appearance.');
    }
    var effects = const ForumBackground.appearance();
    try {
      effects = ForumBackground.fromJson(json['effects']).toAccentTint();
    } on FormatException {
      // Keep the font.
    }
    return SharedAppearance(
      font: ForumFont.fromName(json['font']),
      effects: effects,
    );
  }

  static const defaults = SharedAppearance();

  final ForumFont font;

  /// Tint, opacity and texture, drawn over whichever colours a forum uses.
  final ForumBackground effects;

  SharedAppearance copyWith({ForumFont? font, ForumBackground? effects}) =>
      SharedAppearance(
        font: font ?? this.font,
        effects: effects ?? this.effects,
      );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'font': font.name,
    'effects': effects.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is SharedAppearance &&
      other.font == font &&
      other.effects == effects;

  @override
  int get hashCode => Object.hash(font, effects);
}
