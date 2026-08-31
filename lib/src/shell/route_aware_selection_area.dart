import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;

class RouteAwareSelectionArea extends StatefulWidget {
  const RouteAwareSelectionArea({
    super.key,
    this.selectionAreaKey,
    this.focusNode,
    this.selectionControls,
    this.contextMenuBuilder = _defaultContextMenuBuilder,
    this.magnifierConfiguration,
    this.onSelectionChanged,
    required this.child,
  });

  final Key? selectionAreaKey;
  final FocusNode? focusNode;
  final TextSelectionControls? selectionControls;
  final SelectableRegionContextMenuBuilder? contextMenuBuilder;
  final TextMagnifierConfiguration? magnifierConfiguration;
  final ValueChanged<SelectedContent?>? onSelectionChanged;
  final Widget child;

  static Widget _defaultContextMenuBuilder(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) => AdaptiveTextSelectionToolbar.selectableRegion(
    selectableRegionState: selectableRegionState,
  );

  @override
  State<RouteAwareSelectionArea> createState() =>
      _RouteAwareSelectionAreaState();
}

class _RouteAwareSelectionAreaState extends State<RouteAwareSelectionArea> {
  final GlobalKey _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    if (ModalRoute.isCurrentOf(context) == false) {
      return SelectionContainer.disabled(child: child);
    }

    return SelectionArea(
      key: widget.selectionAreaKey,
      focusNode: widget.focusNode,
      selectionControls: widget.selectionControls,
      contextMenuBuilder: widget.contextMenuBuilder,
      magnifierConfiguration: widget.magnifierConfiguration,
      onSelectionChanged: widget.onSelectionChanged,
      child: child,
    );
  }
}
