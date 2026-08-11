import 'package:flutter/material.dart';

import '../models/discourse_instance.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_dialog_action.dart';
import 'platform.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

/// Asks before removing [instance], then performs the removal through the
/// shell that owns it. Both the rail's context actions and the sidebar header
/// menu use this path so signing out behaves the same from either affordance.
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

/// What can be done with one site in the rail, kept behind the gesture each
/// platform already means "what else can this do": a right click with a
/// pointer, a long press on a touch screen.
///
/// The two do not arrive at the same place. A pointer lands on a small menu row
/// exactly where it was aimed, so removing the site is offered there directly.
/// A thumb does not — and the press that opened the menu ends somewhere inside
/// it — so on touch the menu only leads to More Options, and the destructive
/// button waits in a sheet, deliberately one deliberate tap further away.
///
/// Both paths end at the same confirmation: removing a site signs it out, and
/// nothing here should be able to do that by accident.
class InstanceActions extends StatefulWidget {
  const InstanceActions({
    super.key,
    required this.instance,
    required this.child,
    this.onMoveUp,
    this.onMoveDown,
  });

  final DiscourseInstance instance;
  final Widget child;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  State<InstanceActions> createState() => _InstanceActionsState();
}

class _InstanceActionsState extends State<InstanceActions> {
  final MenuController _menu = MenuController();

  /// Opens at the pointer or thumb rather than at the item's corner, which is
  /// what a context menu is expected to do — and the rail is only 72 wide, so
  /// a menu pinned to it would be almost entirely over the panel anyway.
  void _open(Offset position) {
    if (_menu.isOpen) {
      _menu.close();
      return;
    }
    _menu.open(position: position);
  }

  /// The touch path: everything the menu could not sensibly hold, full width
  /// and far enough from the press that opened it.
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
                    child: OutlinedButton.icon(
                      onPressed: widget.onMoveUp == null
                          ? null
                          : () => Navigator.of(
                              sheetContext,
                            ).pop(_InstanceSheetAction.moveUp),
                      icon: const DIcon(DIcons.arrowUp, size: 18),
                      label: const Text('Move up'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onMoveDown == null
                          ? null
                          : () => Navigator.of(
                              sheetContext,
                            ).pop(_InstanceSheetAction.moveDown),
                      icon: const RotatedBox(
                        quarterTurns: 2,
                        child: DIcon(DIcons.arrowUp, size: 18),
                      ),
                      label: const Text('Move down'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(sheetContext).pop(_InstanceSheetAction.remove),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              icon: const DIcon(DIcons.trashCan, size: 18),
              label: const Text('Remove forum'),
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

    return MenuAnchor(
      controller: _menu,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(theme.shell.floating),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      menuChildren: _items(theme),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Each gesture is wired only where it means something: holding a mouse
        // button down on a desktop is not a request for a menu, and a touch
        // screen has no second button to press.
        onLongPressStart: context.isTouch
            ? (details) => _open(details.localPosition)
            : null,
        onSecondaryTapDown: context.isTouch
            ? null
            : (details) => _open(details.localPosition),
        child: widget.child,
      ),
    );
  }
}

enum _InstanceSheetAction { moveUp, moveDown, remove }
