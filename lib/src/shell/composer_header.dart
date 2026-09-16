import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/composer_placement.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import 'composer_controller.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';

class ComposerHeader extends StatelessWidget {
  const ComposerHeader({
    super.key,
    required this.composer,
    required this.minimized,
    this.onMinimize,
    this.onRestore,
    this.placement = ComposerPlacement.right,
    this.onPlacementChanged,
  });

  static const double height = readerHeaderHeight;

  final ComposerController composer;
  final bool minimized;
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
    final color = DTokens.of(context).foreground;
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
                variant: DButtonVariant.transparentBackground,
                size: DButtonSize.large,
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
        : Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (composer.whisper) ...[
                  DIcon(DIcons.farEyeSlash, size: 14, color: color),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ),
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
            semanticLabel: 'Composer options',
            align: DPopoverAlign.end,
            width: 264,
            child: DPopoverClose(
              builder: (context, closeMenu) => Row(
                children: [
                  const Expanded(child: Text('Dock side')),
                  DToggleGroup<ComposerPlacement>(
                    semanticLabel: 'Dock side',
                    values: [placement],
                    allowEmptySelection: false,
                    spacing: 1,
                    size: DToggleSize.regular,
                    onChanged: (values) {
                      closeMenu();
                      onPlacementChanged!(values.single);
                    },
                    items: [
                      for (final value in ComposerPlacement.values)
                        DToggleGroupItem.iconOnly(
                          value: value,
                          semanticLabel: value.label,
                          tooltip: value.label,
                          icon: switch (value) {
                            ComposerPlacement.left => const RotatedBox(
                              quarterTurns: 2,
                              child: Icon(
                                Icons.view_sidebar_outlined,
                                size: 18,
                              ),
                            ),
                            ComposerPlacement.bottom => const RotatedBox(
                              quarterTurns: 1,
                              child: Icon(
                                Icons.view_sidebar_outlined,
                                size: 18,
                              ),
                            ),
                            ComposerPlacement.right => const Icon(
                              Icons.view_sidebar_outlined,
                              size: 18,
                            ),
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          child: DPopoverTrigger(
            builder: (context, trigger) => DButton.iconOnly(
              key: const ValueKey('composer-options'),
              icon: RotatedBox(
                quarterTurns: switch (placement) {
                  ComposerPlacement.left => 2,
                  ComposerPlacement.bottom => 1,
                  ComposerPlacement.right => 0,
                },
                child: const Icon(Icons.view_sidebar_outlined),
              ),
              tooltip: 'Composer options',
              semanticLabel: 'Composer options',
              hasPopup: true,
              expanded: trigger.open,
              focusNode: trigger.focusNode,
              onPressed: trigger.toggle,
              variant: DButtonVariant.transparentBackground,
              size: DButtonSize.regular,
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
    ];
    return SizedBox(
      key: const ValueKey('composer-header'),
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: minimized
                  ? heading
                  : Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: heading,
                    ),
            ),
            if (composer.canSaveDraft && !target.isEdit)
              Flexible(child: _DraftStatus(composer: composer)),
            ...controls,
          ],
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
            child: Row(
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
                if (showLabel) ...[
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
    );
  }
}
