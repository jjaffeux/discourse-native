import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/composer_placement.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import 'composer_controller.dart';
import 'composer_recent_drafts.dart';
import 'platform.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';

class ComposerHeader extends StatelessWidget {
  const ComposerHeader({
    super.key,
    required this.composer,
    required this.minimized,
    required this.onClose,
    required this.closeTooltip,
    this.onMinimize,
    this.onRestore,
    this.placement = ComposerPlacement.right,
    this.onPlacementChanged,
  });

  static const double height = readerHeaderHeight;

  final ComposerController composer;
  final bool minimized;
  final VoidCallback onClose;
  final String closeTooltip;
  final VoidCallback? onMinimize;
  final VoidCallback? onRestore;
  final ComposerPlacement placement;
  final ValueChanged<ComposerPlacement>? onPlacementChanged;

  @override
  Widget build(BuildContext context) =>
      ShellSelector<({bool whisperer, int pluginState, bool atDestination})>(
        select: (shell) => (
          atDestination:
              shell.currentInstance?.url == composer.target.siteUrl &&
              shell.currentContent?.topicId == composer.target.topicId,
          whisperer:
              shell.currentUserFor(composer.target.siteUrl)?.whisperer == true,
          pluginState: Object.hash(
            shell.siteConfigFor(composer.target.siteUrl),
            shell.freshCurrentUserFor(composer.target.siteUrl),
          ),
        ),
        builder: (context, state, _) =>
            _buildHeader(context, state.whisperer, state.atDestination),
      );

