import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/composer_placement.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import '../theme/discourse_typography.dart';
import 'composer_controller.dart';
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
    this.onExitFullScreen,
    this.mobileSubmit,
    this.onDiscard,
  });

  static const double height = readerHeaderHeight;

  final Widget? mobileSubmit;
  final VoidCallback? onDiscard;
  final ComposerController composer;
  final bool minimized;
  final VoidCallback onClose;
  final String closeTooltip;
  final VoidCallback? onMinimize;
  final VoidCallback? onRestore;
  final ComposerPlacement placement;
  final ValueChanged<ComposerPlacement>? onPlacementChanged;
  final VoidCallback? onExitFullScreen;

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
      ComposerMode.newTopic => context.l10n.newTopic,
      ComposerMode.privateMessage => context.l10n.newMessage,
      ComposerMode.categoryEdit => context.l10n.editCategory,
      ComposerMode.tagsEdit => context.l10n.editTags,
      ComposerMode.topicEdit => context.l10n.editTopic,
      ComposerMode.postEdit => context.l10n.editPost(
        (target.editingPostNumber).toString(),
      ),
      ComposerMode.plugin => target.topicTitle,
      ComposerMode.reply =>
        composer.whisper ? context.l10n.whisper : context.l10n.reply,
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
            semanticLabel: context.l10n.resumeEditing((label).toString()),
            tooltip: context.l10n.restoreComposer,
            variant: DButtonVariant.primary,
            size: DButtonSize.toolbar,
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
                Text(context.l10n.resumeEditingComposerheader),
                const SizedBox(width: 8),
                const DIcon(DIcons.expand),
              ],
            ),
          )
        : canToggleWhisper
        ? DDropdownMenu(
            content: DDropdownMenuContent(
              semanticLabel: context.l10n.replyVisibility,
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
                            ? context.l10n.whisperAllowedGroupsOnly
                            : context.l10n.reply,
                        closeOnSelect: true,
                        leading: DIcon(
                          whisper ? DIcons.farEyeSlash : DIcons.reply,
                          size: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              whisper
                                  ? context.l10n.whisper
                                  : context.l10n.reply,
                            ),
                            if (whisper)
                              Text(
                                context.l10n.allowedGroupsOnly,
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
                    ? context.l10n.whisperOptions
                    : context.l10n.replyOptions,
                variant: DButtonVariant.outline,
                size: DButtonSize.toolbar,
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

    if (mobileSubmit != null && !minimized) {
      return Padding(
        key: const ValueKey('composer-header'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          spacing: DSpacing.controlGap,
          children: [
            DDropdownMenu(
              content: DDropdownMenuContent(
                semanticLabel: context.l10n.composerActions,
                children: [
                  DDropdownMenuItem(
                    key: const ValueKey('composer-cancel'),
                    variant: DDropdownMenuItemVariant.destructive,
                    onPressed: onDiscard,
                    child: Text(context.l10n.discard),
                  ),
                  DDropdownMenuItem(
                    key: const ValueKey('composer-minimize'),
                    onPressed: onMinimize,
                    child: Text(context.l10n.minimize),
                  ),
                  DDropdownMenuItem(
                    key: const ValueKey('composer-save-draft'),
                    onPressed: composer.canSaveDraft ? onClose : null,
                    child: Text(context.l10n.saveDraft),
                  ),
                ],
              ),
              child: DDropdownMenuTrigger(
                builder: (context, trigger) => DButton.iconOnly(
                  key: const ValueKey('composer-close'),
                  onPressed: trigger.toggle,
                  icon: const DIcon(DIcons.xmark),
                  tooltip: context.l10n.composerActions,
                  semanticLabel: context.l10n.composerActions,
                  variant: DButtonVariant.outline,
                  shape: DButtonShape.pill,
                  focusNode: trigger.focusNode,
                  hasPopup: true,
                  expanded: trigger.open,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  spacing: DSpacing.controlGap,
                  children: [
                    if (canToggleWhisper) heading,
                    ...pluginControls,
                    if (composer.canSaveDraft && !target.isEdit)
                      _DraftSaveFailure(composer: composer),
                  ],
                ),
              ),
            ),
            mobileSubmit!,
          ],
        ),
      );
    }

    final controls = [
      if (!atDestination && !target.createsTopic && target.topicId > 0)
        DButton.iconOnly(
          key: const ValueKey('composer-return-to-topic'),
          tooltip: context.l10n.returnTo((target.topicTitle).toString()),
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
            semanticLabel: context.l10n.dockSide,
            align: DPopoverAlign.end,
            width: 250,
            child: DPopoverClose(
              builder: (context, close) => Row(
                children: [
                  Expanded(child: Text(context.l10n.dockSide)),
                  DToggleGroup<ComposerPlacement>(
                    size: DControlSize.segment,
                    inset: true,
                    semanticLabel: context.l10n.dockSide,
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
              size: DControlSize.segment,
              key: const ValueKey('composer-options'),
              inset: true,
              semanticLabel: context.l10n.composerView,
              values: [placement == ComposerPlacement.fullScreen],
              allowEmptySelection: false,
              onItemActivated: (fullScreen) {
                if (!fullScreen) {
                  if (placement == ComposerPlacement.fullScreen &&
                      onExitFullScreen != null) {
                    onExitFullScreen!();
                  } else {
                    trigger.toggle();
                  }
                }
              },
              onChanged: (values) {
                if (values.single) {
                  onPlacementChanged!(ComposerPlacement.fullScreen);
                }
              },
              items: [
                DToggleGroupItem.iconOnly(
                  value: false,
                  semanticLabel: context.l10n.dockSide,
                  tooltip: context.l10n.dockSide,
                  focusNode: trigger.focusNode,
                  icon: const Icon(Icons.view_sidebar_outlined),
                ),
                DToggleGroupItem.iconOnly(
                  value: true,
                  semanticLabel: context.l10n.fullScreen,
                  tooltip: context.l10n.fullScreen,
                  icon: const Icon(Icons.fullscreen),
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
          tooltip: context.l10n.restoreComposer,
          variant: DButtonVariant.transparentBackground,
          size: DButtonSize.toolbar,
        )
      else if (onMinimize case final minimize?)
        DButton.iconOnly(
          key: const ValueKey('composer-minimize'),
          onPressed: minimize,
          icon: const Icon(Icons.remove),
          tooltip: context.l10n.minimizeComposer,
          variant: DButtonVariant.transparentBackground,
          size: DButtonSize.toolbar,
        ),
      if (!minimized)
        DButton.iconOnly(
          key: const ValueKey('composer-close'),
          onPressed: onClose,
          icon: const DIcon(DIcons.xmark),
          tooltip: closeTooltip,
          variant: DButtonVariant.transparentBackground,
          size: DButtonSize.toolbar,
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
                                child: heading,
                              ),
                      ),
                      if (!minimized && composer.canSaveDraft && !target.isEdit)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.6,
                          ),
                          child: _DraftSaveFailure(composer: composer),
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
                    spacing: DSpacing.controlGap,
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

class _DraftSaveFailure extends StatelessWidget {
  const _DraftSaveFailure({required this.composer});

  final ComposerController composer;

  @override
  Widget build(BuildContext context) {
    final failing =
        composer.localDraftFailed ||
        composer.draftsGaveUp ||
        composer.draftStatus == DraftStatus.failing;
    if (!failing) return const SizedBox.shrink();
    final (label, description) = composer.localDraftFailed
        ? (context.l10n.notSaved, context.l10n.couldnTSaveThisDraftOnThisDevice)
        : (
            context.l10n.deviceOnly,
            context.l10n.notSavedOnTheSiteKeptOnThisDeviceOnly,
          );

    final tokens = DTokens.of(context);
    final color = tokens.destructive;
    final style = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: color);
    final textScaler = MediaQuery.textScalerOf(context);
    final showLabel =
        textScaler.scale(style?.fontSize ?? DiscourseTypography.xs) *
            (style?.height ?? 1) <=
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
          message: description,
          excludeFromSemantics: true,
          child: SizedBox(
            // Keep failure details reachable even at large text scales.
            width: showLabel ? 20 + textScaler.scale(72) : 14,
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  DIcon(DIcons.triangleExclamation, size: 14, color: color),
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
