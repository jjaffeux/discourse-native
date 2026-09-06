import 'dart:async';

import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../plugin_api/plugin_registry.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_picker.dart';
import 'category_icon.dart';
import 'shell_scope.dart';
import 'title_bar.dart';
import 'topic_actions.dart';
import 'topic_category_picker.dart';
import 'topic_tag_picker.dart';
import 'topic_taxonomy_fields.dart';
import 'topic_title.dart';
import 'user_menu_button.dart';

class TopicInboxHeader extends StatelessWidget {
  const TopicInboxHeader({
    super.key,
    required this.title,
    required this.siteUrl,
    required this.canReturnToSidebar,
    required this.keepTopicListOpen,
    required this.registry,
    this.route,
    this.topic,
    this.isConnected = false,
    this.bookmarkBusy = false,
  });

  final String title;
  final String? siteUrl;
  final bool canReturnToSidebar;
  final bool keepTopicListOpen;
  final PluginRegistry registry;
  final ContentRoute? route;
  final TopicDetail? topic;
  final bool isConnected;
  final bool bookmarkBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.read(context);
    final topic = this.topic;
    final siteUrl = this.siteUrl;
    final titleStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );
    return DecoratedBox(
      key: const ValueKey('topic-content-header'),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.shell.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                DButton.iconOnly(
                  key: const ValueKey('topic-close-reader'),
                  icon: const DIcon(DIcons.arrowLeft, size: 16),
                  tooltip: 'Back to topics',
                  variant: DButtonVariant.flat,
                  size: DButtonSize.small,
                  onPressed: () {
                    if (controller.topicListContent != null) {
                      controller.closeTopicListReader();
                    } else {
                      controller.handleBack(
                        canReturnToSidebar: canReturnToSidebar,
                      );
                    }
                  },
                ),
                const SizedBox(width: 6),
                Text(
                  'Topic',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (topic != null && siteUrl != null) ...[
                  TopicStatusButton(
                    siteUrl: siteUrl,
                    topic: topic,
                    topicFlags: controller.availableTopicFlagTypes(
                      siteUrl,
                      topic,
                    ),
                  ),
                  TopicShareButton(
                    siteUrl: siteUrl,
                    topic: topic,
                    route: route,
                  ),
                  if (controller.currentInstance?.user != null)
                    TopicBookmarkButton(
                      siteUrl: siteUrl,
                      topic: topic,
                      busy: bookmarkBusy,
                    ),
                  if (isConnected)
                    TopicNotificationLevelButton(
                      siteUrl: siteUrl,
                      topic: topic,
                    ),
                ],
                if (ShellTitleBar.columnsCarryUserMenu) const UserMenuButton(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (topic != null && siteUrl != null) ...[
                  _TopicHeaderTaxonomy(
                    siteUrl: siteUrl,
                    topic: topic,
                    keepTopicListOpen: keepTopicListOpen,
                  ),
                  const SizedBox(height: 12),
                ],
                if (topic?.canEdit == true && siteUrl != null)
                  InlineTopicTitleEditor(
                    key: const ValueKey('topic-header-title'),
                    title: title,
                    siteUrl: siteUrl,
                    style: titleStyle,
                    maxLines: 3,
                    onSave: (value) => controller.saveTopicTitle(
                      siteUrl: siteUrl,
                      topicId: topic!.id,
                      title: value,
                    ),
                  )
                else if (siteUrl != null)
                  TopicTitle(
                    title,
                    siteUrl: siteUrl,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                    key: const ValueKey('topic-header-title'),
                  )
                else
                  Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                if (topic != null && siteUrl != null)
                  _TopicHeaderProperties(
                    siteUrl: siteUrl,
                    topic: topic,
                    registry: registry,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicHeaderTaxonomy extends StatelessWidget {
  const _TopicHeaderTaxonomy({
    required this.siteUrl,
    required this.topic,
    required this.keepTopicListOpen,
  });
  final String siteUrl;
  final TopicDetail topic;
  final bool keepTopicListOpen;

  @override
  Widget build(BuildContext context) => ShellSelector<Object>(
    select: (controller) => controller.presentationTokenFor(siteUrl),
    builder: (context, _, _) {
      final shell = ShellScope.read(context);
      final category = shell.categoryFor(topic.categoryId, siteUrl: siteUrl);
      final parent = shell.categoryFor(
        category?.parentCategoryId,
        siteUrl: siteUrl,
      );
      final root = parent ?? category;
      final uncategorized =
          shell.siteConfigFor(siteUrl).allowUncategorizedTopics
          ? shell
                .filterCategoriesFor(siteUrl)
                .where((item) => item.isUncategorized)
                .firstOrNull
          : null;
      Widget categoryControl(
        TopicCategory? value, {
        required bool subcategory,
      }) => TopicCategoryMenuAnchor(
        siteUrl: siteUrl,
        topicId: topic.id,
        categoryId: topic.categoryId,
        selectedCategoryId: value?.id,
        enabled: topic.canEdit,
        rootOnly: !subcategory,
        parentCategoryId: subcategory ? root?.id : null,
        removeCategoryId: subcategory ? root?.id : uncategorized?.id,
        removeLabel: subcategory
            ? 'Remove subcategory'
            : 'Move to Uncategorized',
        builder: (context, edit, saving) => _CategoryChip(
          category: value,
          siteUrl: siteUrl,
          label: value?.name ?? (subcategory ? 'Subcategory' : 'Category'),
          edit: edit,
          saving: saving,
          editLabel: subcategory
              ? 'Edit topic subcategory'
              : 'Edit topic category',
          navigate: value == null
              ? null
              : () => shell.browseTopicCategory(
                  value,
                  keepTopicOpen: keepTopicListOpen,
                ),
        ),
      );
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (!topic.privateMessage) ...[
            categoryControl(root, subcategory: false),
            if (parent != null ||
                (root != null &&
                    topic.canEdit &&
                    shell
                        .filterCategoriesFor(siteUrl)
                        .any((item) => item.parentCategoryId == root.id)))
              categoryControl(
                parent == null ? null : category,
                subcategory: true,
              ),
          ],
          if (topic.tags.isNotEmpty || topic.canEditTags)
            TopicTagMenuAnchor(
              siteUrl: siteUrl,
              topicId: topic.id,
              categoryId: topic.categoryId,
              tags: topic.tags,
              enabled: topic.canEditTags,
              builder: (context, edit, saving) => TopicTagsValue(
                tags: topic.tags,
                onTap: edit,
                saving: saving,
                tagKey: (tag) => ValueKey(('topic-header-tag', tag.name)),
                addKey: const ValueKey('topic-header-add-tag'),
              ),
            ),
        ],
      );
    },
  );
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.siteUrl,
    required this.label,
    required this.editLabel,
    required this.edit,
    required this.navigate,
    required this.saving,
  });
  final TopicCategory? category;
  final String siteUrl;
  final String label;
  final String editLabel;
  final VoidCallback? edit;
  final VoidCallback? navigate;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = category == null
        ? theme.colorScheme.onSurfaceVariant
        : Color(category!.colorValue);
    return Material(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: edit == null ? label : editLabel,
            child: InkWell(
              onTap: edit,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (category != null) ...[
                      CategoryIcon(
                        category: category!,
                        siteUrl: siteUrl,
                        size: 12,
                        squareSize: 9,
                      ),
                      const SizedBox(width: 6),
                    ],
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    if (saving) ...[
                      const SizedBox(width: 6),
                      const SizedBox.square(
                        dimension: 12,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (navigate != null)
            DButton.iconOnly(
              key: ValueKey('topic-header-browse-category-${category!.id}'),
              icon: const DIcon(DIcons.upRightFromSquare, size: 11),
              tooltip: 'Browse ${category!.name}',
              onPressed: navigate,
              variant: DButtonVariant.flat,
              size: DButtonSize.small,
            ),
        ],
      ),
    );
  }
}

