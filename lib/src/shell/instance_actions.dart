import 'package:flutter/material.dart';

import '../models/discourse_instance.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'platform.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

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
  });

  final DiscourseInstance instance;
  final Widget child;

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
    final asked = await showShellSheet<bool>(
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
            FilledButton.icon(
              onPressed: () => Navigator.of(sheetContext).pop(true),
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

    if (asked != true) return;
    if (!mounted) return;
    await _confirmRemoval();
  }

  Future<void> _confirmRemoval() async {
    final controller = ShellScope.of(context);
    final instance = widget.instance;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);

        return AlertDialog(
          title: Text('Remove ${instance.title}?'),
          content: Text(
            'This signs out of ${instance.host} and takes it out of the rail. '
            'Nothing on the site itself changes, and you can add it back at '
            'any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    // Nothing below touches the tree: removing the site is very often what
    // disposes this widget, since the item it belongs to goes with it.
    if (confirmed != true) return;
    await controller.removeInstance(instance);
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
