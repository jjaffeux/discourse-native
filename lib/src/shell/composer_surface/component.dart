import 'package:flutter/widgets.dart';

import '../composer_document/component.dart';
import '../composer_document/source.dart';

typedef ComposerSurfaceWidgetBuilder =
    Widget Function(BuildContext context, ComposerSurfaceComponent component);

typedef ComposerSurfaceSemanticLabelBuilder =
    String Function(BuildContext context, ComposerSurfaceComponent component);

/// The component data exposed to projected-surface renderers.
///
/// Canonical source is deliberately absent. Renderers receive the typed parser
/// value and a source range, so the editor surface cannot accidentally display
/// component syntax.
@immutable
final class ComposerSurfaceComponent {
  const ComposerSurfaceComponent({
    required this.revision,
    required this.kind,
    required this.layout,
    required this.sourceRange,
    required this.value,
  });

  final ComposerRevision revision;
  final ComposerComponentKind kind;
  final ComposerComponentLayout layout;
  final ComposerSourceRange sourceRange;
  final Object value;

  /// A stable key for locating the rendered component widget.
  Key get widgetKey => ValueKey<String>(
    'composer-surface-${layout.name}-${kind.value}-'
    '${sourceRange.start}-${sourceRange.end}',
  );
}

/// App-owned rendering callbacks, indexed by parsed component kind.
///
/// Missing kinds render a zero-sized placeholder instead of exposing their raw
/// source. This lets source remain lossless while a plugin renderer is loading
/// or unavailable.
@immutable
final class ComposerSurfaceComponents {
  ComposerSurfaceComponents({
    required Map<ComposerComponentKind, ComposerSurfaceWidgetBuilder> widgets,
    Map<ComposerComponentKind, ComposerSurfaceSemanticLabelBuilder>
        semanticLabels =
        const {},
  }) : _widgets = Map.unmodifiable(widgets),
       _semanticLabels = Map.unmodifiable(semanticLabels);

  final Map<ComposerComponentKind, ComposerSurfaceWidgetBuilder> _widgets;
  final Map<ComposerComponentKind, ComposerSurfaceSemanticLabelBuilder>
  _semanticLabels;

  Widget build(BuildContext context, ComposerSurfaceComponent component) {
    final child =
        _widgets[component.kind]?.call(context, component) ??
        const SizedBox.shrink();
    final label =
        _semanticLabels[component.kind]?.call(context, component) ??
        component.kind.value;

    return Semantics(
      key: component.widgetKey,
      container: true,
      label: label,
      child: child,
    );
  }
}

enum ComposerSurfaceNodeLayout { text, block }

/// A SuperEditor-free inspection of one projected surface node.
@immutable
final class ComposerSurfaceNodeSnapshot {
  const ComposerSurfaceNodeSnapshot({
    required this.layout,
    required this.projectedText,
  });

  final ComposerSurfaceNodeLayout layout;
  final String projectedText;
}

/// A SuperEditor-free inspection of the buffer handed to the surface.
@immutable
final class ComposerSurfaceSnapshot {
  const ComposerSurfaceSnapshot({
    required this.nodes,
    required this.projectedText,
    required this.inlineComponentCount,
    required this.blockComponentCount,
  });

  final List<ComposerSurfaceNodeSnapshot> nodes;
  final String projectedText;
  final int inlineComponentCount;
  final int blockComponentCount;
}

/// Read-only project-owned access to the currently projected surface buffer.
final class ComposerSurfaceController {
  ComposerSurfaceSnapshot? _snapshot;

  ComposerSurfaceSnapshot? get snapshot => _snapshot;

  void updateSnapshot(ComposerSurfaceSnapshot snapshot) {
    _snapshot = snapshot;
  }
}
