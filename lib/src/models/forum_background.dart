import 'dart:ui';

import 'package:flutter/foundation.dart';

enum ForumBackgroundEffect { normal, lava, noise }

/// Portable background color and window effects for a custom forum theme.
@immutable
class ForumBackground {
  const ForumBackground({
    required this.color,
    this.strength = .5,
    this.effect = ForumBackgroundEffect.normal,
  }) : assert(strength >= 0 && strength <= 1);

  factory ForumBackground.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid background.');
    }
    final color = value['color'];
    final strength = value['strength'];
    final effect = ForumBackgroundEffect.values
        .where((effect) => effect.name == value['effect'])
        .firstOrNull;
    if (color is! String ||
        !RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(color) ||
        strength is! num ||
        !strength.isFinite ||
        strength < 0 ||
        strength > 1 ||
        effect == null) {
      throw const FormatException('Invalid background.');
    }
    return ForumBackground(
      color: Color(0xff000000 | int.parse(color.substring(1), radix: 16)),
      strength: strength.toDouble(),
      effect: effect,
    );
  }

  final Color color;
  final double strength;
  final ForumBackgroundEffect effect;

  ForumBackground copyWith({
    Color? color,
    double? strength,
    ForumBackgroundEffect? effect,
  }) => ForumBackground(
    color: color ?? this.color,
    strength: strength ?? this.strength,
    effect: effect ?? this.effect,
  );

  Map<String, dynamic> toJson() => {
    'color':
        '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}',
    'strength': strength,
    'effect': effect.name,
  };

  @override
  bool operator ==(Object other) =>
      other is ForumBackground &&
      other.color == color &&
      other.strength == strength &&
      other.effect == effect;

  @override
  int get hashCode => Object.hash(color, strength, effect);
}
