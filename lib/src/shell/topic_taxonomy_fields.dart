import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../theme/d_icons.dart';
import 'category_icon.dart';
import 'open_link.dart';
import 'topic_tag_picker.dart';

class TopicPropertyRow extends StatelessWidget {
  const TopicPropertyRow({
    super.key,
    required this.label,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.alignLabelToControl = false,
  });

  final String label;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool alignLabelToControl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = Text(
      label,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 94,
            child: alignLabelToControl
                ? SizedBox(
                    height: 32,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: labelText,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: labelText,
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
    this.parentCategory,
    this.siteUrl,
    this.valueKey,
    this.colorKey,
    this.actionKey,
    this.parentActionKey,
    this.editActionKey,
    this.editIconKey,
    this.saving = false,
    this.onNavigate,
    this.onParentNavigate,
    this.onEdit,
  }) : assert(parentCategory != null || onParentNavigate == null);

  final String label;
  final Color? color;
  final TopicCategory? category;
  final TopicCategory? parentCategory;
  final String? siteUrl;
  final Key? valueKey;
  final Key? colorKey;
  final Key? actionKey;
  final Key? parentActionKey;
  final Key? editActionKey;
  final Key? editIconKey;
  final bool saving;
  final VoidCallback? onNavigate;
  final VoidCallback? onParentNavigate;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = this.category;
    final hasParentNavigation =
        onNavigate != null &&
        parentCategory != null &&
        onParentNavigate != null;
    final usesLargeCategoryArt =
        category?.readRestricted == true ||
        category?.styleType == 'icon' ||
        (category?.styleType == 'emoji' &&
            category?.emoji != null &&
            siteUrl != null);
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w500,
    );
    final categoryArt = category == null
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
            category: category,
            siteUrl: siteUrl,
            size: 13,
            squareSize: 9,
            showLock: !hasParentNavigation,
          );

    Widget categoryValue(String valueLabel) => Row(
      key: valueKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: usesLargeCategoryArt ? 2 : 4),
          child: categoryArt,
        ),
        const SizedBox(width: 7),
        Flexible(child: Text(valueLabel, style: labelStyle)),
      ],
    );

    Widget value = categoryValue(label);
    if (onNavigate case final onNavigate?) {
      final parentCategory = this.parentCategory;
      final onParentNavigate = this.onParentNavigate;
      if (category != null &&
          parentCategory != null &&
          onParentNavigate != null) {
        value = Row(
          key: valueKey,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 32, child: Center(child: categoryArt)),
            const SizedBox(width: 7),
            Flexible(
              child: Wrap(
                spacing: 4,
                runSpacing: 0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _TopicCategoryNavigationLink(
                    actionKey: parentActionKey,
                    label: parentCategory.name,
                    readRestricted: parentCategory.readRestricted,
                    semanticLabel: context.l10n
                        .parentCategoryTopictaxonomyfields(
                          (parentCategory.name).toString(),
                        ),
                    tooltip: context.l10n.openCategory(
                      (parentCategory.name).toString(),
                    ),
                    onTap: onParentNavigate,
                    showChevron: true,
                  ),
                  _TopicCategoryNavigationLink(
                    actionKey: actionKey,
                    label: category.name,
                    readRestricted: category.readRestricted,
                    semanticLabel: context.l10n.categoryTopiclistview(
                      (category.name).toString(),
                    ),
                    tooltip: context.l10n.openCategoryTopictaxonomyfields(
                      (category.name).toString(),
                    ),
                    onTap: onNavigate,
                  ),
                ],
              ),
            ),
          ],
        );
      } else {
        final message = context.l10n.openCategoryTopictaxonomyfieldsValue(
          (label).toString(),
        );
        value = DTooltip(
          message: message,
          child: DItem(
            key: actionKey,
            fitContent: true,
            size: DItemSize.artwork,
            highlightOnInteraction: false,
            link: true,
            onPressed: onNavigate,
            semanticLabel: context.l10n.categoryTopictaxonomyfields(
              (label).toString(),
            ),
            children: [
              ExcludeSemantics(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: categoryValue(label),
                  ),
                ),
              ),
            ],
          ),
        );
      }
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
              tooltip: appL10n.editTopicCategory,
              onTap: onEdit,
            ),
          ],
        ],
      ),
    );
  }
}

class _TopicCategoryNavigationLink extends StatelessWidget {
  const _TopicCategoryNavigationLink({
    required this.actionKey,
    required this.label,
    required this.semanticLabel,
    required this.tooltip,
    required this.onTap,
    required this.readRestricted,
    this.showChevron = false,
  });

