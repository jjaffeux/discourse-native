import 'dart:async';

import 'package:discourse_native/discourse_ui.dart' show DAvatar;

import 'package:flutter/material.dart';

import '../foundation/frame_safe_notifier.dart';
import '../models/content_route.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../plugin_api/plugin_registry.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import 'anchored_picker.dart';
import 'avatar_image.dart';
import 'category_icon.dart';
import 'content_reading_lane.dart';
import 'open_link.dart';
import 'relative_time.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'title_bar.dart';
import 'topic_actions.dart';
import 'topic_category_picker.dart';
import 'topic_header_tags.dart';
import 'topic_list_layout.dart';
import 'topic_title.dart';
import 'user_menu_button.dart';

class TopicInboxHeader extends StatefulWidget {
  const TopicInboxHeader({
    super.key,
    required this.title,
    required this.siteUrl,
    required this.canReturnToSidebar,
    required this.keepTopicListOpen,
    required this.registry,
    this.route,
    this.topic,
    this.scrollController,
    this.hasEarlierPosts = false,
  });

  final String title;
  final String? siteUrl;
  final bool canReturnToSidebar;
  final bool keepTopicListOpen;
  final PluginRegistry registry;
  final ContentRoute? route;
  final TopicDetail? topic;
  final ScrollController? scrollController;
  final bool hasEarlierPosts;

  @override
  State<TopicInboxHeader> createState() => _TopicInboxHeaderState();
}

class _TopicInboxHeaderState extends State<TopicInboxHeader> {
  final _compact = FrameSafeValueNotifier(false);
  bool _editingTitle = false;

  @override
  void initState() {
    super.initState();
    _updateCompact();
    widget.scrollController?.addListener(_updateCompact);
    _updateAfterLayout();
  }

  @override
  void didUpdateWidget(TopicInboxHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_updateCompact);
      widget.scrollController?.addListener(_updateCompact);
    }
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.topic?.id != widget.topic?.id ||
        oldWidget.scrollController != widget.scrollController) {
      _editingTitle = false;
      _compact.value = false;
    }
    _updateAfterLayout();
  }

  void _updateAfterLayout() =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateCompact();
      });

  void _updateCompact() {
    final scroll = widget.scrollController;
    final offset = scroll != null && scroll.hasClients
        ? scroll.offset - scroll.position.minScrollExtent
        : 0.0;
    _compact.value =
        widget.topic != null &&
        widget.siteUrl != null &&
        !_editingTitle &&
        (widget.hasEarlierPosts || offset > (_compact.value ? 18 : 82));
  }

  void _titleEditingChanged(bool editing) {
    _editingTitle = editing;
    _updateCompact();
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_updateCompact);
    _compact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 380);
    return DecoratedBox(
      key: const ValueKey('topic-content-header'),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).shell.divider),
        ),
      ),
      child: ValueListenableBuilder<bool>(
        valueListenable: _compact,
        builder: (context, compact, _) => AnimatedSize(
          duration: duration,
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          // Preserve hover, focus, and open menus across header modes.
          child: _TopicHeaderToolbar(
            header: widget,
            compact: compact,
            duration: duration,
            autofocusTitle: _editingTitle,
            onTitleEditingChanged: _titleEditingChanged,
            onEditTitle: widget.topic?.canEdit == true
                ? () => _titleEditingChanged(true)
                : null,
          ),
        ),
      ),
    );
  }
}

class _TopicHeaderTransition extends StatelessWidget {
  const _TopicHeaderTransition({required this.duration, required this.child});

  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: duration,
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.topCenter,
      fit: StackFit.passthrough,
      children: [
        for (final child in previous)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ExcludeFocus(
              child: ExcludeSemantics(child: IgnorePointer(child: child)),
            ),
          ),
        ?current,
      ],
    ),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: child.key == const ValueKey('topic-header-compact')
              ? const Offset(.025, 0)
              : const Offset(0, -.06),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: child,
  );
}