  Widget _buildHeader(
    BuildContext context,
    bool whisperer,
    bool atDestination,
  ) {
    final theme = Theme.of(context);
    final target = composer.target;
    final modeLabel = switch (target.mode) {
      ComposerMode.newTopic => 'New topic',
      ComposerMode.privateMessage => 'New message',
      ComposerMode.categoryEdit => 'Edit category',
      ComposerMode.tagsEdit => 'Edit tags',
      ComposerMode.topicEdit => 'Edit topic',
      ComposerMode.postEdit => 'Edit post #${target.editingPostNumber}',
      ComposerMode.plugin => target.topicTitle,
      ComposerMode.reply => composer.whisper ? 'Whisper' : 'Reply',
    };
    final destination = target.createsTopic
        ? composer.title.text
        : target.topicTitle;
    final label = minimized && destination.isNotEmpty
        ? '$modeLabel · $destination'
        : modeLabel;
    final canToggleWhisper =
        !minimized &&
        whisperer &&
        target.mode == ComposerMode.reply &&
        !target.replyingToWhisper;
    final registry =
        PluginScope.maybeOf(context)?.registry ?? PluginRegistry.empty;
    final pluginControls = minimized
        ? const <Widget>[]
        : registry.composerHeader(context, composer);

    final heading = minimized
        ? DButton(
            key: const ValueKey('composer-restore'),
            onPressed: onRestore,
            semanticLabel: 'Resume editing: $label',
            tooltip: 'Restore composer',
            variant: DButtonVariant.primary,
            size: DButtonSize.large,
            icon: DIcon(composer.whisper ? DIcons.farEyeSlash : DIcons.pen),
            label: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Resume editing'),
                const SizedBox(width: 8),
                const DIcon(DIcons.expand),
              ],
            ),
          )
        : canToggleWhisper
        ? DDropdownMenu(
            content: DDropdownMenuContent(
              semanticLabel: 'Reply visibility',
              width: 240,
              children: [
                DDropdownMenuRadioGroup<bool>(
                  value: composer.whisper,
                  onChanged: composer.isEditing && !composer.loadingBody
                      ? composer.setWhisper
                      : null,
                  children: [
                    for (final whisper in [false, true])
                      DDropdownMenuRadioItem<bool>(
                        key: ValueKey(
                          whisper
                              ? 'composer-toggle-whisper'
                              : 'composer-public-reply',
                        ),
                        value: whisper,
                        semanticLabel: whisper
                            ? 'Whisper, Allowed groups only'
                            : 'Reply',
                        closeOnSelect: true,
                        leading: DIcon(
                          whisper ? DIcons.farEyeSlash : DIcons.reply,
                          size: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(whisper ? 'Whisper' : 'Reply'),
                            if (whisper)
                              Text(
                                'Allowed groups only',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: DTokens.of(context).mutedForeground,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            child: DDropdownMenuTrigger(
              builder: (context, trigger) => DButton(
                key: const ValueKey('composer-reply-options'),
                onPressed: composer.isEditing && !composer.loadingBody
                    ? trigger.toggle
                    : null,
                hasPopup: true,
                expanded: trigger.open,
                focusNode: trigger.focusNode,
                semanticLabel: composer.whisper
                    ? 'Whisper options'
                    : 'Reply options',
                variant: DButtonVariant.outline,
                size: DButtonSize.regular,
                icon: DIcon(
                  composer.whisper ? DIcons.farEyeSlash : DIcons.reply,
                ),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(label)),
                    const SizedBox(width: 6),
                    const DIcon(DIcons.chevronDown),
                  ],
                ),
              ),
            ),
          )
        : DToggle(
            key: const ValueKey('composer-mode'),
            pressed: true,
            readOnly: true,
            variant: DToggleVariant.outline,
            icon: DIcon(
              composer.whisper
                  ? DIcons.farEyeSlash
                  : target.createsTopic
                  ? DIcons.layerGroup
                  : target.isEdit
                  ? DIcons.pen
                  : DIcons.reply,
            ),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          );

    final controls = [
      if (!atDestination && !target.createsTopic && target.topicId > 0)
        DButton.iconOnly(
          key: const ValueKey('composer-return-to-topic'),
          tooltip: 'Return to ${target.topicTitle}',
          icon: const DIcon(DIcons.arrowLeft),
          variant: DButtonVariant.transparentBackground,
          onPressed: () => ShellScope.read(context).openTopicPost(
            siteUrl: target.siteUrl,
            topicId: target.topicId,
            postNumber:
                target.replyToPostNumber ?? target.editingPostNumber ?? 1,
          ),
        ),
      ...pluginControls,
      if (!minimized && onPlacementChanged != null)
        DPopover(
          reverseTransitionDuration: Duration.zero,
          content: DPopoverContent(
            semanticLabel: 'Dock side',
            align: DPopoverAlign.end,
            width: 250,
            child: DPopoverClose(
              builder: (context, close) => Row(
                children: [
                  const Expanded(child: Text('Dock side')),
                  DToggleGroup<ComposerPlacement>(
                    inset: true,
                    semanticLabel: 'Dock side',
                    values: [placement],
                    allowEmptySelection: false,
                    onChanged: (values) {
                      close();
                      onPlacementChanged!(values.single);
                    },
                    items: [
                      for (final value in const [
                        ComposerPlacement.left,
                        ComposerPlacement.bottom,
                        ComposerPlacement.right,
                      ])
                        DToggleGroupItem.iconOnly(
                          value: value,
                          semanticLabel: value.label,
                          tooltip: value.label,
                          icon: RotatedBox(
                            quarterTurns: value == ComposerPlacement.left
                                ? 2
                                : value == ComposerPlacement.bottom
                                ? 1
                                : 0,
                            child: const Icon(Icons.view_sidebar_outlined),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          child: DPopoverTrigger(
            builder: (context, trigger) => DToggleGroup<bool>(
              key: const ValueKey('composer-options'),
              inset: true,
              semanticLabel: 'Composer view',
              values: [placement == ComposerPlacement.fullScreen],
              allowEmptySelection: false,
              onItemActivated: (fullScreen) {
                if (!fullScreen) trigger.toggle();
              },
              onChanged: (values) {
                if (values.single) {
                  onPlacementChanged!(ComposerPlacement.fullScreen);
                }
              },
              items: [
                DToggleGroupItem.iconOnly(
                  value: false,
                  semanticLabel: 'Dock side',
                  tooltip: 'Dock side',
                  focusNode: trigger.focusNode,
                  icon: const Icon(Icons.view_sidebar_outlined),
                ),
                const DToggleGroupItem.iconOnly(
                  value: true,
                  semanticLabel: 'Full screen',
                  tooltip: 'Full screen',
                  icon: Icon(Icons.fullscreen),
                ),
              ],
            ),
          ),
        ),
      if (!minimized && onRestore != null)
        DButton.iconOnly(
          key: const ValueKey('composer-restore'),
          onPressed: onRestore,
          icon: const DIcon(DIcons.expand),
          tooltip: 'Restore composer',
          variant: DButtonVariant.transparentBackground,
          size: DButtonSize.regular,
        )
      else if (onMinimize case final minimize?)
        DButton.iconOnly(
          key: const ValueKey('composer-minimize'),
          onPressed: minimize,
          icon: const Icon(Icons.remove),
          tooltip: 'Minimize composer',
          variant: DButtonVariant.transparentBackground,
          size: DButtonSize.regular,
        ),
      if (!minimized)
        DButton.iconOnly(
          key: const ValueKey('composer-close'),
          onPressed: onClose,
          icon: const DIcon(DIcons.xmark),
          tooltip: closeTooltip,
          variant: DButtonVariant.transparentBackground,
          size: DButtonSize.regular,
        ),
    ];
    final alignWithTabs =
        !minimized && !context.isTouch && placement != ComposerPlacement.bottom;
    return SizedBox(
      key: const ValueKey('composer-header'),
      height: alignWithTabs
          ? workspaceTabStripHeightFor(context) + workspaceTabsPadding.vertical
          : height,
      child: Padding(
        padding: alignWithTabs
            ? workspaceTabsPadding
            : const EdgeInsets.symmetric(horizontal: 8),
        child: LayoutBuilder(
          builder: (context, headerConstraints) => Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      Expanded(
                        child: minimized
                            ? heading
                            : Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: ComposerRecentDrafts(
                                    composer: composer,
                                    heading: heading,
                                  ),
                                ),
                              ),
                      ),
                      if (!minimized && composer.canSaveDraft && !target.isEdit)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.6,
                          ),
                          child: _DraftStatus(composer: composer),
                        ),
                    ],
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: headerConstraints.maxWidth * 0.6,
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: controls,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftStatus extends StatelessWidget {
  const _DraftStatus({required this.composer});

  final ComposerController composer;

  @override
  Widget build(BuildContext context) {
    final failing =
        composer.localDraftFailed ||
        composer.draftsGaveUp ||
        composer.draftStatus == DraftStatus.failing;
    final saving =
        !failing &&
        (composer.draftPending || composer.draftStatus == DraftStatus.saving);
    final (label, description) = switch (composer) {
      _ when composer.localDraftFailed => (
        'Not saved',
        "Couldn't save this draft on this device.",
      ),
      _ when failing => (
        'Device only',
        'Not saved on the site — kept on this device only.',
      ),
      _ when saving => ('Saving…', 'Saving draft…'),
      _ when composer.draftStatus == DraftStatus.saved => (
        'Saved',
        'Draft saved on the site',
      ),
      _ => (null, null),
    };
    if (label == null) return const SizedBox.shrink();

    final tokens = DTokens.of(context);
    final color = failing ? tokens.destructive : tokens.mutedForeground;
    final style = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: color);
    final textScaler = MediaQuery.textScalerOf(context);
    final showLabel =
        textScaler.scale(style?.fontSize ?? 12) * (style?.height ?? 1) <=
        ComposerHeader.height;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8, end: 8),
      child: Semantics(
        key: const ValueKey('composer-draft-status'),
        container: true,
        liveRegion: true,
        excludeSemantics: true,
        label: description,
        child: DTooltip(
          message: description!,
          excludeFromSemantics: true,
          child: SizedBox(
            // Reserve the same label space across save states, including zoom.
            width: showLabel ? 20 + textScaler.scale(72) : 14,
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (saving)
                    DSpinner(size: 14, color: color, semanticLabel: null)
                  else
                    DIcon(
                      failing ? DIcons.triangleExclamation : DIcons.check,
                      size: 14,
                      color: color,
                    ),
                  if (showLabel && constraints.maxWidth >= 40) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
