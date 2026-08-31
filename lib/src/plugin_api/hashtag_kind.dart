import 'package:flutter/foundation.dart';

import '../theme/d_icon.dart';

/// Slots left after core's category and tag in Discourse's 20-kind request.
const int maximumPluginHashtagKinds = 18;

enum HashtagStyle {
  square,
  icon,
  emoji;

  /// Discourse's default is the category-style square when no style arrives.
  static HashtagStyle parse(String? value) => switch (value) {
    'icon' => HashtagStyle.icon,
    'emoji' => HashtagStyle.emoji,
    _ => HashtagStyle.square,
  };
}

enum HashtagColorPolicy { none, supplied, category }

@immutable
final class HashtagPresentationRequest {
  HashtagPresentationRequest({
    required this.type,
    required this.style,
    this.icon,
    this.emoji,
    List<int> colorValues = const [],
  }) : colorValues = List.unmodifiable(colorValues);

  final String type;
  final HashtagStyle style;
  final String? icon;
  final String? emoji;
  final List<int> colorValues;

  @override
  bool operator ==(Object other) =>
      other is HashtagPresentationRequest &&
      other.type == type &&
      other.style == style &&
      other.icon == icon &&
      other.emoji == emoji &&
      listEquals(other.colorValues, colorValues);

  @override
  int get hashCode =>
      Object.hash(type, style, icon, emoji, Object.hashAll(colorValues));
}

@immutable
final class HashtagPresentation {
  HashtagPresentation({
    required this.type,
    required this.style,
    required this.fallbackIcon,
    required this.colorPolicy,
    this.icon,
    this.emoji,
    List<int> colorValues = const [],
  }) : colorValues = List.unmodifiable(colorValues);

  factory HashtagPresentation.fromRequest(
    HashtagPresentationRequest request, {
    required DIconData fallbackIcon,
    required HashtagColorPolicy colorPolicy,
  }) => HashtagPresentation(
    type: request.type,
    style: request.style,
    icon: request.icon,
    emoji: request.emoji,
    colorValues: colorPolicy == HashtagColorPolicy.none
        ? const []
        : request.colorValues,
    fallbackIcon: fallbackIcon,
    colorPolicy: colorPolicy,
  );

  final String type;
  final HashtagStyle style;
  final String? icon;
  final String? emoji;
  final List<int> colorValues;
  final DIconData fallbackIcon;
  final HashtagColorPolicy colorPolicy;

  @override
  bool operator ==(Object other) =>
      other is HashtagPresentation &&
      other.type == type &&
      other.style == style &&
      other.icon == icon &&
      other.emoji == emoji &&
      listEquals(other.colorValues, colorValues) &&
      other.fallbackIcon == fallbackIcon &&
      other.colorPolicy == colorPolicy;

  @override
  int get hashCode => Object.hash(
    type,
    style,
    icon,
    emoji,
    Object.hashAll(colorValues),
    fallbackIcon,
    colorPolicy,
  );
}

typedef PluginHashtagPresenter =
    HashtagPresentation Function(HashtagPresentationRequest request);

typedef PluginHashtagPresentationResolver =
    HashtagPresentation? Function(HashtagPresentationRequest request);

@immutable
final class PluginHashtagKind {
  const PluginHashtagKind(this.wireType, this.present);

  final String wireType;
  final PluginHashtagPresenter present;
}

abstract interface class HashtagKindPlugin {
  List<PluginHashtagKind> get hashtagKinds;
}
