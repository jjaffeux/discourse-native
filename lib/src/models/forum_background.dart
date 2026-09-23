import 'dart:ui';

import 'package:flutter/foundation.dart';

enum ForumBackgroundEffect { normal, lava, noise, gradient }

/// Portable background color and window effects for a custom forum theme.
@immutable
class ForumBackground {
  const ForumBackground({
    required this.color,
    this.strength = .5,
    this.effect = ForumBackgroundEffect.normal,
    this.noiseIntensity = defaultNoiseIntensity,
    this.transparency = defaultTransparency,
    this.useAccentTint = false,
  }) : assert(strength >= 0 && strength <= 1),
       assert(noiseIntensity >= 0 && noiseIntensity <= 1),
       assert(transparency >= 0 && transparency <= maxTransparency);

  static const defaultNoiseIntensity = .2;
  static const defaultTransparency = .1;

  /// The reference keeps reading surfaces at least 70% opaque.
  static const maxTransparency = .3;
  static const maxTint = .22;
  static const maxTextTint = .11;

  const ForumBackground.appearance({
    this.strength = 0,
    this.effect = ForumBackgroundEffect.normal,
    this.noiseIntensity = .14,
    this.transparency = 0,
  }) : color = const Color(0xff000000),
       useAccentTint = true,
       assert(strength >= 0 && strength <= 1),
       assert(noiseIntensity >= 0 && noiseIntensity <= 1),
       assert(transparency >= 0 && transparency <= maxTransparency);

  factory ForumBackground.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid background.');
    }
    final color = value['color'];
    final strength = value['strength'];
    final noiseIntensity = value.containsKey('noiseIntensity')
        ? value['noiseIntensity']
        : defaultNoiseIntensity;
    final transparency = value.containsKey('transparency')
        ? value['transparency']
        : defaultTransparency;
    final effect = ForumBackgroundEffect.values
        .where((effect) => effect.name == value['effect'])
        .firstOrNull;
    if (color is! String ||
        !RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(color) ||
        strength is! num ||
        !strength.isFinite ||
        strength < 0 ||
        strength > 1 ||
        noiseIntensity is! num ||
        !noiseIntensity.isFinite ||
        noiseIntensity < 0 ||
        noiseIntensity > 1 ||
        transparency is! num ||
        !transparency.isFinite ||
        transparency < 0 ||
        transparency > maxTransparency ||
        effect == null ||
        (value.containsKey('useAccentTint') &&
            value['useAccentTint'] is! bool)) {
      throw const FormatException('Invalid background.');
    }
    return ForumBackground(
      color: Color(0xff000000 | int.parse(color.substring(1), radix: 16)),
      strength: strength.toDouble(),
      effect: effect,
      noiseIntensity: noiseIntensity.toDouble(),
      transparency: transparency.toDouble(),
      useAccentTint: value['useAccentTint'] == true,
    );
  }

  final Color color;
  final double strength;
  final ForumBackgroundEffect effect;

  /// Texture intensity, independent of color tint and panel transparency.
  final double noiseIntensity;

  /// How much of the window canvas shows through content panels.
  final double transparency;

  /// New themes tint both background and text with their own accent. Older
  /// exported themes retain their separately chosen background treatment.
  final bool useAccentTint;

  ForumBackground copyWith({
    Color? color,
    double? strength,
    ForumBackgroundEffect? effect,
    double? noiseIntensity,
    double? transparency,
    bool? useAccentTint,
  }) => ForumBackground(
    color: color ?? this.color,
    strength: strength ?? this.strength,
    effect: effect ?? this.effect,
    noiseIntensity: noiseIntensity ?? this.noiseIntensity,
    transparency: transparency ?? this.transparency,
    useAccentTint: useAccentTint ?? this.useAccentTint,
  );

  Map<String, dynamic> toJson() => {
    'color':
        '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}',
    'strength': strength,
    'effect': effect.name,
    'noiseIntensity': noiseIntensity,
    'transparency': transparency,
    if (useAccentTint) 'useAccentTint': true,
  };

  @override
  bool operator ==(Object other) =>
      other is ForumBackground &&
      other.color == color &&
      other.strength == strength &&
      other.effect == effect &&
      other.noiseIntensity == noiseIntensity &&
      other.transparency == transparency &&
      other.useAccentTint == useAccentTint;

  @override
  int get hashCode => Object.hash(
    color,
    strength,
    effect,
    noiseIntensity,
    transparency,
    useAccentTint,
  );
}
