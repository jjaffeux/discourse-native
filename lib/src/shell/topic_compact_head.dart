import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../foundation/icons/d_icons.dart';
import '../models/topic.dart';
import '../theme/discourse_typography.dart';
import 'category_icon.dart';
import 'content_reading_lane.dart';
import 'topic_title.dart';

const double _lineGap = 6;
const double _markSize = 9;
const double _caretWidth = 6;

/// How many of a topic's [tags] the compact line can name before a count of
/// the rest, once its [path] is paid for. Each piece is counted with the gap
/// after it, as the reference's `barTagsThatFit` counts them.
int topicCompactTagsThatFit({
  required double width,
  required List<String> path,
  required List<String> tags,
  required double Function(String text) measure,
}) {
  if (width <= 0) return tags.length;
  var used = 0.0;
  for (final (index, name) in path.indexed) {
    used +=
        (index > 0 ? _caretWidth + _lineGap : 0) +
        _markSize +
        _lineGap +
        measure(name) +
        _lineGap;
  }
  var shown = 0;
  while (shown < tags.length) {
    final tag = measure('#${tags[shown]}') + _lineGap;
    final rest = tags.length - shown - 1;
    final count = rest > 0 ? measure('+$rest') + _lineGap : 0.0;
    if (used + tag + count > width) break;
    used += tag;
    shown++;
  }
  return shown;
}

/// A status mark drawn before the compact title.
typedef TopicCompactStatus = ({DIconData icon, String label});

/// The head a desktop reader changes to once the page has gone under it: the
/// title over where the topic is filed, the tools at the end of the line.
/// [part] carries what both heads show from one place to the other.
class TopicCompactHead extends StatelessWidget {
  const TopicCompactHead({
    super.key,
    required this.title,
    required this.siteUrl,
    required this.part,
    this.status = const [],
    this.path = const [],
    this.tags = const [],
    this.tools,
  });

  /// Null while loading a topic whose title no route or list row supplied.
  final String? title;
  final String siteUrl;
  final Widget Function(String id, Widget child) part;
  final List<TopicCompactStatus> status;
  final List<TopicCategory> path;
  final List<TopicTag> tags;
  final Widget? tools;

  @override
  Widget build(BuildContext context) {
    final tools = this.tools;
    final identity = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 3,
      children: [
        // Left to its own width, so the title resizes in its proportions.
        part('title', _title(context)),
        if (path.isNotEmpty || tags.isNotEmpty)
          _TopicCompactMetadata(siteUrl: siteUrl, path: path, tags: tags),
      ],
    );
    return ContentReadingLaneBox(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Large text wraps the tools rather than taking the whole line,
            // leaving the room the full head holds for its own title.
            final toolRoom =
                constraints.maxWidth -
                10 -
                3 *
                    DControlStyle.scaledHeight(
                      DControlSize.filter,
                      MediaQuery.textScalerOf(context),
                      context: context,
                    );
            return Row(
              spacing: 10,
              children: [
                Expanded(child: identity),
                if (tools != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.max(0, toolRoom),
                    ),
                    child: part('tools', tools),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _title(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.headlineSmall?.copyWith(fontSize: DiscourseTypography.sm);
    final known = title;
    if (known == null) return Text('', style: style);
    final muted = DTokens.of(context).mutedForeground;
    // The title text already names the topic in full, even when clipped.
    return DTooltip(
      message: known,
      excludeFromSemantics: true,
      child: TopicTitle(
        known,
        key: const ValueKey('topic-compact-title'),
        siteUrl: siteUrl,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
        leading: [
          for (final mark in status)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 5),
              child: DTooltip(
                message: mark.label,
                excludeFromSemantics: true,
                child: DIcon(
                  mark.icon,
                  size: 11,
                  color: muted,
                  semanticLabel: mark.label,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopicCompactMetadata extends StatelessWidget {
  const _TopicCompactMetadata({
    required this.siteUrl,
    required this.path,
    required this.tags,
  });

  final String siteUrl;
  final List<TopicCategory> path;
  final List<TopicTag> tags;

  @override
  Widget build(BuildContext context) {
    final muted = DTokens.of(context).mutedForeground;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: DiscourseTypography.micro,
      color: muted,
    );
    final direction = DDirection.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final shown = topicCompactTagsThatFit(
          width: constraints.maxWidth,
          path: [for (final step in path) step.name],
          tags: [for (final tag in tags) tag.name],
          measure: measure,
        );
        final hidden = tags.skip(shown).map((tag) => tag.name).toList();
        return Row(
          key: const ValueKey('topic-compact-metadata'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    for (final (index, step) in path.indexed) ...[
                      if (index > 0)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: _lineGap,
                            ),
                            child: DIcon(
                              DIcons.chevronRight,
                              size: _markSize,
                              color: muted,
                            ),
                          ),
                        ),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            end: _lineGap,
                          ),
                          child: CategoryIcon(
                            category: step,
                            siteUrl: siteUrl,
                            squareSize: _markSize,
                            size: _markSize,
                          ),
                        ),
                      ),
                      TextSpan(text: step.name),
                    ],
                    for (final (index, tag) in tags.take(shown).indexed) ...[
                      if (path.isNotEmpty || index > 0)
                        const WidgetSpan(child: SizedBox(width: _lineGap)),
                      TextSpan(text: '#${tag.name}'),
                    ],
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            if (hidden.isNotEmpty) ...[
              const SizedBox(width: _lineGap),
              DTooltip(
                key: const ValueKey('topic-compact-more-tags'),
                message: hidden.join(', '),
                child: Text('+${hidden.length}', style: style),
              ),
            ],
          ],
        );
      },
    );
  }
}
