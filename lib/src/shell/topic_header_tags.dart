import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/topic.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_picker.dart';
import 'topic_tag_picker.dart';

/// Keeps taxonomy on one line while leaving every tag accessible.
class TopicHeaderTags extends StatelessWidget {
  const TopicHeaderTags({
    super.key,
    required this.siteUrl,
    required this.topic,
  });

  final String siteUrl;
  final TopicDetail topic;

  @override
  Widget build(BuildContext context) => TopicTagMenuAnchor(
    siteUrl: siteUrl,
    topicId: topic.id,
    categoryId: topic.categoryId,
    tags: topic.tags,
    enabled: topic.canEditTags,
    builder: (context, edit, saving) => LayoutBuilder(
      builder: (context, constraints) {
        final tags = topic.tags;
        final theme = Theme.of(context);
        final style = theme.textTheme.labelSmall!.copyWith(
          fontSize: DiscourseTypography.fontDown2,
        );
        const gap = 7.0;
        double labelWidth(String label) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final width = painter.width.ceilToDouble() + 14;
          painter.dispose();
          return width;
        }

        String overflowLabel(int visible) => visible == 0
            ? 'Tags · ${tags.length}'
            : '+${tags.length - visible} tags';
        // Adding is also available in the overflow editor, so a narrow reader
        // can omit the separate plus without losing an action.
        final showAdd =
            topic.canEditTags &&
            (tags.isEmpty ||
                constraints.maxWidth >= labelWidth(overflowLabel(0)) + 35);
        final budget = math.max(
          0.0,
          constraints.maxWidth - (showAdd ? 28 + gap : 0),
        );
        final widths = [
          for (final tag in tags.take(3))
            math.min(148.0, labelWidth('# ${tag.name}')),
        ];
        var visible = widths.length;
        while (visible > 0) {
          final hidden = visible < tags.length;
          final needed =
              widths.take(visible).fold(0.0, (a, b) => a + b) +
              gap * (visible - 1) +
              (hidden ? gap + labelWidth(overflowLabel(visible)) : 0);
          if (needed <= budget) break;
          visible--;
        }
        final VoidCallback? open = topic.canEditTags
            ? edit
            : () => unawaited(
                showAnchoredPicker<void>(
                  context: context,
                  title: 'Topic tags',
                  barrierLabel: 'Dismiss topic tags',
                  popoverKey: const ValueKey('topic-header-tags-popover'),
                  builder: (_) => _ReadOnlyTags(tags: tags),
                ),
              );

        Widget chip(String label, Key key, {required String tooltip}) =>
            Tooltip(
              message: tooltip,
              child: Material(
                color: theme.shell.hover,
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  key: key,
                  onTap: open,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 5,
                    ),
                    child: Text(
                      label,
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            );

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < visible; index++) ...[
              if (index > 0) const SizedBox(width: gap),
              SizedBox(
                width: widths[index],
                child: chip(
                  '# ${tags[index].name}',
                  ValueKey(('topic-header-tag', tags[index].name)),
                  tooltip: topic.canEditTags
                      ? 'Edit topic tags · ${tags[index].name}'
                      : tags[index].name,
                ),
              ),
            ],
            if (visible < tags.length) ...[
              if (visible > 0) const SizedBox(width: gap),
              Flexible(
                child: chip(
                  overflowLabel(visible),
                  const ValueKey('topic-header-more-tags'),
                  tooltip: topic.canEditTags
                      ? 'View and edit all ${tags.length} topic tags'
                      : 'View all ${tags.length} topic tags',
                ),
              ),
            ],
            if (showAdd) ...[
              if (tags.isNotEmpty) const SizedBox(width: gap),
              SizedBox.square(
                dimension: 28,
                child: saving
                    ? const Padding(
                        padding: EdgeInsets.all(6),
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 1.5,
                        ),
                      )
                    : DButton.iconOnly(
                        key: const ValueKey('topic-header-add-tag'),
                        icon: const DIcon(DIcons.plus, size: 14),
                        tooltip: 'Add or remove topic tags',
                        onPressed: edit,
                        variant: DButtonVariant.flat,
                        size: DButtonSize.small,
                      ),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class _ReadOnlyTags extends StatefulWidget {
  const _ReadOnlyTags({required this.tags});

  final List<TopicTag> tags;

  @override
  State<_ReadOnlyTags> createState() => _ReadOnlyTagsState();
}

class _ReadOnlyTagsState extends State<_ReadOnlyTags> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final term = _query.text.trim().toLowerCase();
    final matches = widget.tags.where(
      (tag) => tag.name.toLowerCase().contains(term),
    );
    return AnchoredPickerContent(
      queryKey: const ValueKey('topic-header-tags-search'),
      queryController: _query,
      queryHint: 'Find a topic tag',
      onQueryChanged: (_) => setState(() {}),
      onQuerySubmitted: (_) {},
      children: [
        for (final tag in matches)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text('# ${tag.name}'),
          ),
        if (matches.isEmpty) const AnchoredPickerMessage('No matching tags'),
      ],
    );
  }
}
