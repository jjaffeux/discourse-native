import 'dart:async';

import 'package:flutter/material.dart';

import '../foundation/control_style.dart';
import 'd_button.dart';
import 'd_popover.dart';
import 'd_toggle_group.dart';

/// A position trigger that unfolds leftward at its own location.
/// The popup owns collision correction, outside/Escape dismissal and focus;
/// the Native toggle group owns selection and the sliding surface.
class DPositionControl<T extends Object> extends StatefulWidget {
  const DPositionControl({
    super.key,
    required this.value,
    required this.items,
    required this.icon,
    required this.label,
    required this.onChanged,
    this.triggerKey,
  });
  final T value;
  final List<DToggleGroupItem<T>> items;
  final Widget icon;
  final String label;
  final ValueChanged<T> onChanged;
  final Key? triggerKey;
  @override
  State<DPositionControl<T>> createState() => _DPositionControlState<T>();
}

class _DPositionControlState<T extends Object>
    extends State<DPositionControl<T>>
    with SingleTickerProviderStateMixin {
  late final _unfold = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  bool _open = false;
  Timer? _fold;
  late final _selection = DToggleGroupController<T>(values: [widget.value]);
  @override
  void dispose() {
    _fold?.cancel();
    _selection.dispose();
    _unfold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final extent = DControlStyle.scaledHeight(
      DControlSize.toolbar,
      MediaQuery.textScalerOf(context),
      context: context,
    );
    final expandedWidth =
        widget.items.length * extent + (widget.items.length - 1) * 2 + 6;
    final foldedFraction = (extent + 6) / expandedWidth;
    return DPopover(
      open: _open,
      restoreFocus: false,
      transitionDuration: reduced
          ? Duration.zero
          : const Duration(milliseconds: 180),
      reverseTransitionDuration: reduced
          ? Duration.zero
          : const Duration(milliseconds: 180),
      onOpenChange: (open, _) {
        _fold?.cancel();
        if (reduced) {
          _unfold.value = open ? 1 : 0;
        } else if (open) {
          _unfold.forward(from: 0);
        } else {
          _unfold.reverse();
        }
        setState(() {
          _open = open;
          _selection.setValues([widget.value]);
        });
      },
      content: DPopoverContent(
        semanticLabel: widget.label,
        width: null,
        padding: EdgeInsets.zero,
        scrollable: false,
        placementResolver: (placement) => Offset(
          placement.target.right - placement.contentSize.width + 3,
          placement.target.center.dy - placement.contentSize.height / 2,
        ),
        child: AnimatedBuilder(
          animation: _unfold,
          builder: (context, child) => ClipRect(
            child: Align(
              alignment: Alignment.centerRight,
              heightFactor: 1,
              widthFactor:
                  foldedFraction +
                  (1 - foldedFraction) *
                      Curves.easeInOut.transform(_unfold.value),
              child: child,
            ),
          ),
          child: SizedBox(
            width: expandedWidth,
            child: DToggleGroup<T>(
              semanticLabel: widget.label,
              size: DControlSize.toolbar,
              controller: _selection,
              inset: true,
              slidingIndicator: true,
              allowEmptySelection: false,
              onChanged: (_) {},
              onItemActivated: (value) {
                _selection.setValues([value]);
                if (value != widget.value) widget.onChanged(value);
                _fold?.cancel();
                _fold = Timer(
                  reduced ? Duration.zero : const Duration(milliseconds: 260),
                  () {
                    if (mounted) {
                      if (reduced) {
                        _unfold.value = 0;
                      } else {
                        _unfold.reverse();
                      }
                      setState(() => _open = false);
                    }
                  },
                );
              },
              items: widget.items,
            ),
          ),
        ),
      ),
      child: DPopoverTrigger(
        builder: (context, trigger) => IgnorePointer(
          ignoring: trigger.open,
          child: Opacity(
            opacity: trigger.open ? 0 : 1,
            child: DButton.iconOnly(
              key: widget.triggerKey,
              icon: widget.icon,
              tooltip: widget.label,
              semanticLabel: widget.label,
              hasPopup: true,
              expanded: trigger.open,
              focusNode: trigger.focusNode,
              variant: DButtonVariant.ghost,
              size: DButtonSize.toolbar,
              onPressed: trigger.toggle,
            ),
          ),
        ),
      ),
    );
  }
}
