import 'package:flutter/foundation.dart';

import '../theme/d_icon.dart';

/// Slots left after core's category and tag in Discourse's 20-kind request.
const int maximumPluginHashtagKinds = 18;

/// How a hashtag draws the artwork ahead of its label.
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

/// Where a hashtag presentation may obtain colour.
enum HashtagColorPolicy {
  /// This kind never uses colour, even when the wire payload supplies some.
  none,

  /// Use only the bounded colour values supplied with the wire payload.
  supplied,

  /// Use supplied colours when present, otherwise resolve the core category.
  category,
}

/// The neutral wire presentation offered to a registered hashtag kind.
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

/// A hashtag kind's resolved visual policy.
///
/// Presenters normally use [HashtagPresentation.fromRequest] so the site's
/// style, icon, emoji, and eligible colours travel through unchanged while the
/// owning kind supplies only its fallback and colour semantics.
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

/// Looks up an installed plugin presenter, or returns null for core/unknown.
typedef PluginHashtagPresentationResolver =
    HashtagPresentation? Function(HashtagPresentationRequest request);

/// One plugin-owned hashtag type, identified by the server's `type` value.
///
/// [wireType] is added to composer search and exact-ref lookup as well as used
/// to select [present], so recognition and rendering are one registration.
@immutable
final class PluginHashtagKind {
  const PluginHashtagKind(this.wireType, this.present);

  final String wireType;
  final PluginHashtagPresenter present;
}

/// Contributes plugin-owned hashtag types to the immutable application registry.
abstract interface class HashtagKindPlugin {
  List<PluginHashtagKind> get hashtagKinds;
}
