import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../models/discourse_instance.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
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

  final confirmed = await showDiscourseDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return DiscourseAlertDialog(
        title: Text('Remove ${instance.title}?'),
        content: Text(
          'This signs out of ${instance.host} and takes it out of the rail. '
          'Nothing on the site itself changes, and you can add it back at '
          'any time.',
        ),
        actions: [
          AdaptiveDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          AdaptiveDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            kind: AdaptiveDialogActionKind.destructive,
            child: const Text('Remove'),
          ),
        ],
      );
    },
  );

  if (confirmed != true || !context.mounted) return;
  if (!identical(ShellScope.read(context), controller)) return;
  final removed = await controller.removeInstance(instance);
  if (removed ||
      !context.mounted ||
      !identical(ShellScope.read(context), controller)) {
    return;
  }
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text("Couldn't remove ${instance.title}. Try again.")),
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

  final MenuController _menu = MenuController();

  void _open(Offset position) {
    if (_menu.isOpen) {
      _menu.close();
      return;
    }
    _menu.open(position: position);
  }

  void _openFromKeyboard() {
    if (_menu.isOpen) return;
    _menu.open();
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

  List<Widget> _items(ThemeData theme) {
    if (context.isTouch) {
      return [
        MenuItemButton(
          leadingIcon: const DIcon(DIcons.ellipsis, size: 18),
          onPressed: _openSheet,
          child: const Text('More Options'),
        ),
      ];
    }

    return [
      if (widget.onMoveUp != null)
        MenuItemButton(
          leadingIcon: const DIcon(DIcons.arrowUp, size: 18),
          onPressed: widget.onMoveUp,
          child: const Text('Move up'),
        ),
      if (widget.onMoveDown != null)
        MenuItemButton(
          leadingIcon: const RotatedBox(
            quarterTurns: 2,
            child: DIcon(DIcons.arrowUp, size: 18),
          ),
          onPressed: widget.onMoveDown,
          child: const Text('Move down'),
        ),
      if (widget.onMoveUp != null || widget.onMoveDown != null)
        const Divider(height: 1),
      MenuItemButton(
        leadingIcon: const DIcon(DIcons.trashCan, size: 18),
        style: MenuItemButton.styleFrom(
          foregroundColor: theme.colorScheme.error,
          iconColor: theme.colorScheme.error,
        ),
        onPressed: _confirmRemoval,
        child: const Text('Remove forum'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTouch = context.isTouch;
    final touchGestureBuilder = isTouch ? widget.touchGestureBuilder : null;
    final actionChild = GestureDetector(
      behavior: HitTestBehavior.translucent,
      // Each gesture is wired only where it means something: holding a mouse
      // button down on a desktop is not a request for a menu, and a touch
      // screen has no second button to press. A touch wrapper owns long press
      // exclusively when one is supplied, avoiding competing recognizers.
      onLongPressStart: isTouch && touchGestureBuilder == null
          ? (details) => _open(details.localPosition)
          : null,
      onSecondaryTapDown: isTouch
          ? null
          : (details) => _open(details.localPosition),
      child: widget.child,
    );
    final interactionChild = touchGestureBuilder == null
        ? actionChild
        : touchGestureBuilder(actionChild, _open);

    return MenuAnchor(
      controller: _menu,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(theme.shell.floating),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      menuChildren: _items(theme),
      child: MergeSemantics(
        child: Semantics(
          customSemanticsActions: {_showActions: _openFromKeyboard},
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.contextMenu):
                  _openFromKeyboard,
              const SingleActivator(LogicalKeyboardKey.f10, shift: true):
                  _openFromKeyboard,
            },
            child: interactionChild,
          ),
        ),
      ),
    );
  }
}

enum _InstanceSheetAction { moveUp, moveDown, remove }
