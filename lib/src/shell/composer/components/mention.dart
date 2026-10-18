import 'package:flutter/material.dart';

import '../../mention.dart';
import '../source_projection.dart';

List<InlineSpan> buildComposerMentionSpans({
  required String source,
  required TextRange range,
  required TextStyle baseStyle,
  required Key pillKey,
}) => composerInlinePlaceholderSpans(
  source: source,
  range: range,
  baseStyle: baseStyle,
  child: KeyedSubtree(
    key: pillKey,
    child: MentionPill(
      label: source.substring(range.start, range.end),
      baseStyle: baseStyle,
    ),
  ),
);
