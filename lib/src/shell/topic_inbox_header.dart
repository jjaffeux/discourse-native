import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import 'anchored_picker.dart';
import 'category_icon.dart';
import 'platform.dart';
import 'shell_scope.dart';
import 'title_bar.dart';
import 'topic_actions.dart';
import 'topic_header_editor.dart';
import 'topic_header_tags.dart';
import 'topic_title.dart';
import 'user_menu_button.dart';

/// Ledger context stays above the post viewport, including while editing.
/// The body owns its scrolling and receives no header obstruction.
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
    this.bodyBuilder,
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
  final Widget Function(List<Widget> openingSlivers, double pinnedExtent)?
  bodyBuilder;

  @override
  State<TopicInboxHeader> createState() => _TopicInboxHeaderState();
}

class _TopicInboxHeaderState extends State<TopicInboxHeader> {
  TopicHeaderField? _field;
  Object? _owner;

  void _edit(TopicHeaderField field) => setState(() => _field = field);

  @override
  Widget build(BuildContext context) {
    final siteUrl = widget.siteUrl;
    final topic = widget.topic;
    return ShellSelector<Object>(
      select: (shell) => (
        shell,
        siteUrl == null ? null : shell.lifecycle.capture(siteUrl).session,
        siteUrl == null ? null : shell.presentationTokenFor(siteUrl),
      ),
      builder: (context, _, _) {
        final shell = ShellScope.read(context);
        final owner = (
          shell,
          siteUrl,
          topic?.id,
          siteUrl == null ? null : shell.lifecycle.capture(siteUrl).session,
        );
        if (_owner != owner) {
          _owner = owner;
          _field = null;
        }
        final editable =
            topic != null &&
            siteUrl != null &&
            (topic.canEdit || topic.canEditTags);
        final header = DecoratedBox(
          key: const ValueKey('topic-content-header'),
          decoration: BoxDecoration(
            color: Theme.of(context).shell.content,
            border: Border(
              bottom: BorderSide(color: DTokens.of(context).border),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ledger(context),
              if (_field != null && editable)
                TopicHeaderEditor(
                  key: ValueKey((owner, _field)),
                  siteUrl: siteUrl,
                  topic: topic,
                  field: _field!,
                  onClose: () => setState(() => _field = null),
                ),
            ],
          ),
        );
        final body = widget.bodyBuilder;
        final contextHeader = Semantics(
          container: true,
          explicitChildNodes: true,
          child: header,
        );
        if (body == null) return contextHeader;
        final reader = body(const [], 0);
        return LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Large text, a keyboard, or unusually many tags can exhaust a
              // short window. Keep the complete header reachable while still
              // reserving a reading viewport; normal headers keep their height.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .6,
                ),
                child: DScrollArea(
                  borderRadius: BorderRadius.zero,
                  child: contextHeader,
                ),
              ),
              Expanded(child: reader),
            ],
          ),
        );
      },
    );
  }

  Widget _ledger(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final topic = widget.topic;
      final siteUrl = widget.siteUrl;
      final shell = ShellScope.read(context);
      final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
      final wide = constraints.maxWidth >= 540 * scale;
      final categoryWidth = constraints.maxWidth >= 760 * scale ? 160.0 : 140.0;
      final category = siteUrl == null || topic?.privateMessage == true
          ? null
          : shell.categoryFor(topic?.categoryId, siteUrl: siteUrl);
      final categoryControl = topic != null && siteUrl != null
          ? _LedgerCategory(
              siteUrl: siteUrl,
              topic: topic,
              category: category,
              showMarker: !wide,
              onEdit: topic.canEdit
                  ? () => _edit(TopicHeaderField.category)
                  : null,
            )
          : const SizedBox.shrink();
      final actions = Wrap(
        key: const ValueKey('topic-header-common-actions'),
        spacing: DSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.end,
        children: [
          if (topic != null && siteUrl != null) ...[
            _TopicHeaderProperties(
              siteUrl: siteUrl,
              topic: topic,
              registry: widget.registry,
              compact: true,
            ),
            TopicStatusButton(
              siteUrl: siteUrl,
              topic: topic,
              topicFlags: shell.availableTopicFlagTypes(siteUrl, topic),
              compact: true,
              includeContextActions: true,
              route: widget.route,
            ),
          ],
          if (ShellTitleBar.columnsCarryUserMenu) const UserMenuButton(),
        ],
      );
      final identity = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _LedgerTitle(
            title: widget.title,
            siteUrl: siteUrl,
            onEdit: topic?.canEdit == true && siteUrl != null
                ? () => _edit(TopicHeaderField.title)
                : null,
          ),
          if (topic != null && siteUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: DSpacing.xs),
              child: Wrap(
                key: const ValueKey('topic-header-taxonomy'),
                spacing: DSpacing.xs,
                runSpacing: DSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TopicHeaderTags(
                    key: const ValueKey('topic-header-tags'),
                    siteUrl: siteUrl,
                    topic: topic,
                    onEdit: () => _edit(TopicHeaderField.tags),
                    onTagNavigate: (tag, {newTab = false}) =>
                        shell.openTopicTag(
                          tag,
                          siteUrl: siteUrl,
                          privateMessage: topic.privateMessage,
                          newTab: newTab,
                        ),
                  ),
                  if (topic.closed)
                    const DBadge(
                      key: ValueKey('topic-header-closed'),
                      variant: DBadgeVariant.secondary,
                      leading: DIcon(DIcons.lock),
                      child: Text('Closed'),
                    ),
                  if (topic.archived)
                    const DBadge(
                      variant: DBadgeVariant.secondary,
                      child: Text('Archived'),
                    ),
                  if (!topic.visible)
                    const DBadge(
                      variant: DBadgeVariant.secondary,
                      child: Text('Unlisted'),
                    ),
                  if (topic.pinned)
                    const DBadge(
                      variant: DBadgeVariant.secondary,
                      child: Text('Pinned'),
                    ),
                  if (topic.deletedAt != null)
                    const DBadge(
                      variant: DBadgeVariant.destructive,
                      child: Text('Deleted'),
                    ),
                ],
              ),
            ),
        ],
      );
      if (wide) {
        final color = category == null
            ? DTokens.of(context).border
            : Color(category.colorValue);
        return Stack(
          children: [
            // The ledger rail is a full-height part of the header, rather than
            // a category button with an oversized painted surface.
            if (topic != null)
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: categoryWidth,
                child: DecoratedBox(
                  key: const ValueKey('topic-header-category-rail'),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .05),
                    border: BorderDirectional(
                      start: BorderSide(color: color, width: 3),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                if (topic != null)
                  SizedBox(
                    width: categoryWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DSpacing.sm,
                        vertical: DSpacing.md,
                      ),
                      child: Row(
                        children: [
                          if (!widget.keepTopicListOpen)
                            TopicCloseButton(
                              canReturnToSidebar: widget.canReturnToSidebar,
                            ),
                          Expanded(child: categoryControl),
                        ],
                      ),
                    ),
                  )
                else if (!widget.keepTopicListOpen)
                  TopicCloseButton(
                    canReturnToSidebar: widget.canReturnToSidebar,
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: identity,
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 12),
                  child: actions,
                ),
              ],
            ),
          ],
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: DSpacing.sm,
              runSpacing: DSpacing.xs,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (constraints.maxWidth - 24) / 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!widget.keepTopicListOpen)
                        TopicCloseButton(
                          canReturnToSidebar: widget.canReturnToSidebar,
                        ),
                      Flexible(child: categoryControl),
                    ],
                  ),
                ),
                actions,
              ],
            ),
            const SizedBox(height: DSpacing.xs),
            identity,
          ],
        ),
      );
    },
  );
}

