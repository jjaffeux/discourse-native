import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show Selectable, SelectedContent, SelectionRegistrar;

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
    final child = _StableSelectionRegistrar(
      key: _childKey,
      child: widget.child,
    );
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

// Sliver selection keep-alives assume their registrar remains non-null during
// removal and disposal. Keep this scope alive with the reparented content while
// disconnecting its selectables from the covered route's SelectionArea.
class _StableSelectionRegistrar extends StatefulWidget {
  const _StableSelectionRegistrar({super.key, required this.child});

  final Widget child;

  @override
  State<_StableSelectionRegistrar> createState() =>
      _StableSelectionRegistrarState();
}

class _StableSelectionRegistrarState extends State<_StableSelectionRegistrar>
    implements SelectionRegistrar {
  final Set<Selectable> _selectables = {};
  SelectionRegistrar? _registrar;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registrar = SelectionContainer.maybeOf(context);
    if (identical(registrar, _registrar)) {
      return;
    }
    for (final selectable in _selectables) {
      _registrar?.remove(selectable);
    }
    _registrar = registrar;
    for (final selectable in _selectables) {
      _registrar?.add(selectable);
    }
  }

  @override
  void add(Selectable selectable) {
    if (_selectables.add(selectable)) {
      _registrar?.add(selectable);
    }
  }

  @override
  void remove(Selectable selectable) {
    if (_selectables.remove(selectable)) {
      _registrar?.remove(selectable);
    }
  }

  @override
  void dispose() {
    for (final selectable in _selectables) {
      _registrar?.remove(selectable);
    }
    _registrar = null;
    _selectables.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SelectionRegistrarScope(registrar: this, child: widget.child);
}
