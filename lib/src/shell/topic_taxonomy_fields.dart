import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'inline_action.dart';

/// A labelled topic property shared by the composer and topic sidebar.
class TopicPropertyRow extends StatelessWidget {
  const TopicPropertyRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 94,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A topic category value shared by the composer and topic sidebar.
class TopicCategoryValue extends StatelessWidget {
  const TopicCategoryValue({
    super.key,
    required this.label,
    required this.color,
    this.valueKey,
    this.colorKey,
    this.actionKey,
    this.saving = false,
    this.onTap,
    this.tooltip = 'Edit topic category',
  });

  final String label;
  final Color? color;
  final Key? valueKey;
  final Key? colorKey;
  final Key? actionKey;
  final bool saving;
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = Row(
      key: valueKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: colorKey,
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color ?? theme.colorScheme.outline,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (saving) ...[
          const SizedBox(width: 7),
          const SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator.adaptive(strokeWidth: 2),
          ),
        ],
      ],
    );
    if (onTap == null) return category;
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: tooltip,
        child: InlineAction(
          key: actionKey,
          onTap: onTap!,
          borderRadius: BorderRadius.circular(5),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: category,
          ),
        ),
      ),
    );
  }
}

/// Tag pills and their editing affordance, shared by topic metadata surfaces.
class TopicTagsValue extends StatelessWidget {
  const TopicTagsValue({
    super.key,
    required this.tags,
    this.saving = false,
    this.onTap,
    this.tagKey,
    this.addKey,
    this.addIconKey,
    this.emptyLabel = 'No tags',
    this.editTooltip = 'Edit topic tags',
  });

  final List<TopicTag> tags;
  final bool saving;
  final VoidCallback? onTap;
  final Key? Function(TopicTag tag)? tagKey;
  final Key? addKey;
  final Key? addIconKey;
  final String emptyLabel;
  final String editTooltip;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return onTap == null
          ? _EmptyTopicProperty(emptyLabel)
          : _EditableEmptyTopicTags(
              actionKey: addKey,
              saving: saving,
              onTap: onTap,
            );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tag in tags)
          _TopicTagPill(
            pillKey: tagKey?.call(tag),
            tag: tag,
            onTap: onTap,
            tooltip: editTooltip,
          ),
        if (saving)
          const _TopicTagsSavingIndicator()
        else if (onTap != null)
          _TopicTagsAddButton(
            actionKey: addKey,
            iconKey: addIconKey,
            onTap: onTap,
          ),
      ],
    );
  }
}

class _TopicTagPill extends StatelessWidget {
  const _TopicTagPill({
    required this.pillKey,
    required this.tag,
    required this.tooltip,
    this.onTap,
  });

  final Key? pillKey;
  final TopicTag tag;
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = StadiumBorder(
      side: BorderSide(color: theme.colorScheme.outlineVariant),
    );
    final pill = Material(
      key: pillKey,
      color: theme.colorScheme.surfaceContainerHigh,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        mouseCursor: onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        customBorder: shape,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              tag.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
    return onTap == null ? pill : Tooltip(message: tooltip, child: pill);
  }
}

class _EditableEmptyTopicTags extends StatelessWidget {
  const _EditableEmptyTopicTags({
    required this.actionKey,
    required this.saving,
    required this.onTap,
  });

  final Key? actionKey;
  final bool saving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    const shape = StadiumBorder();
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Tooltip(
          message: saving ? 'Saving topic tags' : 'Add tag',
          child: Material(
            color: theme.colorScheme.surfaceContainerHigh,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: actionKey,
              onTap: onTap,
              mouseCursor: onTap == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.click,
              customBorder: shape,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (saving)
                      const SizedBox.square(
                        dimension: 11,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    else
                      DIcon(DIcons.tag, size: 11, color: color),
                    const SizedBox(width: 4),
                    Text(
                      saving ? 'Saving…' : 'Add tag',
                      style: theme.textTheme.labelSmall?.copyWith(color: color),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicTagsAddButton extends StatelessWidget {
  const _TopicTagsAddButton({
    required this.actionKey,
    required this.iconKey,
    required this.onTap,
  });

  final Key? actionKey;
  final Key? iconKey;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Add tag',
    child: Material(
      type: MaterialType.transparency,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: actionKey,
        onTap: onTap,
        mouseCursor: onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: DIcon(
            DIcons.plus,
            key: iconKey,
            size: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ),
  );
}

class _TopicTagsSavingIndicator extends StatelessWidget {
  const _TopicTagsSavingIndicator();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 13,
    child: CircularProgressIndicator(strokeWidth: 1.5),
  );
}

class _EmptyTopicProperty extends StatelessWidget {
  const _EmptyTopicProperty(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