class _LedgerTitle extends StatelessWidget {
  const _LedgerTitle({required this.title, required this.siteUrl, this.onEdit});
  final String title;
  final String? siteUrl;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    final label = siteUrl == null
        ? Text(
            title,
            style: style,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          )
        : TopicTitle(
            title,
            key: const ValueKey('topic-header-compact-title'),
            siteUrl: siteUrl!,
            style: style,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );
    return onEdit == null
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: DTooltip(message: title, child: label),
          )
        : Align(
            alignment: AlignmentDirectional.centerStart,
            child: DButton(
              key: const ValueKey('topic-header-title'),
              label: label,
              tooltip: 'Rename topic',
              variant: DButtonVariant.ghost,
              size: DButtonSize.small,
              onPressed: onEdit,
            ),
          );
  }
}

class _LedgerCategory extends StatelessWidget {
  const _LedgerCategory({
    required this.siteUrl,
    required this.topic,
    required this.category,
    required this.showMarker,
    this.onEdit,
  });
  final String siteUrl;
  final TopicDetail topic;
  final TopicCategory? category;
  final bool showMarker;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    if (topic.privateMessage) {
      return const DBadge(
        variant: DBadgeVariant.ghost,
        leading: DIcon(DIcons.envelope),
        child: Text('Message'),
      );
    }
    final shell = ShellScope.read(context);
    final parent = shell.categoryFor(
      category?.parentCategoryId,
      siteUrl: siteUrl,
    );
    final path = category == null
        ? 'Category'
        : shell.topicCategoryPathLabel(category!, siteUrl: siteUrl);
    final label = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parent != null)
          Text(
            parent.name,
            softWrap: true,
            maxLines: 20,
            style: TextStyle(color: DTokens.of(context).mutedForeground),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (category != null && showMarker) ...[
              CategoryIcon(
                category: category!,
                siteUrl: siteUrl,
                size: 12,
                squareSize: 8,
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                category?.name ?? 'Set category',
                softWrap: true,
                maxLines: 20,
              ),
            ),
          ],
        ),
      ],
    );
    return Align(
      key: const ValueKey('topic-header-category'),
      alignment: AlignmentDirectional.centerStart,
      child: DButton(
        label: label,
        icon: onEdit == null ? null : const DIcon(DIcons.chevronDown),
        iconPosition: DButtonIconPosition.end,
        tooltip: onEdit == null ? 'Browse $path' : 'Edit topic category',
        variant: DButtonVariant.ghost,
        size: DButtonSize.small,
        onPressed:
            onEdit ??
            (category == null
                ? null
                : () => shell.openCategory(category!, siteUrl: siteUrl)),
      ),
    );
  }
}

