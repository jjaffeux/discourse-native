import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../theme/d_icon_sets.dart';
import 'forum_background.dart';
import 'forum_font.dart';

/// Fonts and window effects shared by every forum. Only a
/// forum's colours, their tint, and whether it shows them light or dark, are
/// its own, so moving between forums never changes the font or the window's
/// opacity.
@immutable
final class SharedAppearance {
  const SharedAppearance({
    this.font = ForumFont.system,
    this.interfaceFont = ForumFont.system,
    this.iconSet = DIconSet.defaultSet,
    this.effects = const ForumBackground.appearance(),
  });

  /// Damaged effects fall back to none rather than discarding the font. A
  /// tint stored while it was shared is dropped: tints belong to themes.
  factory SharedAppearance.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 && json['version'] != 2) {
      throw FormatException(appL10n.invalidAppearance);
    }
    var effects = const ForumBackground.appearance();
    try {
      effects = ForumBackground.fromJson(
        json['effects'],
      ).toAccentTint().copyWith(strength: 0);
    } on FormatException {
      // Keep the font.
    }
    return SharedAppearance(
      font: ForumFont.fromName(json['readingFont'] ?? json['font']),
      interfaceFont: ForumFont.fromName(json['interfaceFont']),
      iconSet: DIconSet.fromName(json['iconSet']),
      effects: effects,
    );
  }

  static const defaults = SharedAppearance();

  /// The saved reading choice; the legacy name remains source compatible.
  final ForumFont font;
  ForumFont get readingFont => font;
  final ForumFont interfaceFont;

  /// System reading follows the interface, as in the font chooser.
  String? get readingFamily => font.family ?? interfaceFont.family;
  final DIconSet iconSet;

  /// Opacity and texture, drawn over whichever colours a forum uses. Its
  /// strength is never drawn: a theme carries its own [ForumTheme.tint].
  final ForumBackground effects;

  SharedAppearance copyWith({
    ForumFont? font,
    ForumFont? interfaceFont,
    DIconSet? iconSet,
    ForumBackground? effects,
  }) => SharedAppearance(
    font: font ?? this.font,
    interfaceFont: interfaceFont ?? this.interfaceFont,
    iconSet: iconSet ?? this.iconSet,
    effects: effects ?? this.effects,
  );

  Map<String, dynamic> toJson() => {
    'version': 2,
    'readingFont': font.name,
    'interfaceFont': interfaceFont.name,
    'iconSet': iconSet.name,
    'effects': effects.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is SharedAppearance &&
      other.font == font &&
      other.interfaceFont == interfaceFont &&
      other.iconSet == iconSet &&
      other.effects == effects;

  @override
  int get hashCode => Object.hash(font, interfaceFont, iconSet, effects);
}
