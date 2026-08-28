import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/site_config.dart';

/// The stable request presented to optimistic chat-preview contributions.
@immutable
final class ChatPreviewRequest {
  const ChatPreviewRequest({
    required this.raw,
    required this.siteConfig,
    this.trustedSeed,
  });

  final String raw;
  final SiteConfig siteConfig;
  final TrustedPreviewSeed? trustedSeed;
}

sealed class ChatPreviewResult {
  const ChatPreviewResult();
}

@immutable
final class ProjectedPreview extends ChatPreviewResult {
  const ProjectedPreview(this.document);

  final PreviewDocument document;
}

@immutable
final class SourceFallback extends ChatPreviewResult {
  const SourceFallback(this.raw, this.reason);

  /// Kept on the result so fallback can never accidentally display a rewritten
  /// or sanitized version of the outgoing source.
  final String raw;
  final ChatPreviewFallbackReason reason;
}

enum ChatPreviewFallbackReason {
  unsupportedSyntax,
  ambiguousSyntax,
  pluginBlocked,
  pluginFailure,
  duplicatePluginId,
  invalidPluginClaim,
  overlappingPluginClaims,
  invalidTrustedSeed,
  resourceLimit,
  internalFailure,
}

@immutable
final class PreviewDocument {
  PreviewDocument(this.source, Iterable<ChatPreviewNode> nodes)
    : nodes = List.unmodifiable(nodes);

  final String source;
  final List<ChatPreviewNode> nodes;
}

@immutable
final class SourceRange {
  const SourceRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;
  bool get isEmpty => start == end;

  bool isValidFor(String source) =>
      start >= 0 && end >= start && end <= source.length;

  bool overlaps(SourceRange other) => start < other.end && other.start < end;

  @override
  bool operator ==(Object other) =>
      other is SourceRange && start == other.start && end == other.end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '[$start,$end)';
}

sealed class ChatPreviewNode {
  const ChatPreviewNode({required this.range});

  final SourceRange range;
}

enum ChatPreviewTextStyle { bold, italic, strikethrough, code }

@immutable
final class ChatPreviewText extends ChatPreviewNode {
  ChatPreviewText({
    required super.range,
    required this.text,
    Iterable<ChatPreviewTextStyle> styles = const [],
  }) : styles = Set.unmodifiable(styles);

  final String text;
  final Set<ChatPreviewTextStyle> styles;
}

@immutable
final class ChatPreviewLineBreak extends ChatPreviewNode {
  const ChatPreviewLineBreak({required super.range});
}

/// A Markdown delimiter which owns source but has no provisional pixels.
@immutable
final class ChatPreviewSyntax extends ChatPreviewNode {
  const ChatPreviewSyntax({required super.range, required this.source});

  final String source;
}

@immutable
final class ChatPreviewCodeBlock extends ChatPreviewNode {
  const ChatPreviewCodeBlock({
    required super.range,
    required this.bodyRange,
    required this.code,
    this.language,
  });

  final SourceRange bodyRange;
  final String code;
  final String? language;
}

@immutable
final class ChatPreviewImage extends ChatPreviewNode {
  const ChatPreviewImage({
    required super.range,
    required this.url,
    required this.title,
    required this.width,
    required this.height,
    required this.fallbackText,
  });

  final Uri url;
  final String title;
  final int width;
  final int height;
  final String fallbackText;
}

/// An opaque, typed extension node. Only the adapter with [featureId] may
/// interpret [kind] and [attributes].
@immutable
final class PluginPreviewNode extends ChatPreviewNode {
  PluginPreviewNode({
    required super.range,
    required this.featureId,
    required this.kind,
    required this.fallbackText,
    Map<String, String> attributes = const {},
    Iterable<ChatPreviewTextStyle> styles = const [],
  }) : attributes = UnmodifiableMapView(Map.of(attributes)),
       styles = Set.unmodifiable(styles);

  final String featureId;
  final String kind;
  final String fallbackText;
  final Map<String, String> attributes;
  final Set<ChatPreviewTextStyle> styles;

  PluginPreviewNode withStyles(Iterable<ChatPreviewTextStyle> next) =>
      PluginPreviewNode(
        range: range,
        featureId: featureId,
        kind: kind,
        fallbackText: fallbackText,
        attributes: attributes,
        styles: next,
      );
}

sealed class TrustedPreviewSeed {
  const TrustedPreviewSeed();
}

@immutable
final class TrustedGifPreviewSeed extends TrustedPreviewSeed {
  const TrustedGifPreviewSeed({
    required this.url,
    required this.title,
    required this.width,
    required this.height,
  });

  final Uri url;
  final String title;
  final int width;
  final int height;
}

/// Pure inspection contract implemented by optional preview contributors.
///
/// Widget construction is intentionally a separate concern owned by the
/// registry so the projected document never stores locally generated HTML or
/// a widget instance.
abstract interface class ChatPreviewPluginAdapter {
  String get previewFeatureId;
  ChatPreviewInspection inspect(ChatPreviewRequest request);
}

@immutable
final class ChatPreviewInspection {
  ChatPreviewInspection({
    Iterable<ChatPreviewClaim> claims = const [],
    Iterable<ChatPreviewBlocker> blockers = const [],
  }) : claims = List.unmodifiable(claims),
       blockers = List.unmodifiable(blockers);

  final List<ChatPreviewClaim> claims;
  final List<ChatPreviewBlocker> blockers;
}

@immutable
final class ChatPreviewClaim {
  const ChatPreviewClaim({required this.range, required this.node});

  final SourceRange range;
  final PluginPreviewNode node;
}

@immutable
final class ChatPreviewBlocker {
  const ChatPreviewBlocker(this.reason, {this.range});

  final String reason;
  final SourceRange? range;
}