class TopicCloseButton extends StatelessWidget {
  const TopicCloseButton({super.key, required this.canReturnToSidebar});

  final bool canReturnToSidebar;

  @override
  Widget build(BuildContext context) => DButton.iconOnly(
    key: const ValueKey('topic-close-reader'),
    icon: const DIcon(DNativeIcons.closeTopicPane, size: 20),
    tooltip: ShellScope.read(context).topicListContent?.isMessages == true
        ? 'Collapse message'
        : 'Collapse topic',
    variant: DButtonVariant.ghost,
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
          _TopicPropertyPopover(
            key: ValueKey(('topic-header-property', section.label)),
            siteUrl: siteUrl,
            topicId: topic.id,
            section: section,
            registry: registry,
            compact: compact,
            navigationRevision: ShellScope.read(
              context,
            ).topicNavigationRevision,
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

class _TopicPropertyPopover extends StatefulWidget {
  const _TopicPropertyPopover({
    super.key,
    required this.siteUrl,
    required this.topicId,
    required this.section,
    required this.registry,
    required this.compact,
    required this.navigationRevision,
  });

  final String siteUrl;
  final int topicId;
  final TopicPropertySection section;
  final PluginRegistry registry;
  final bool compact;
  final int navigationRevision;

  @override
  State<_TopicPropertyPopover> createState() => _TopicPropertyPopoverState();
}

class _TopicPropertyPopoverState extends State<_TopicPropertyPopover> {
  final _controller = DPopoverController();

  @override
  void didUpdateWidget(_TopicPropertyPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.topicId != widget.topicId ||
        oldWidget.navigationRevision != widget.navigationRevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.close();
      });
    }
  }

  Widget _trigger(
    BuildContext context,
    VoidCallback showDetails, {
    FocusNode? focusNode,
    bool expanded = false,
  }) {
    final section = widget.section;
    if (widget.compact) {
      return section.compactHeader?.call(context, showDetails) ??
          DButton.iconOnly(
            icon: const DIcon(DIcons.ellipsis),
            tooltip: section.label,
            size: DButtonSize.small,
            variant: DButtonVariant.ghost,
            hasPopup: true,
            expanded: expanded,
            focusNode: focusNode,
            onPressed: showDetails,
          );
    }
    return section.header?.call(context, showDetails) ??
        DButton(
          label: Text(section.label),
          size: DButtonSize.small,
          hasPopup: true,
          expanded: expanded,
          focusNode: focusNode,
          onPressed: showDetails,
        );
  }

  void _showTouch(BuildContext anchorContext) => unawaited(
    showAnchoredPicker<void>(
      context: context,
      anchorContext: anchorContext,
      title: widget.section.label,
      barrierLabel: 'Dismiss ${widget.section.label}',
      popoverHeight: null,
      popoverKey: ValueKey(('topic-header-property', widget.section.label)),
      builder: (pickerContext) => _TopicPropertyDetails(
        siteUrl: widget.siteUrl,
        topicId: widget.topicId,
        label: widget.section.label,
        registry: widget.registry,
        navigationRevision: widget.navigationRevision,
        onDismiss: () => Navigator.of(pickerContext).pop(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (context.isTouch) {
      return Builder(
        builder: (anchorContext) =>
            _trigger(anchorContext, () => _showTouch(anchorContext)),
      );
    }
    return DPopover(
      controller: _controller,
      content: DPopoverContent(
        width: 252,
        padding: EdgeInsets.zero,
        semanticLabel: widget.section.label,
        align: DPopoverAlign.end,
        child: _TopicPropertyDetails(
          siteUrl: widget.siteUrl,
          topicId: widget.topicId,
          label: widget.section.label,
          registry: widget.registry,
          navigationRevision: widget.navigationRevision,
          onDismiss: _controller.close,
        ),
      ),
      child: DPopoverTrigger(
        builder: (context, trigger) => _trigger(
          context,
          trigger.toggle,
          focusNode: trigger.focusNode,
          expanded: trigger.open,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _TopicPropertyDetails extends StatelessWidget {
  const _TopicPropertyDetails({
    required this.siteUrl,
    required this.topicId,
    required this.label,
    required this.registry,
    required this.navigationRevision,
    required this.onDismiss,
  });
  final String siteUrl;
  final int topicId;
  final String label;
  final PluginRegistry registry;
  final int navigationRevision;
  final VoidCallback onDismiss;

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
          if (context.mounted) onDismiss();
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
