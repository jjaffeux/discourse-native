import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/composer_placement.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icon.dart';
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
    required this.onDiscard,
    this.onMinimize,
    this.onRestore,
    this.placement = ComposerPlacement.right,
    this.onPlacementChanged,
  });

  static const double height = 44;

  final ComposerController composer;
  final bool minimized;
  final VoidCallback onClose;
  final String closeTooltip;
  final VoidCallback onDiscard;
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
    final color = composer.whisper
        ? theme.colorScheme.tertiary
        : theme.colorScheme.onSurface;
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
        ? MenuAnchor(
            menuChildren: [
              for (final whisper in [false, true])
                MenuItemButton(
                  key: ValueKey(
                    whisper
                        ? 'composer-toggle-whisper'
                        : 'composer-public-reply',
                  ),
                  onPressed: composer.isEditing && !composer.loadingBody
                      ? () => composer.setWhisper(whisper)
                      : null,
                  leadingIcon: DIcon(
                    whisper ? DIcons.farEyeSlash : DIcons.reply,
                    size: 16,
                  ),
                  trailingIcon: composer.whisper == whisper
                      ? const Icon(Icons.check, size: 16)
                      : const SizedBox(width: 16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(whisper ? 'Whisper' : 'Reply'),
                        if (whisper)
                          Text(
                            'Allowed groups only',
                            style: theme.textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
            builder: (context, menu, _) => Semantics(
              button: true,
              label: composer.whisper ? 'Whisper options' : 'Reply options',
              expanded: menu.isOpen,
              child: DButton(
                key: const ValueKey('composer-reply-options'),
                onPressed: menu.isOpen ? menu.close : menu.open,
                variant: DButtonVariant.transparent,
                size: DButtonSize.small,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DIcon(
                      composer.whisper ? DIcons.farEyeSlash : DIcons.reply,
                      size: 14,
                      color: color,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(color: theme.colorScheme.onSurface),
                      ),
                    ),
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
      if (!minimized)
        DPopover(
          reverseTransitionDuration: Duration.zero,
          content: DPopoverContent(
            semanticLabel: 'Composer options',
            align: DPopoverAlign.end,
            width: 264,
            child: DPopoverClose(
              builder: (context, closeMenu) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (onPlacementChanged != null) ...[
                    Row(
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
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: DSeparator(),
                    ),
                  ],
                  DButton(
                    label: Text(closeTooltip),
                    alignment: AlignmentDirectional.centerStart,
                    variant: DButtonVariant.transparent,
                    onPressed: () {
                      closeMenu();
                      onClose();
                    },
                  ),
                  DButton(
                    key: const ValueKey('composer-discard'),
                    label: Text(
                      target.isEdit ? 'Cancel edit' : 'Discard',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    alignment: AlignmentDirectional.centerStart,
                    variant: DButtonVariant.transparent,
                    onPressed: composer.isEditing && !composer.loadingBody
                        ? () {
                            closeMenu();
                            onDiscard();
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ),
          child: DPopoverTrigger(
            builder: (context, trigger) => DButton.iconOnly(
              key: const ValueKey('composer-options'),
              icon: const DIcon(DIcons.ellipsis, size: 16),
              tooltip: 'Composer options',
              semanticLabel: 'Composer options',
              hasPopup: true,
              expanded: trigger.open,
              focusNode: trigger.focusNode,
              onPressed: trigger.toggle,
              variant: DButtonVariant.transparent,
              size: DButtonSize.small,
            ),
          ),
        ),
      if (onRestore case final restore?)
        DButton.iconOnly(
          key: const ValueKey('composer-restore'),
          onPressed: restore,
          icon: const DIcon(DIcons.expand, size: 16),
          tooltip: 'Restore composer',
          variant: DButtonVariant.transparent,
          size: DButtonSize.small,
        )
      else if (onMinimize case final minimize?)
        DButton.iconOnly(
          key: const ValueKey('composer-minimize'),
          onPressed: minimize,
          icon: const Icon(Icons.remove, size: 18),
          tooltip: 'Minimize composer',
          variant: DButtonVariant.transparent,
          size: DButtonSize.small,
        ),
      DButton.iconOnly(
        key: const ValueKey('composer-close'),
        onPressed: onClose,
        icon: const DIcon(DIcons.xmark, size: 16),
        tooltip: closeTooltip,
        variant: DButtonVariant.transparent,
        size: DButtonSize.small,
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
