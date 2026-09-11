import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/discourse_typography.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/topic.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'platform.dart';
import 'topic_tag_picker.dart';
import 'topic_taxonomy_picker.dart';

/// Keeps taxonomy on one line while leaving every tag accessible.
class TopicHeaderTags extends StatelessWidget {
  const TopicHeaderTags({
    super.key,
    required this.siteUrl,
    required this.topic,
    required this.onTagNavigate,
  });

  final String siteUrl;
  final TopicDetail topic;
  final TopicTagNavigationCallback onTagNavigate;

  @override
  Widget build(BuildContext context) => TopicTagMenuAnchor(
    siteUrl: siteUrl,
    topicId: topic.id,
    categoryId: topic.categoryId,
    tags: topic.tags,
    enabled: topic.canEditTags,
    onTagNavigate: onTagNavigate,
    builder: (context, edit, saving) => LayoutBuilder(
      builder: (context, constraints) {
        final tags = topic.tags;
        if (tags.isEmpty) {
          return topic.canEditTags
              ? DPopoverTrigger(
                  builder: (context, trigger) => DButton(
                    key: const ValueKey('topic-header-edit-tags'),
                    label: const Text('Add tag'),
                    icon: const DIcon(DIcons.tag, size: 12),
                    tooltip: 'Add tag',
                    variant: DButtonVariant.secondary,
                    size: DButtonSize.extraSmall,
                    focusNode: trigger.focusNode,
                    hasPopup: true,
                    expanded: trigger.open,
                    loading: saving,
                    loadingSemanticLabel: 'Saving tags',
                    onPressed: edit == null
                        ? null
                        : trigger.open
                        ? trigger.closePopover
                        : edit,
                  ),
                )
              : const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        final style = theme.textTheme.labelSmall?.copyWith(
          fontSize: DiscourseTypography.xs,
          height: 16 / 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        );
        const gap = 7.0;
        double labelWidth(String label) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: DDirection.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final width = painter.width.ceilToDouble() + 18;
          painter.dispose();
          return width;
        }

        String overflowLabel(int visible) => visible == 0
            ? 'Tags · ${tags.length}'
            : '+${tags.length - visible}';
        final editWidth = context.isTouch ? 48.0 : 28.0;
        // The overflow editor keeps editing available in narrow readers.
        final showEdit =
            topic.canEditTags &&
            constraints.maxWidth >=
                labelWidth(overflowLabel(0)) + editWidth + gap;
        final budget = math.max(
          0.0,
          constraints.maxWidth - (showEdit ? editWidth + gap : 0),
        );
        final widths = [
          for (final tag in tags.take(3))
            math.min(
              tags.length == 1 ? math.min(148.0, budget) : 148.0,
              labelWidth('# ${tag.name}'),
            ),
        ];
        var visible = topic.canEditTags && !showEdit ? 0 : widths.length;
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
                TopicTaxonomyPickerAnchor.show<void>(
                  anchorContext: context,
                  title: 'Topic tags',
                  popoverKey: const ValueKey('topic-header-tags-popover'),
                  builder: (pickerContext, close) => _ReadOnlyTags(
                    tags: tags,
                    onTagNavigate: (tag, {newTab = false}) {
                      close(null);
                      onTagNavigate(tag, newTab: newTab);
                    },
                  ),
                ),
              );

        Widget chip(
          String label,
          Key key, {
          required String tooltip,
          TopicTag? tag,
        }) => DTooltip(
          message: tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTertiaryTapUp: tag == null
                ? null
                : (_) => onTagNavigate(tag, newTab: true),
            child: tag == null
                ? DBadge.action(
                    key: key,
                    variant: DBadgeVariant.secondary,
                    onPressed: open,
                    semanticLabel: tooltip,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                : DBadge.link(
                    key: key,
                    variant: DBadgeVariant.secondary,
                    onPressed: () => onTagNavigate(tag),
                    semanticLabel: tooltip,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                  tooltip: 'Open tag ${tags[index].name}',
                  tag: tags[index],
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
            if (showEdit) ...[
              if (tags.isNotEmpty) const SizedBox(width: gap),
              DPopoverTrigger(
                builder: (context, trigger) => DButton.iconOnly(
                  key: const ValueKey('topic-header-edit-tags'),
                  icon: const DIcon(DIcons.pencil, size: 14),
                  tooltip: 'Add or remove topic tags',
                  onPressed: edit == null
                      ? null
                      : trigger.open
                      ? trigger.closePopover
                      : edit,
                  focusNode: trigger.focusNode,
                  expanded: trigger.open,
                  hasPopup: true,
                  loading: saving,
                  loadingSemanticLabel: 'Saving tags',
                  variant: DButtonVariant.ghost,
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
  const _ReadOnlyTags({required this.tags, required this.onTagNavigate});

  final List<TopicTag> tags;
  final TopicTagNavigationCallback onTagNavigate;

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
    return TopicTaxonomyPickerContent(
      queryKey: const ValueKey('topic-header-tags-search'),
      queryController: _query,
      queryHint: 'Find a topic tag',
      onQueryChanged: (_) => setState(() {}),
      onQuerySubmitted: (_) {},
      children: [
        for (final tag in matches)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTertiaryTapUp: (_) => widget.onTagNavigate(tag, newTab: true),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: DItem(
                key: ValueKey(('topic-header-tag-option', tag.name)),
                size: DItemSize.xs,
                link: true,
                children: [
                  DItemContent(children: [Text('# ${tag.name}')]),
                  const DItemActions(
                    children: [DIcon(DIcons.upRightFromSquare, size: 12)],
                  ),
                ],
                onPressed: () => widget.onTagNavigate(tag),
              ),
            ),
          ),
        if (matches.isEmpty)
          const TopicTaxonomyPickerMessage('No matching tags'),
      ],
    );
  }
}