class _TopicHeaderProperties extends StatelessWidget {
  const _TopicHeaderProperties({
    required this.siteUrl,
    required this.topic,
    required this.registry,
  });
  final String siteUrl;
  final TopicDetail topic;
  final PluginRegistry registry;

  @override
  Widget build(BuildContext context) {
    Widget properties() {
      final sections = registry.topicProperties(context, siteUrl, topic);
      if (sections.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final section in sections)
              Builder(
                builder: (anchorContext) {
                  void showDetails() => unawaited(
                    showAnchoredPicker<void>(
                      context: context,
                      anchorContext: anchorContext,
                      title: section.label,
                      barrierLabel: 'Dismiss ${section.label}',
                      popoverKey: ValueKey((
                        'topic-header-property',
                        section.label,
                      )),
                      builder: (_) => _TopicPropertyDetails(
                        siteUrl: siteUrl,
                        topicId: topic.id,
                        label: section.label,
                        registry: registry,
                        navigationRevision: ShellScope.read(
                          context,
                        ).topicNavigationRevision,
                      ),
                    ),
                  );
                  return section.header?.call(anchorContext, showDetails) ??
                      DButton(
                        label: Text(section.label),
                        size: DButtonSize.small,
                        onPressed: showDetails,
                      );
                },
              ),
          ],
        ),
      );
    }

    final rebuildOn = registry.topicPropertiesRebuildOn(
      context,
      siteUrl,
      topic,
    );
    return rebuildOn == null
        ? properties()
        : ListenableBuilder(
            listenable: rebuildOn,
            builder: (_, _) => properties(),
          );
  }
}

class _TopicPropertyDetails extends StatelessWidget {
  const _TopicPropertyDetails({
    required this.siteUrl,
    required this.topicId,
    required this.label,
    required this.registry,
    required this.navigationRevision,
  });
  final String siteUrl;
  final int topicId;
  final String label;
  final PluginRegistry registry;
  final int navigationRevision;

  @override
  Widget build(BuildContext context) => ShellSelector<(String?, int?, int)>(
    select: (shell) => (
      shell.currentInstance?.url,
      shell.currentContent?.topicId,
      shell.topicNavigationRevision,
    ),
    builder: (context, navigation, _) {
      if (navigation != (siteUrl, topicId, navigationRevision)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
            Navigator.of(context).pop();
          }
        });
      }
      return ValueListenableBuilder<TopicDetail?>(
        valueListenable: ShellScope.read(
          context,
        ).store.ref<TopicDetail>(siteUrl, topicId),
        builder: (context, topic, _) {
          if (topic == null) return const SizedBox.shrink();
          Widget details() {
            final section = registry
                .topicProperties(context, siteUrl, topic)
                .where((section) => section.label == label)
                .firstOrNull;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: section?.values ?? const [Text('None')],
              ),
            );
          }

          final rebuildOn = registry.topicPropertiesRebuildOn(
            context,
            siteUrl,
            topic,
          );
          return rebuildOn == null
              ? details()
              : ListenableBuilder(
                  listenable: rebuildOn,
                  builder: (_, _) => details(),
                );
        },
      );
    },
  );
}