class _TopicHeaderToolbar extends StatelessWidget {
  const _TopicHeaderToolbar({
    required this.header,
    required this.compact,
    required this.duration,
    required this.autofocusTitle,
    required this.onTitleEditingChanged,
    required this.onEditTitle,
  });

  final TopicInboxHeader header;
  final bool compact;
  final Duration duration;
  final bool autofocusTitle;
  final ValueChanged<bool> onTitleEditingChanged;
  final VoidCallback? onEditTitle;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final topic = header.topic;
      final siteUrl = header.siteUrl;
      final lane = ContentReadingLane.geometryFor(
        context,
        availableWidth: constraints.maxWidth,
        basePadding: const EdgeInsets.symmetric(horizontal: 12),
      );
      final leadingPadding = header.keepTopicListOpen
          ? topicInboxDividerInset
          : 16.0;
      final actionDimension = DButton.iconOnlyDimensionFor(DButtonSize.small);
      final toolbarStart = leadingPadding + actionDimension;
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: shellHeaderHeight),
        child: Padding(
          padding: EdgeInsets.only(left: leadingPadding, right: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Wrapped titles grow below the fixed toolbar controls.
              SizedBox(
                height: shellHeaderHeight,
                child: Center(
                  widthFactor: 1,
                  child: _TopicCloseButton(
                    canReturnToSidebar: header.canReturnToSidebar,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: (lane.padding.left + 16 - toolbarStart).clamp(
                      8,
                      double.infinity,
                    ),
                    right: 8,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: shellHeaderHeight,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      heightFactor: 1,
                      child: SizedBox(
                        width: lane.width - 32,
                        child: _TopicHeaderTransition(
                          duration: duration,
                          child: compact
                              ? _CompactTopicInboxHeader(
                                  key: const ValueKey('topic-header-compact'),
                                  header: header,
                                  onEditTitle: onEditTitle,
                                )
                              : _ExpandedTopicInboxHeader(
                                  key: ValueKey((
                                    'topic-header-expanded',
                                    siteUrl,
                                    topic?.id,
                                  )),
                                  header: header,
                                  autofocusTitle: autofocusTitle,
                                  onTitleEditingChanged: onTitleEditingChanged,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: shellHeaderHeight,
                child: Center(
                  widthFactor: 1,
                  child: _TopicHeaderActions(
                    header: header,
                    width: constraints.maxWidth,
                    compact: compact,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ExpandedTopicHeaderTitle extends StatelessWidget {
  const _ExpandedTopicHeaderTitle({
    required this.header,
    required this.autofocus,
    required this.onEditingChanged,
  });

  final TopicInboxHeader header;
  final bool autofocus;
  final ValueChanged<bool> onEditingChanged;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    final topic = header.topic;
    final siteUrl = header.siteUrl;
    final title = header.title;
    final titleStyle = Theme.of(
      context,
    ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      // Leave room for the title's editing frame even when it wraps.
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: topic?.canEdit == true && siteUrl != null
          ? InlineTopicTitleEditor(
              key: const ValueKey('topic-header-title'),
              title: title,
              siteUrl: siteUrl,
              style: titleStyle,
              maxLines: 3,
              showEditingFrame: true,
              autofocus: autofocus,
              onEditingChanged: onEditingChanged,
              onSave: (value) => controller.saveTopicTitle(
                siteUrl: siteUrl,
                topicId: topic!.id,
                title: value,
              ),
            )
          : siteUrl != null
          ? TopicTitle(
              title,
              siteUrl: siteUrl,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
              key: const ValueKey('topic-header-title'),
            )
          : Text(
              title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
    );
  }
}

class _ExpandedTopicInboxHeader extends StatelessWidget {
  const _ExpandedTopicInboxHeader({
    super.key,
    required this.header,
    required this.autofocusTitle,
    required this.onTitleEditingChanged,
  });

  final TopicInboxHeader header;
  final bool autofocusTitle;
  final ValueChanged<bool> onTitleEditingChanged;

  @override
  Widget build(BuildContext context) {
    final topic = header.topic;
    final siteUrl = header.siteUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: shellHeaderHeight),
          child: Align(
            alignment: Alignment.centerLeft,
            heightFactor: 1,
            child: _ExpandedTopicHeaderTitle(
              header: header,
              autofocus: autofocusTitle,
              onEditingChanged: onTitleEditingChanged,
            ),
          ),
        ),
        if (topic != null && siteUrl != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _TopicHeaderTaxonomy(
              siteUrl: siteUrl,
              topic: topic,
              keepTopicListOpen: header.keepTopicListOpen,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final summary = _TopicActivitySummary(
                  siteUrl: siteUrl,
                  topic: topic,
                );
                final properties = _TopicHeaderProperties(
                  siteUrl: siteUrl,
                  topic: topic,
                  registry: header.registry,
                );
                return constraints.maxWidth >= 560
                    ? Row(
                        children: [
                          Expanded(child: summary),
                          const SizedBox(width: 12),
                          Expanded(child: properties),
                        ],
                      )
                    : Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [summary, properties],
                      );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _CompactTopicHeaderTitle extends StatelessWidget {
  const _CompactTopicHeaderTitle({required this.header, required this.onEdit});

  final TopicInboxHeader header;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: header.title,
    child: Semantics(
      button: onEdit != null,
      hint: onEdit != null ? 'Edit topic title' : null,
      child: InkWell(
        onTap: onEdit,
        mouseCursor: onEdit != null
            ? SystemMouseCursors.text
            : SystemMouseCursors.basic,
        borderRadius: BorderRadius.circular(4),
        child: TopicTitle(
          header.title,
          key: const ValueKey('topic-header-compact-title'),
          siteUrl: header.siteUrl!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}

class _CompactTopicInboxHeader extends StatelessWidget {
  const _CompactTopicInboxHeader({
    super.key,
    required this.header,
    required this.onEditTitle,
  });

  final TopicInboxHeader header;
  final VoidCallback? onEditTitle;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final topic = header.topic!;
      final siteUrl = header.siteUrl!;
      final controller = ShellScope.read(context);
      final titleStyle = Theme.of(context).textTheme.titleSmall;
      final titleHeight =
          MediaQuery.textScalerOf(
            context,
          ).scale(titleStyle?.fontSize ?? DiscourseTypography.base) *
          (titleStyle?.height ?? DiscourseTypography.lineHeightMedium);
      // Retain the title's toolbar inset and use it below the taxonomy too.
      final verticalPadding = ((shellHeaderHeight - titleHeight) / 2).clamp(
        0.0,
        double.infinity,
      );
      return Padding(
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _CompactTopicHeaderTitle(header: header, onEdit: onEditTitle),
            if (!topic.privateMessage ||
                topic.tags.isNotEmpty ||
                topic.canEditTags) ...[
              const SizedBox(height: 8),
              Row(
                key: const ValueKey('topic-header-compact-taxonomy'),
                children: [
                  if (!topic.privateMessage)
                    _CompactTopicCategories(
                      siteUrl: siteUrl,
                      topic: topic,
                      keepTopicListOpen: header.keepTopicListOpen,
                      maxWidth: (constraints.maxWidth * .5).clamp(128, 400),
                    ),
                  if (topic.tags.isNotEmpty || topic.canEditTags)
                    Flexible(
                      child: TopicHeaderTags(
                        key: const ValueKey('topic-header-compact-tags'),
                        siteUrl: siteUrl,
                        topic: topic,
                        onTagNavigate: (tag, {newTab = false}) =>
                            controller.openTopicTag(
                              tag,
                              siteUrl: siteUrl,
                              privateMessage: topic.privateMessage,
                              newTab: newTab,
                            ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _TopicHeaderActions extends StatelessWidget {
  const _TopicHeaderActions({
    required this.header,
    required this.width,
    this.compact = false,
  });

  final TopicInboxHeader header;
  final double width;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final topic = header.topic;
    final siteUrl = header.siteUrl;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (compact && topic != null && siteUrl != null)
          _TopicHeaderProperties(
            siteUrl: siteUrl,
            topic: topic,
            registry: header.registry,
            compact: true,
          ),
        Row(
          key: const ValueKey('topic-header-common-actions'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (header.keepTopicListOpen && width >= 640)
              const _TopicInboxNavigation(),
            if (topic != null && siteUrl != null) ...[
              TopicStatusButton(
                siteUrl: siteUrl,
                topic: topic,
                topicFlags: ShellScope.read(
                  context,
                ).availableTopicFlagTypes(siteUrl, topic),
              ),
              if (width >= 440)
                TopicShareButton(
                  siteUrl: siteUrl,
                  topic: topic,
                  route: header.route,
                ),
            ],
            if (ShellTitleBar.columnsCarryUserMenu) const UserMenuButton(),
          ],
        ),
      ],
    );
  }
}

class _TopicCloseButton extends StatelessWidget {
  const _TopicCloseButton({required this.canReturnToSidebar});

  final bool canReturnToSidebar;

  @override
  Widget build(BuildContext context) => DButton.iconOnly(
    key: const ValueKey('topic-close-reader'),
    icon: const DIcon(DNativeIcons.closeTopicPane, size: 20),
    tooltip: 'Collapse topic',
    variant: DButtonVariant.flat,
    size: DButtonSize.small,
    onPressed: () {
      final controller = ShellScope.read(context);
      if (controller.topicListContent != null) {
        controller.closeTopicListReader();
      } else {
        controller.handleBack(canReturnToSidebar: canReturnToSidebar);
      }
    },
  );
}

class _CompactTopicCategories extends StatelessWidget {
  const _CompactTopicCategories({
    required this.siteUrl,
    required this.topic,
    required this.keepTopicListOpen,
    required this.maxWidth,
  });

  final String siteUrl;
  final TopicDetail topic;
  final bool keepTopicListOpen;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ShellSelector<Object>(
    select: (controller) => controller.presentationTokenFor(siteUrl),
    builder: (context, _, _) {
      final shell = ShellScope.read(context);
      final category = shell.categoryFor(topic.categoryId, siteUrl: siteUrl);
      if (category == null) return const SizedBox.shrink();
      final parent = shell.categoryFor(
        category.parentCategoryId,
        siteUrl: siteUrl,
      );
      Widget chip(TopicCategory value, {bool isParent = false}) =>
          LayoutBuilder(
            builder: (context, constraints) => _TopicCategoryControl(
              key: ValueKey(
                isParent
                    ? 'topic-header-compact-parent-category'
                    : 'topic-header-compact-category',
              ),
              siteUrl: siteUrl,
              topic: topic,
              category: value,
              subcategory: !isParent && parent != null,
              parentCategoryId: parent?.id,
              keepTopicListOpen: keepTopicListOpen,
              compressed: constraints.maxWidth < 120,
            ),
          );
      return Padding(
        padding: EdgeInsets.only(right: maxWidth <= 128 ? 4 : 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: parent == null ? maxWidth.clamp(72, 200) : maxWidth,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (parent != null) ...[
                Flexible(child: chip(parent, isParent: true)),
                const SizedBox(width: 7),
              ],
              Flexible(child: chip(category)),
            ],
          ),
        ),
      );
    },
  );
}

class _TopicActivitySummary extends StatelessWidget {
  const _TopicActivitySummary({required this.siteUrl, required this.topic});
  final String siteUrl;
  final TopicDetail topic;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Topic?>(
    valueListenable: ShellScope.read(context).topicRef(siteUrl, topic.id),
    builder: (context, row, _) {
      final theme = Theme.of(context);
      final participants = topic.participants.take(3).toList();
      final style = theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
      return Wrap(
        key: const ValueKey('topic-header-activity'),
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (topic.closed)
            Semantics(
              key: const ValueKey('topic-header-closed'),
              label: 'Topic closed',
              excludeSemantics: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.shell.panel,
                  border: Border.all(color: theme.shell.divider),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DIcon(
                        DIcons.lock,
                        size: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Closed',
                          style: style?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (participants.isNotEmpty)
            SizedBox(
              width: 20 + (participants.length - 1) * 15,
              height: 20,
              child: Stack(
                children: [
                  for (var i = 0; i < participants.length; i++)
                    Positioned(
                      left: i * 15,
                      child: Tooltip(
                        message: participants[i].displayName,
                        child: DAvatar.frame(
                          child: AvatarImage(
                            url: participants[i].avatarUrl,
                            size: 20,
                            fallback: Container(
                              width: 20,
                              height: 20,
                              color: theme.shell.hover,
                              alignment: Alignment.center,
                              child: Text(
                                participants[i].username.isEmpty
                                    ? '?'
                                    : participants[i].username.characters.first
                                          .toUpperCase(),
                                style: style?.copyWith(
                                  fontSize: DiscourseTypography.xs,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Text(
            '${topic.replyCount} ${topic.replyCount == 1 ? 'reply' : 'replies'}',
            style: style,
          ),
          if (row?.bumpedAt case final activity?) ...[
            Text('·', style: style),
            Text(switch (relativeTime(activity)) {
              'now' => 'Last activity just now',
              final age => 'Last activity $age ago',
            }, style: style),
          ],
        ],
      );
    },
  );
}

class _TopicInboxNavigation extends StatelessWidget {
  const _TopicInboxNavigation();

  @override
  Widget build(
    BuildContext context,
  ) => ShellSelector<({int? previous, int? next, bool more, bool busy})>(
    select: (shell) {
      final ids = shell.currentFeed?.topicIds ?? const <int>[];
      final index = ids.indexOf(shell.currentContent?.topicId ?? -1);
      return (
        previous: index > 0 ? ids[index - 1] : null,
        next: index >= 0 && index + 1 < ids.length ? ids[index + 1] : null,
        more:
            index >= 0 &&
            index == ids.length - 1 &&
            shell.currentFeed?.hasMore == true,
        busy: shell.currentFeed?.loadingMore == true,
      );
    },
    builder: (context, state, _) {
      final shell = ShellScope.read(context);
      Future<void> open(int? id, {bool loadNext = false}) async {
        final siteUrl = shell.currentInstance?.url;
        final source = shell.currentFeedId;
        final current = shell.currentContent?.topicId;
        if (siteUrl == null) return;
        if (loadNext && source != null) {
          await shell.loadMoreFeed(source);
          if (shell.currentInstance?.url != siteUrl ||
              shell.currentFeedId != source ||
              shell.currentContent?.topicId != current) {
            return;
          }
          final ids = shell.currentFeed?.topicIds ?? const <int>[];
          final index = ids.indexOf(current ?? -1);
          id = index >= 0 && index + 1 < ids.length ? ids[index + 1] : null;
        }
        final topic = id == null ? null : shell.store.read<Topic>(siteUrl, id);
        if (topic != null) shell.openTopicFromList(topic);
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DButton.iconOnly(
            key: const ValueKey('inbox-previous-topic'),
            tooltip: 'Previous topic',
            icon: const DIcon(DIcons.chevronLeft, size: 13),
            onPressed: state.previous == null
                ? null
                : () => unawaited(open(state.previous)),
            variant: DButtonVariant.flat,
            size: DButtonSize.small,
          ),
          DButton.iconOnly(
            key: const ValueKey('inbox-next-topic'),
            tooltip: 'Next topic',
            icon: const DIcon(DIcons.chevronRight, size: 13),
            onPressed: state.busy || (state.next == null && !state.more)
                ? null
                : () =>
                      unawaited(open(state.next, loadNext: state.next == null)),
            variant: DButtonVariant.flat,
            size: DButtonSize.small,
          ),
        ],
      );
    },
  );
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
      final hasCategories = !topic.privateMessage;
      final hasSubcategory =
          hasCategories &&
          (parent != null ||
              (root != null &&
                  topic.canEdit &&
                  shell
                      .filterCategoriesFor(siteUrl)
                      .any((item) => item.parentCategoryId == root.id)));
      final hasTags = topic.tags.isNotEmpty || topic.canEditTags;
      return LayoutBuilder(
        builder: (context, constraints) {
          final categoryWidth =
              (constraints.maxWidth * (hasSubcategory ? .28 : .42)).clamp(
                56.0,
                200.0,
              );
          // Reserve room for category artwork, the privacy lock, and saving.
          // Add the browse button and roomier padding only when each chip fits.
          final compressed = categoryWidth < 100;
          return Row(
            key: const ValueKey('topic-header-taxonomy'),
            children: [
              if (hasCategories) ...[
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: categoryWidth),
                  child: _TopicCategoryControl(
                    siteUrl: siteUrl,
                    topic: topic,
                    category: root,
                    subcategory: false,
                    keepTopicListOpen: keepTopicListOpen,
                    compressed: compressed,
                    showBrowseButton: !compressed,
                  ),
                ),
                if (hasSubcategory) ...[
                  const SizedBox(width: 7),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: categoryWidth),
                    child: _TopicCategoryControl(
                      siteUrl: siteUrl,
                      topic: topic,
                      category: parent == null ? null : category,
                      subcategory: true,
                      parentCategoryId: root?.id,
                      keepTopicListOpen: keepTopicListOpen,
                      compressed: compressed,
                      showBrowseButton: !compressed,
                    ),
                  ),
                ],
              ],
              if (hasTags) ...[
                if (hasCategories) const SizedBox(width: 8),
                Flexible(
                  child: TopicHeaderTags(
                    siteUrl: siteUrl,
                    topic: topic,
                    onTagNavigate: (tag, {newTab = false}) =>
                        shell.openTopicTag(
                          tag,
                          siteUrl: siteUrl,
                          privateMessage: topic.privateMessage,
                          newTab: newTab,
                        ),
                  ),
                ),
              ],
            ],
          );
        },
      );
    },
  );
}

class _TopicCategoryControl extends StatelessWidget {
  const _TopicCategoryControl({
    super.key,
    required this.siteUrl,
    required this.topic,
    required this.category,
    required this.subcategory,
    required this.keepTopicListOpen,
    required this.compressed,
    this.parentCategoryId,
    this.showBrowseButton = true,
  });

  final String siteUrl;
  final TopicDetail topic;
  final TopicCategory? category;
  final bool subcategory;
  final int? parentCategoryId;
  final bool keepTopicListOpen;
  final bool compressed;
  final bool showBrowseButton;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    final value = category;
    final uncategorized = shell.siteConfigFor(siteUrl).allowUncategorizedTopics
        ? shell
              .filterCategoriesFor(siteUrl)
              .where((item) => item.isUncategorized)
              .firstOrNull
        : null;
    return TopicCategoryMenuAnchor(
      siteUrl: siteUrl,
      topicId: topic.id,
      categoryId: topic.categoryId,
      selectedCategoryId: value?.id,
      enabled: topic.canEdit,
      rootOnly: !subcategory,
      parentCategoryId: subcategory ? parentCategoryId : null,
      removeCategoryId: subcategory ? parentCategoryId : uncategorized?.id,
      removeLabel: subcategory ? 'Remove subcategory' : 'Move to Uncategorized',
      builder: (context, edit, saving) {
        final browse = value == null
            ? null
            : () => shell.browseTopicCategory(
                value,
                keepTopicOpen: keepTopicListOpen,
              );
        final browseOnly = !showBrowseButton && !topic.canEdit;
        return _CategoryChip(
          category: value,
          siteUrl: siteUrl,
          label: value?.name ?? (subcategory ? '+ Subcategory' : '+ Category'),
          edit: browseOnly ? browse : edit,
          saving: saving,
          compact: compressed,
          editLabel: browseOnly
              ? 'Browse ${value?.name}'
              : subcategory
              ? 'Edit topic subcategory'
              : 'Edit topic category',
          navigate: showBrowseButton ? browse : null,
        );
      },
    );
  }
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
    this.compact = false,
  });
  final TopicCategory? category;
  final String siteUrl;
  final String label;
  final String editLabel;
  final VoidCallback? edit;
  final VoidCallback? navigate;
  final bool saving;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = category == null
        ? theme.colorScheme.onSurfaceVariant
        : Color(category!.colorValue);
    final overlayColor = WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.focused)) {
        return color.withValues(alpha: .16);
      }
      if (states.contains(WidgetState.pressed)) {
        return color.withValues(alpha: .12);
      }
      if (states.contains(WidgetState.hovered)) {
        return color.withValues(alpha: .08);
      }
      return Colors.transparent;
    });
    return Material(
      color: category == null
          ? Colors.transparent
          : color.withValues(alpha: .10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(5),
        side: BorderSide(color: color.withValues(alpha: .25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Tooltip(
              message: edit == null ? label : editLabel,
              child: InkWell(
                onTap: edit,
                overlayColor: overlayColor,
                splashFactory: NoSplash.splashFactory,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 24),
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 2 : 7,
                    vertical: 5,
                  ),
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
                        SizedBox(width: compact ? 2 : 6),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                      if (!compact &&
                          edit != null &&
                          category != null &&
                          !saving) ...[
                        const SizedBox(width: 5),
                        DIcon(
                          DIcons.chevronDown,
                          size: 9,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
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
          ),
          if (navigate != null)
            LinkTarget(
              url: '/c/${category!.id}',
              title: category!.name,
              siteUrl: siteUrl,
              child: Tooltip(
                message: 'Browse ${category!.name}',
                child: InkWell(
                  key: ValueKey('topic-header-browse-category-${category!.id}'),
                  onTap: navigate,
                  overlayColor: overlayColor,
                  splashFactory: NoSplash.splashFactory,
                  child: Container(
                    width: 25,
                    height: 24,
                    decoration: BoxDecoration(
                      border: BorderDirectional(
                        start: BorderSide(color: color.withValues(alpha: .22)),
                      ),
                    ),
                    child: Center(
                      child: DIcon(
                        DIcons.upRightFromSquare,
                        size: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
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
    this.compact = false,
  });
  final String siteUrl;
  final TopicDetail topic;
  final PluginRegistry registry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Widget properties() {
      final sections = registry.topicProperties(context, siteUrl, topic);
      if (sections.isEmpty) return const SizedBox.shrink();
      final children = <Widget>[
        for (final section in sections)
          Builder(
            builder: (anchorContext) {
              void showDetails() => unawaited(
                showAnchoredPicker<void>(
                  context: context,
                  anchorContext: anchorContext,
                  title: section.label,
                  barrierLabel: 'Dismiss ${section.label}',
                  popoverHeight: null,
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
              if (compact) {
                return section.compactHeader?.call(
                      anchorContext,
                      showDetails,
                    ) ??
                    DButton.iconOnly(
                      icon: const DIcon(DIcons.ellipsis, size: 16),
                      tooltip: section.label,
                      size: DButtonSize.small,
                      variant: DButtonVariant.flat,
                      onPressed: showDetails,
                    );
              }
              return section.header?.call(anchorContext, showDetails) ??
                  DButton(
                    label: Text(section.label),
                    size: DButtonSize.small,
                    onPressed: showDetails,
                  );
            },
          ),
      ];
      return compact
          ? Row(mainAxisSize: MainAxisSize.min, children: children)
          : Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: children,
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
