import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'category_icon.dart';
import 'inline_action.dart';

class TopicPropertyRow extends StatelessWidget {
  const TopicPropertyRow({
    super.key,
    required this.label,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  final String label;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
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

class TopicCategoryValue extends StatelessWidget {
  const TopicCategoryValue({
    super.key,
    required this.label,
    required this.color,
    this.category,
    this.siteUrl,
    this.valueKey,
    this.colorKey,
    this.actionKey,
    this.editActionKey,
    this.editIconKey,
    this.saving = false,
    this.onTap,
    this.onNavigate,
    this.onEdit,
    this.tooltip = 'Edit topic category',
    this.navigationTooltip,
    this.editTooltip = 'Edit topic category',
  }) : assert(onTap == null || onNavigate == null);

  final String label;
  final Color? color;
  final TopicCategory? category;
  final String? siteUrl;
  final Key? valueKey;
  final Key? colorKey;
  final Key? actionKey;
  final Key? editActionKey;
  final Key? editIconKey;
  final bool saving;
  final VoidCallback? onTap;
  final VoidCallback? onNavigate;
  final VoidCallback? onEdit;
  final String tooltip;
  final String? navigationTooltip;
  final String editTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoryValue = Row(
      key: valueKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: category == null
              ? Container(
                  key: colorKey,
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: color ?? theme.colorScheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              : CategoryIcon(
                  key: colorKey,
                  category: category!,
                  siteUrl: siteUrl,
                  size: 13,
                  squareSize: 9,
                ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );

    Widget value = categoryValue;
    if (onNavigate case final onNavigate?) {
      final message = navigationTooltip ?? 'Open category $label';
      value = Tooltip(
        message: message,
        child: InlineAction.link(
          key: actionKey,
          onTap: onNavigate,
          semanticLabel: 'Category: $label',
          excludeChildSemantics: true,
          borderRadius: BorderRadius.circular(5),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              heightFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: categoryValue,
              ),
            ),
          ),
        ),
      );
    } else if (onTap case final onTap?) {
      value = Tooltip(
        message: tooltip,
        child: InlineAction(
          key: actionKey,
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: categoryValue,
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: value),
          if (saving) ...[
            const SizedBox(width: 7),
            const _TopicTaxonomySavingIndicator(dimension: 12),
          ] else if (onEdit case final onEdit?) ...[
            const SizedBox(width: 4),
            _TopicTaxonomyEditButton(
              actionKey: editActionKey,
              iconKey: editIconKey,
              tooltip: editTooltip,
              onTap: onEdit,
            ),
          ],
        ],
      ),
    );
  }
}

class TopicTagsValue extends StatelessWidget {
  const TopicTagsValue({
    super.key,
    required this.tags,
    this.saving = false,
    this.onTap,
    this.onTagNavigate,
    this.onEdit,
    this.tagKey,
    this.addKey,
    this.addIconKey,
    this.emptyLabel = 'No tags',
    this.editTooltip = 'Edit topic tags',
  });

  final List<TopicTag> tags;
  final bool saving;
  final VoidCallback? onTap;
  final ValueChanged<TopicTag>? onTagNavigate;
  final VoidCallback? onEdit;
  final Key? Function(TopicTag tag)? tagKey;
  final Key? addKey;
  final Key? addIconKey;
  final String emptyLabel;
  final String editTooltip;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      final edit = onEdit ?? onTap;
      return edit == null && !saving
          ? _EmptyTopicProperty(emptyLabel)
          : _EditableEmptyTopicTags(
              actionKey: addKey,
              saving: saving,
              onTap: edit,
            );
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tag in tags)
          _TopicTagPill(
            pillKey: tagKey?.call(tag),
            tag: tag,
            onTap: onTagNavigate == null ? onTap : () => onTagNavigate!(tag),
            isLink: onTagNavigate != null,
            semanticLabel: onTagNavigate == null ? null : 'Tag: ${tag.name}',
            tooltip: onTagNavigate == null
                ? editTooltip
                : 'Open tag ${tag.name}',
          ),
        if (saving)
          const _TopicTagsSavingIndicator()
        else if (onEdit case final onEdit?)
          _TopicTaxonomyEditButton(
            actionKey: addKey,
            iconKey: addIconKey,
            tooltip: editTooltip,
            onTap: onEdit,
          )
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
    required this.isLink,
    this.semanticLabel,
    this.onTap,
  });

  final Key? pillKey;
  final TopicTag tag;
  final VoidCallback? onTap;
  final String tooltip;
  final bool isLink;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(5),
    );
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
    );
    final pill = Material(
      key: pillKey,
      color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.72),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null || isLink
          ? content
          : InlineAction(
              onTap: onTap!,
              borderRadius: BorderRadius.circular(999),
              child: content,
            ),
    );
    if (onTap == null) return pill;

    final action = isLink
        ? InlineAction.link(
            onTap: onTap!,
            semanticLabel: semanticLabel,
            excludeChildSemantics: true,
            borderRadius: BorderRadius.circular(5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              child: Align(widthFactor: 1, heightFactor: 1, child: pill),
            ),
          )
        : pill;
    return Tooltip(message: tooltip, child: action);
  }
}

class _TopicTaxonomyEditButton extends StatelessWidget {
  const _TopicTaxonomyEditButton({
    required this.actionKey,
    required this.iconKey,
    required this.tooltip,
    required this.onTap,
  });

  final Key? actionKey;
  final Key? iconKey;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InlineAction(
      key: actionKey,
      onTap: onTap,
      semanticLabel: tooltip,
      excludeChildSemantics: true,
      borderRadius: BorderRadius.circular(999),
      child: SizedBox.square(
        dimension: 32,
        child: Center(
          child: DIcon(
            DIcons.pencil,
            key: iconKey,
            size: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ),
  );
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
  Widget build(BuildContext context) =>
      const _TopicTaxonomySavingIndicator(dimension: 13);
}

class _TopicTaxonomySavingIndicator extends StatelessWidget {
  const _TopicTaxonomySavingIndicator({required this.dimension});

  final double dimension;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: dimension,
    child: const CircularProgressIndicator.adaptive(strokeWidth: 1.5),
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