  final Key? actionKey;
  final String label;
  final String semanticLabel;
  final String tooltip;
  final VoidCallback onTap;
  final bool readRestricted;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DTooltip(
      message: tooltip,
      child: DItem(
        key: actionKey,
        fitContent: true,
        size: DItemSize.artwork,
        highlightOnInteraction: false,
        link: true,
        onPressed: onTap,
        semanticLabel: semanticLabel,
        children: [
          ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (readRestricted) ...[
                  DIcon(
                    DIcons.lock,
                    size: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (showChevron) ...[
                  const SizedBox(width: 4),
                  DIcon(
                    DIcons.chevronRight,
                    size: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
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
    this.onTagNavigate,
    this.onEdit,
    this.tagKey,
    this.addKey,
    this.addIconKey,
  });

  final List<TopicTag> tags;
  final bool saving;
  final TopicTagNavigationCallback? onTagNavigate;
  final VoidCallback? onEdit;
  final Key? Function(TopicTag tag)? tagKey;
  final Key? addKey;
  final Key? addIconKey;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return onEdit == null && !saving
          ? _EmptyTopicProperty(appL10n.noTags)
          : _EditableEmptyTopicTags(
              actionKey: addKey,
              saving: saving,
              onTap: onEdit,
            );
    }

    Widget pill(TopicTag tag) {
      final built = _TopicTagPill(
        pillKey: tagKey?.call(tag),
        tag: tag,
        onTap: onTagNavigate == null ? null : () => onTagNavigate!(tag),
        semanticLabel: onTagNavigate == null
            ? null
            : context.l10n.tag((tag.name).toString()),
      );
      return onTagNavigate == null
          ? built
          : LinkTarget.action(
              action: ({required newTab, panel}) =>
                  onTagNavigate!(tag, newTab: newTab, panel: panel),
              child: built,
            );
    }

    final pills = [for (final tag in tags) pill(tag)];
    final Widget? trailingAction;
    if (saving) {
      trailingAction = const _TopicTagsSavingIndicator();
    } else if (onEdit case final onEdit?) {
      trailingAction = _TopicTaxonomyEditButton(
        actionKey: addKey,
        iconKey: addIconKey,
        compact: true,
        tooltip: appL10n.editTopicTagsPostactions,
        onTap: onEdit,
      );
    } else {
      trailingAction = null;
    }

    return Wrap(
      spacing: 4,
      runSpacing: 0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: trailingAction == null
          ? pills
          : [
              ...pills.take(pills.length - 1),
              _TopicTagTrailingAction(tag: pills.last, action: trailingAction),
            ],
    );
  }
}

class _TopicTagTrailingAction extends StatelessWidget {
  const _TopicTagTrailingAction({required this.tag, required this.action});

  final Widget tag;
  final Widget action;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(child: tag),
      const SizedBox(width: 4),
      action,
    ],
  );
}

class _TopicTagPill extends StatelessWidget {
  const _TopicTagPill({
    required this.pillKey,
    required this.tag,
    this.semanticLabel,
    this.onTap,
  });

  final Key? pillKey;
  final TopicTag tag;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final label = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Text(tag.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    if (onTap == null) {
      return DBadge(
        key: pillKey,
        variant: DBadgeVariant.secondary,
        size: DBadgeSize.compact,
        child: label,
      );
    }
    return DBadge.link(
      key: pillKey,
      variant: DBadgeVariant.secondary,
      size: DBadgeSize.compact,
      semanticLabel: semanticLabel,
      onPressed: onTap,
      child: label,
    );
  }
}

class _TopicTaxonomyEditButton extends StatelessWidget {
  const _TopicTaxonomyEditButton({
    required this.actionKey,
    required this.iconKey,
    required this.tooltip,
    required this.onTap,
    this.compact = false,
  });

  final Key? actionKey;
  final Key? iconKey;
  final String tooltip;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => DButton.iconOnly(
    key: actionKey,
    tooltip: tooltip,
    variant: DButtonVariant.ghost,
    size: compact ? DButtonSize.chip : DButtonSize.regular,
    shape: DButtonShape.pill,
    onPressed: onTap,
    icon: DIcon(DIcons.pencil, key: iconKey),
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
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: DButton(
      key: actionKey,
      tooltip: saving ? context.l10n.savingTopicTags : context.l10n.addTag,
      semanticLabel: saving
          ? context.l10n.savingTopicTags
          : context.l10n.addTag,
      onPressed: onTap,
      loading: saving,
      variant: DButtonVariant.inline,
      density: DButtonDensity.inlineMetadata,
      icon: const DIcon(DIcons.tag),
      label: Text(saving ? context.l10n.saving : context.l10n.addTag),
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
    child: const DSpinner(strokeWidth: 1.5),
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
