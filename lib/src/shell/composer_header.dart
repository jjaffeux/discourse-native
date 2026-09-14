import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/composer_placement.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import 'composer_controller.dart';
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

  static const double height = 44;
  static const double _controlIconSize = 24;

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
      ShellSelector<({bool whisperer, int pluginState})>(
        select: (shell) => (
          whisperer:
              shell.currentUserFor(composer.target.siteUrl)?.whisperer == true,
          pluginState: Object.hash(
            shell.siteConfigFor(composer.target.siteUrl),
            shell.freshCurrentUserFor(composer.target.siteUrl),
          ),
        ),
        builder: (context, state, _) => _buildHeader(context, state.whisperer),
      );

  Widget _buildHeader(BuildContext context, bool whisperer) {
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

    final heading = canToggleWhisper
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
                variant: DButtonVariant.ghost,
                size: DButtonSize.small,
                icon: DIcon(
                  composer.whisper ? DIcons.farEyeSlash : DIcons.reply,
                  color: color,
                ),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(label)),
                    const SizedBox(width: 6),
                    const DIcon(DIcons.chevronDown, size: 10),
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
                    size: DToggleSize.small,
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
                child: const Icon(
                  Icons.view_sidebar_outlined,
                  size: _controlIconSize,
                ),
              ),
              tooltip: 'Composer options',
              semanticLabel: 'Composer options',
              hasPopup: true,
              expanded: trigger.open,
              focusNode: trigger.focusNode,
              onPressed: trigger.toggle,
              variant: DButtonVariant.ghost,
              size: DButtonSize.large,
            ),
          ),
        ),
      if (onRestore case final restore?)
        DButton.iconOnly(
          key: const ValueKey('composer-restore'),
          onPressed: restore,
          icon: const DIcon(DIcons.expand, size: _controlIconSize),
          tooltip: 'Restore composer',
          variant: DButtonVariant.ghost,
          size: DButtonSize.large,
        )
      else if (onMinimize case final minimize?)
        DButton.iconOnly(
          key: const ValueKey('composer-minimize'),
          onPressed: minimize,
          icon: const Icon(Icons.remove, size: _controlIconSize),
          tooltip: 'Minimize composer',
          variant: DButtonVariant.ghost,
          size: DButtonSize.large,
        ),
      DButton.iconOnly(
        key: const ValueKey('composer-close'),
        onPressed: onClose,
        icon: const DIcon(DIcons.xmark, size: _controlIconSize),
        tooltip: closeTooltip,
        variant: DButtonVariant.ghost,
        size: DButtonSize.large,
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
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: heading,
              ),
            ),
            ...controls,
          ],
        ),
      ),
    );
  }
}
