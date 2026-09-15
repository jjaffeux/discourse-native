import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/d_icons.dart';
import 'instance_sidebar.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

/// Keeps navigation available when reading and writing need the window width.
class DesktopNavigation extends StatefulWidget {
  const DesktopNavigation({
    super.key,
    required this.compact,
    required this.sidebar,
    required this.child,
  });

  final bool compact;
  final Widget sidebar;
  final Widget child;

  @override
  State<DesktopNavigation> createState() => _DesktopNavigationState();
}

class _DesktopNavigationState extends State<DesktopNavigation> {
  bool _open = false;
  ShellController? _shell;
  Object? _owner;

  Object _navigationOwner() => (
    _shell!.currentInstance?.url,
    _shell!.activeTabId,
    _shell!.currentContent,
    _shell!.rootMode,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = ShellScope.read(context);
    if (identical(shell, _shell)) return;
    _shell?.removeListener(_navigationChanged);
    _shell = shell..addListener(_navigationChanged);
    _owner = _navigationOwner();
  }

  void _navigationChanged() {
    final owner = _navigationOwner();
    if (owner == _owner) return;
    _owner = owner;
    if (_open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _open) setState(() => _open = false);
      });
    }
  }

  @override
  void didUpdateWidget(DesktopNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.compact) _open = false;
  }

  @override
  void dispose() {
    _shell?.removeListener(_navigationChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => DPopover(
      open: _open && widget.compact,
      onOpenChange: (open, _) {
        if (open != _open) setState(() => _open = open);
      },
      content: DPopoverContent(
        semanticLabel: 'Community navigation',
        align: DPopoverAlign.start,
        width: 288,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: math.max(120, math.min(600, bounds.maxHeight - 44)),
          child: const InstanceSidebar(),
        ),
      ),
      child: Row(
        children: [
          Offstage(offstage: widget.compact, child: widget.sidebar),
          Expanded(
            child: Column(
              children: [
                if (widget.compact)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsets.all(DSpacing.xs),
                      child: DPopoverTrigger(
                        builder: (context, trigger) => DButton(
                          key: const ValueKey('desktop-navigation-trigger'),
                          label: const Text('Navigation'),
                          icon: const DIcon(DIcons.list),
                          variant: DButtonVariant.ghost,
                          expanded: trigger.open,
                          hasPopup: true,
                          focusNode: trigger.focusNode,
                          onPressed: trigger.toggle,
                        ),
                      ),
                    ),
                  ),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
