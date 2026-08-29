import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;

/// Enables multi-widget selection only while the enclosing route is current.
///
/// Flutter keeps covered routes mounted while its overlay deliberately skips
/// laying them out. A [SelectionArea] in such a route can retain unlaid-out
/// paragraphs and later crash while sorting them by screen position. Removing
/// the area while the route is covered unregisters those paragraphs. The
/// global-keyed subtree preserves the content's state across that change.
///
/// See https://github.com/flutter/flutter/issues/151536.
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
