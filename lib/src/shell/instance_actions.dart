import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../discourse_ui.dart';
import '../models/discourse_instance.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_dialog_action.dart';
import 'platform.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

Future<void> confirmInstanceRemoval(
  BuildContext context,
  DiscourseInstance instance,
) async {
  final controller = ShellScope.read(context);

  final confirmed = await showDiscourseAlertDialog<bool>(
    context: context,
    title: Text('Remove ${instance.title}?'),
    description: Text(
      'This signs out of ${instance.host} and takes it out of the rail. '
      'The app will revoke this device’s access so notifications stop. '
      'You can add the forum back at any time.',
    ),
    cancelLabel: const Text('Cancel'),
    actionLabel: const Text('Remove'),
    cancelResult: false,
    actionResult: true,
    actionVariant: DButtonVariant.destructive,
  );

  if (confirmed != true || !context.mounted) return;
  if (!identical(ShellScope.read(context), controller)) return;
  final removed = await controller.removeInstance(instance);
  if (removed ||
      !context.mounted ||
      !identical(ShellScope.read(context), controller)) {
    return;
  }
  DToast.show(
    context,
    "Couldn't remove ${instance.title}. Try again.",
    type: DToastType.error,
  );
}

typedef InstanceTouchGestureBuilder =
    Widget Function(Widget child, ValueChanged<Offset> openActions);

class InstanceActions extends StatefulWidget {
  const InstanceActions({
    super.key,
    required this.instance,
    required this.child,
    this.onMoveUp,
    this.onMoveDown,
    this.touchGestureBuilder,
  });

  final DiscourseInstance instance;
  final Widget child;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  final InstanceTouchGestureBuilder? touchGestureBuilder;

  @override
  State<InstanceActions> createState() => _InstanceActionsState();
}

class _InstanceActionsState extends State<InstanceActions> {
  static const _showActions = CustomSemanticsAction(
    label: 'Show forum actions',
  );

  final DContextMenuController _menu = DContextMenuController();
  final DContextMenuTriggerController _trigger =
      DContextMenuTriggerController();

  void _open(Offset position) {
    if (_menu.isOpen) {
      _menu.close();
      return;
    }
    _trigger.openAt(
      position,
      interaction: context.isTouch
          ? DPopoverInteraction.touch
          : DPopoverInteraction.mouse,
    );
  }

  void _openFromKeyboard() {
    if (_menu.isOpen) return;
    _trigger.openFromKeyboard();
  }

  Future<void> _openSheet() async {
    final asked = await showShellSheet<_InstanceSheetAction>(
      context: context,
      title: widget.instance.title,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.instance.host,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (widget.onMoveUp != null || widget.onMoveDown != null) ...[
              Row(
                children: [
                  Expanded(
                    child: DButton(
                      label: const Text('Move up'),
                      onPressed: widget.onMoveUp == null
                          ? null
                          : () => Navigator.of(
                              sheetContext,
                            ).pop(_InstanceSheetAction.moveUp),
                      icon: const DIcon(DIcons.arrowUp, size: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DButton(
                      label: const Text('Move down'),
                      onPressed: widget.onMoveDown == null
                          ? null
                          : () => Navigator.of(
                              sheetContext,
                            ).pop(_InstanceSheetAction.moveDown),
                      icon: const RotatedBox(
                        quarterTurns: 2,
                        child: DIcon(DIcons.arrowUp, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            DButton(
              label: const Text('Remove forum'),
              onPressed: () =>
                  Navigator.of(sheetContext).pop(_InstanceSheetAction.remove),
              icon: const DIcon(DIcons.trashCan, size: 18),
              variant: DButtonVariant.danger,
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    switch (asked) {
      case _InstanceSheetAction.moveUp:
        widget.onMoveUp?.call();
      case _InstanceSheetAction.moveDown:
        widget.onMoveDown?.call();
      case _InstanceSheetAction.remove:
        await _confirmRemoval();
      case null:
        return;
    }
  }

  Future<void> _confirmRemoval() async {
    await confirmInstanceRemoval(context, widget.instance);
  }

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  List<Widget> _items() {
    if (context.isTouch) {
      return [
        DContextMenuItem(
          leading: const DIcon(DIcons.ellipsis, size: 16),
          onPressed: _openSheet,
          child: const Text('More Options'),
        ),
      ];
    }

    return [
      if (widget.onMoveUp != null)
        DContextMenuItem(
          leading: const DIcon(DIcons.arrowUp, size: 16),
          onPressed: widget.onMoveUp,
          child: const Text('Move up'),
        ),
      if (widget.onMoveDown != null)
        DContextMenuItem(
          leading: const RotatedBox(
            quarterTurns: 2,
            child: DIcon(DIcons.arrowUp, size: 16),
          ),
          onPressed: widget.onMoveDown,
          child: const Text('Move down'),
        ),
      if (widget.onMoveUp != null || widget.onMoveDown != null)
        const DContextMenuSeparator(),
      DContextMenuItem(
        leading: const DIcon(DIcons.trashCan, size: 16),
        variant: DContextMenuItemVariant.destructive,
        onPressed: _confirmRemoval,
        child: const Text('Remove forum'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isTouch = context.isTouch;
    final touchGestureBuilder = isTouch ? widget.touchGestureBuilder : null;
    final interactionChild = touchGestureBuilder == null
        ? widget.child
        : touchGestureBuilder(widget.child, _open);

    return DContextMenu(
      controller: _menu,
      content: DContextMenuContent(
        width: 176,
        semanticLabel: 'Forum actions',
        children: _items(),
      ),
      child: MergeSemantics(
        child: Semantics(
          customSemanticsActions: {_showActions: _openFromKeyboard},
          child: DContextMenuTrigger(
            controller: _trigger,
            focusable: false,
            longPressEnabled: touchGestureBuilder == null,
            child: interactionChild,
          ),
        ),
      ),
    );
  }
}

enum _InstanceSheetAction { moveUp, moveDown, remove }
