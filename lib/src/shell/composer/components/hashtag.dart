import 'package:flutter/material.dart';

import '../../../models/found_hashtag.dart';
import '../../../plugin_api/hashtag_kind.dart';
import '../../hashtag.dart';
import '../source_projection.dart';

List<InlineSpan> buildComposerHashtagSpans({
  required String source,
  required TextRange range,
  required FoundHashtag hashtag,
  required TextStyle baseStyle,
  required String? siteUrl,
  required PluginHashtagPresentationResolver? pluginPresentation,
}) => composerInlinePlaceholderSpans(
  source: source,
  range: range,
  baseStyle: baseStyle,
  child: HashtagPill(
    label: source.substring(range.start, range.end),
    baseStyle: baseStyle,
    presentation: resolveHashtagPresentation(
      HashtagPresentationRequest(
        type: hashtag.type,
        style: HashtagStyle.parse(hashtag.styleType),
        icon: hashtag.icon,
        emoji: hashtag.emoji,
        colorValues: hashtag.colorValues,
      ),
      pluginPresentation: pluginPresentation,
    ),
    siteUrl: siteUrl,
  ),
);
