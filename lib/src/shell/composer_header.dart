import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'composer_controller.dart';
import 'platform.dart';
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
    this.onMove,
    this.onMoveEnd,
  });

  static const double height = 44;

  final ComposerController composer;
  final bool minimized;
  final VoidCallback onClose;
  final String closeTooltip;
  final VoidCallback onDiscard;
  final VoidCallback? onMinimize;
  final VoidCallback? onRestore;
  final ValueChanged<Offset>? onMove;
  final VoidCallback? onMoveEnd;

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
        MenuAnchor(
          menuChildren: [
            MenuItemButton(onPressed: onClose, child: Text(closeTooltip)),
            MenuItemButton(
              key: const ValueKey('composer-discard'),
              onPressed: composer.isEditing && !composer.loadingBody
                  ? onDiscard
                  : null,
              leadingIcon: const Icon(Icons.delete_outline, size: 18),
              child: Text(
                target.isEdit ? 'Cancel edit' : 'Discard',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
          builder: (context, menu, _) => IconButton(
            key: const ValueKey('composer-options'),
            onPressed: menu.isOpen ? menu.close : menu.open,
            icon: const DIcon(DIcons.ellipsis, size: 16),
            tooltip: 'Composer options',
          ),
        ),
      if (onRestore case final restore?)
        IconButton(
          key: const ValueKey('composer-restore'),
          onPressed: restore,
          icon: const DIcon(DIcons.expand, size: 16),
          tooltip: 'Restore composer',
        )
      else if (onMinimize case final minimize?)
        IconButton(
          key: const ValueKey('composer-minimize'),
          onPressed: minimize,
          icon: const Icon(Icons.remove, size: 18),
          tooltip: 'Minimize composer',
        ),
      IconButton(
        onPressed: onClose,
        icon: const DIcon(DIcons.xmark, size: 16),
        tooltip: closeTooltip,
      ),
    ];
    final grip = onMove == null
        ? null
        : _ComposerGrip(onMove: onMove!, onMoveEnd: onMoveEnd);
    final header = SizedBox(
      key: const ValueKey('composer-drag-handle'),
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: IconButtonTheme(
          data: IconButtonThemeData(
            style: IconButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurfaceVariant,
              minimumSize: Size.square(context.isTouch ? 44 : 32),
              padding: const EdgeInsets.all(6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: heading),
              ),
              ?grip,
              if (grip != null)
                // Equal side widths keep the grip centered as controls change.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final control in controls)
                          Flexible(child: control),
                      ],
                    ),
                  ),
                )
              else
                Row(mainAxisSize: MainAxisSize.min, children: controls),
            ],
          ),
        ),
      ),
    );
    if (onMove == null) return header;
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanUpdate: (details) => onMove!(details.delta),
        onPanEnd: (_) => onMoveEnd?.call(),
        child: header,
      ),
    );
  }
}

class _ComposerGrip extends StatelessWidget {
  const _ComposerGrip({required this.onMove, this.onMoveEnd});

  final ValueChanged<Offset> onMove;
  final VoidCallback? onMoveEnd;

  void _move(Offset delta) {
    onMove(delta);
    onMoveEnd?.call();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
          _move(const Offset(-8, 0)),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
          _move(const Offset(8, 0)),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
          _move(const Offset(0, -8)),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
          _move(const Offset(0, 8)),
    },
    child: Focus(
      child: Tooltip(
        message: 'Drag composer',
        child: Semantics(
          label: 'Move composer',
          hint: 'Drag or use arrow keys',
          child: Builder(
            builder: (context) => Container(
              key: const ValueKey('composer-move-control'),
              width: 28,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Focus.of(context).hasFocus
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                ),
              ),
              child: RotatedBox(
                quarterTurns: 1,
                child: Icon(
                  Icons.drag_indicator,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  static const double height = ComposerHeader.height;
}
