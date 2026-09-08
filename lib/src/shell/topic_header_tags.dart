import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../discourse_ui.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_picker.dart';
import 'topic_tag_picker.dart';
import 'topic_taxonomy_fields.dart';

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
              ? TopicTagsValue(
                  tags: tags,
                  saving: saving,
                  onEdit: edit,
                  addKey: const ValueKey('topic-header-edit-tags'),
                )
              : const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        final style = theme.textTheme.labelSmall;
        const gap = 7.0;
        double labelWidth(String label) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: DDirection.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final width = painter.width.ceilToDouble() + 14;
          painter.dispose();
          return width;
        }

        String overflowLabel(int visible) => visible == 0
            ? 'Tags · ${tags.length}'
            : '+${tags.length - visible}';
        // The overflow editor keeps editing available in narrow readers.
        final showEdit =
            topic.canEditTags &&
            constraints.maxWidth >= labelWidth(overflowLabel(0)) + 35;
        final budget = math.max(
          0.0,
          constraints.maxWidth - (showEdit ? 28 + gap : 0),
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
                  builder: (pickerContext) => _ReadOnlyTags(
                    tags: tags,
                    onTagNavigate: (tag, {newTab = false}) {
                      Navigator.of(pickerContext).pop();
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
        }) => Tooltip(
          message: tooltip,
          child: Material(
            color: theme.shell.hover,
            borderRadius: BorderRadius.circular(4),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTertiaryTapUp: tag == null
                  ? null
                  : (_) => onTagNavigate(tag, newTab: true),
              child: Semantics(
                link: tag != null,
                button: tag == null,
                child: InkWell(
                  key: key,
                  onTap: tag == null ? open : () => onTagNavigate(tag),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 5,
                    ),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(
                        label,
                        style: style,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
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
              SizedBox.square(
                dimension: 28,
                child: saving
                    ? const Padding(
                        padding: EdgeInsets.all(6),
                        child: DSpinner(strokeWidth: 1.5),
                      )
                    : DButton.iconOnly(
                        key: const ValueKey('topic-header-edit-tags'),
                        icon: const DIcon(DIcons.pencil, size: 14),
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
    return AnchoredPickerContent(
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
              child: AnchoredPickerOption(
                key: ValueKey(('topic-header-tag-option', tag.name)),
                title: Text('# ${tag.name}'),
                trailing: const DIcon(DIcons.upRightFromSquare, size: 12),
                onTap: () => widget.onTagNavigate(tag),
              ),
            ),
          ),
        if (matches.isEmpty) const AnchoredPickerMessage('No matching tags'),
      ],
    );
  }
}
