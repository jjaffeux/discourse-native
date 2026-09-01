import '../composer_document/component.dart';
import '../composer_document/projection.dart';
import '../composer_document/source.dart';
import 'component.dart';

const composerSurfaceObjectReplacementCharacter = '\uFFFC';

enum ComposerSurfaceAtomAffinity { before, after }

/// A half-open UTF-16 range in the raw-free projected surface buffer.
final class ComposerSurfaceRange {
  const ComposerSurfaceRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;
  bool get isCollapsed => start == end;
  bool get isWellFormed => start >= 0 && end >= start;

  bool isValidForLength(int surfaceLength) {
    return isWellFormed && end <= surfaceLength;
  }

  @override
  bool operator ==(Object other) {
    return other is ComposerSurfaceRange &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'ComposerSurfaceRange($start, $end)';
}

/// The canonical and projected boundaries of one compressed component atom.
final class ComposerSurfaceAtomMapping {
  const ComposerSurfaceAtomMapping({
    required this.surfaceOffset,
    required this.component,
  });

  /// Offset of the single object-replacement character.
  final int surfaceOffset;
  final ComposerSurfaceComponent component;

  int get surfaceBefore => surfaceOffset;
  int get surfaceAfter => surfaceOffset + 1;
  int get sourceBefore => component.sourceRange.start;
  int get sourceAfter => component.sourceRange.end;
}

sealed class ComposerSurfaceProjectedNode {
  const ComposerSurfaceProjectedNode({required this.id});

  final String id;
}

final class ComposerSurfaceProjectedTextNode
    extends ComposerSurfaceProjectedNode {
  const ComposerSurfaceProjectedTextNode({
    required super.id,
    required this.text,
    required this.inlineComponents,
  });

  /// Text without object-replacement characters.
  final String text;

  /// Inline components keyed by their final logical offset, including earlier
  /// placeholders in the offset count.
  final Map<int, ComposerSurfaceComponent> inlineComponents;

  String get projectedText {
    if (inlineComponents.isEmpty) return text;

    final buffer = StringBuffer();
    var textOffset = 0;
    var insertedComponents = 0;
    for (final offset in inlineComponents.keys) {
      final nextTextOffset = offset - insertedComponents;
      buffer
        ..write(text.substring(textOffset, nextTextOffset))
        ..write(composerSurfaceObjectReplacementCharacter);
      textOffset = nextTextOffset;
      insertedComponents += 1;
    }
    buffer.write(text.substring(textOffset));
    return buffer.toString();
  }
}

final class ComposerSurfaceProjectedBlockNode
    extends ComposerSurfaceProjectedNode {
  const ComposerSurfaceProjectedBlockNode({
    required super.id,
    required this.component,
  });

  final ComposerSurfaceComponent component;
}

final class ComposerSurfaceProjectionPlan {
  ComposerSurfaceProjectionPlan._({
    required this.nodes,
    required this.sourceLength,
  }) : snapshot = _createSnapshot(nodes) {
    atoms = List.unmodifiable(_positionAtoms(nodes));
    componentsBySurfaceOffset = Map.unmodifiable({
      for (final atom in atoms) atom.surfaceOffset: atom.component,
    });
  }

  factory ComposerSurfaceProjectionPlan.fromProjection(
    ComposerProjection projection,
  ) {
    final nodes = <ComposerSurfaceProjectedNode>[];
    var nodeOrdinal = 0;
    var text = StringBuffer();
    var inlineComponents = <int, ComposerSurfaceComponent>{};

    void flushText() {
      if (text.isEmpty && inlineComponents.isEmpty) return;
      nodes.add(
        ComposerSurfaceProjectedTextNode(
          id:
              'composer-surface-text-${projection.revision.value}-'
              '${nodeOrdinal++}',
          text: text.toString(),
          inlineComponents: Map.unmodifiable(inlineComponents),
        ),
      );
      text = StringBuffer();
      inlineComponents = <int, ComposerSurfaceComponent>{};
    }

    for (final segment in projection.segments) {
      switch (segment) {
        case ComposerTextSegment():
          text.write(segment.source);
        case ComposerComponentSegment(:final match):
          final component = _toSurfaceComponent(match);
          switch (match.layout) {
            case ComposerComponentLayout.inline:
              final surfaceOffset = text.length + inlineComponents.length;
              inlineComponents[surfaceOffset] = component;
            case ComposerComponentLayout.block:
              flushText();
              nodes.add(
                ComposerSurfaceProjectedBlockNode(
                  id:
                      'composer-surface-block-${projection.revision.value}-'
                      '${nodeOrdinal++}',
                  component: component,
                ),
              );
          }
      }
    }
    flushText();

    if (nodes.isEmpty) {
      nodes.add(
        ComposerSurfaceProjectedTextNode(
          id: 'composer-surface-text-${projection.revision.value}-0',
          text: '',
          inlineComponents: const {},
        ),
      );
    }

    return ComposerSurfaceProjectionPlan._(
      nodes: List.unmodifiable(nodes),
      sourceLength: projection.source.length,
    );
  }

  final List<ComposerSurfaceProjectedNode> nodes;
  final int sourceLength;
  late final List<ComposerSurfaceAtomMapping> atoms;
  late final Map<int, ComposerSurfaceComponent> componentsBySurfaceOffset;
  final ComposerSurfaceSnapshot snapshot;

  int get surfaceLength => snapshot.projectedText.length;

  ComposerSurfaceComponent? componentAtSurfaceOffset(int surfaceOffset) {
    if (surfaceOffset < 0 || surfaceOffset >= surfaceLength) {
      throw RangeError.range(
        surfaceOffset,
        0,
        surfaceLength - 1,
        'surfaceOffset',
      );
    }
    return componentsBySurfaceOffset[surfaceOffset];
  }

  /// Maps a canonical source boundary into the projected surface.
  ///
  /// A boundary strictly inside an atom has no exact projected equivalent, so
  /// [affinity] chooses the boundary before or after that atom.
  int surfaceBoundaryForSourceBoundary(
    int sourceOffset, {
    ComposerSurfaceAtomAffinity affinity = ComposerSurfaceAtomAffinity.before,
  }) {
    _checkSourceBoundary(sourceOffset);
    var compressedCodeUnits = 0;
    for (final atom in atoms) {
      if (sourceOffset < atom.sourceBefore) break;
      if (sourceOffset == atom.sourceBefore) return atom.surfaceBefore;
      if (sourceOffset < atom.sourceAfter) {
        return affinity == ComposerSurfaceAtomAffinity.before
            ? atom.surfaceBefore
            : atom.surfaceAfter;
      }
      if (sourceOffset == atom.sourceAfter) return atom.surfaceAfter;
      compressedCodeUnits += atom.component.sourceRange.length - 1;
    }
    return sourceOffset - compressedCodeUnits;
  }

  /// Maps an exact projected boundary back into canonical source.
  int sourceBoundaryForSurfaceBoundary(int surfaceOffset) {
    _checkSurfaceBoundary(surfaceOffset);
    var expandedCodeUnits = 0;
    for (final atom in atoms) {
      if (surfaceOffset < atom.surfaceBefore) break;
      if (surfaceOffset == atom.surfaceBefore) return atom.sourceBefore;
      if (surfaceOffset == atom.surfaceAfter) return atom.sourceAfter;
      expandedCodeUnits += atom.component.sourceRange.length - 1;
    }
    return surfaceOffset + expandedCodeUnits;
  }

  /// Expands every selected projected atom back to its complete source span.
  ComposerSourceRange sourceRangeForSurfaceRange(ComposerSurfaceRange range) {
    if (!range.isValidForLength(surfaceLength)) {
      throw RangeError('Surface range $range is outside length $surfaceLength');
    }
    return ComposerSourceRange(
      sourceBoundaryForSurfaceBoundary(range.start),
      sourceBoundaryForSurfaceBoundary(range.end),
    );
  }

  void _checkSourceBoundary(int sourceOffset) {
    if (sourceOffset < 0 || sourceOffset > sourceLength) {
      throw RangeError.range(sourceOffset, 0, sourceLength, 'sourceOffset');
    }
  }

  void _checkSurfaceBoundary(int surfaceOffset) {
    if (surfaceOffset < 0 || surfaceOffset > surfaceLength) {
      throw RangeError.range(surfaceOffset, 0, surfaceLength, 'surfaceOffset');
    }
  }

  static List<ComposerSurfaceAtomMapping> _positionAtoms(
    List<ComposerSurfaceProjectedNode> nodes,
  ) {
    final atoms = <ComposerSurfaceAtomMapping>[];
    var surfaceOffset = 0;
    for (final node in nodes) {
      switch (node) {
        case ComposerSurfaceProjectedTextNode():
          for (final entry in node.inlineComponents.entries) {
            atoms.add(
              ComposerSurfaceAtomMapping(
                surfaceOffset: surfaceOffset + entry.key,
                component: entry.value,
              ),
            );
          }
          surfaceOffset += node.projectedText.length;
        case ComposerSurfaceProjectedBlockNode():
          atoms.add(
            ComposerSurfaceAtomMapping(
              surfaceOffset: surfaceOffset,
              component: node.component,
            ),
          );
          surfaceOffset += 1;
      }
    }
    return atoms;
  }

  static ComposerSurfaceSnapshot _createSnapshot(
    List<ComposerSurfaceProjectedNode> nodes,
  ) {
    final snapshots = <ComposerSurfaceNodeSnapshot>[];
    var inlineCount = 0;
    var blockCount = 0;
    for (final node in nodes) {
      switch (node) {
        case ComposerSurfaceProjectedTextNode():
          inlineCount += node.inlineComponents.length;
          snapshots.add(
            ComposerSurfaceNodeSnapshot(
              layout: ComposerSurfaceNodeLayout.text,
              projectedText: node.projectedText,
            ),
          );
        case ComposerSurfaceProjectedBlockNode():
          blockCount += 1;
          snapshots.add(
            const ComposerSurfaceNodeSnapshot(
              layout: ComposerSurfaceNodeLayout.block,
              projectedText: composerSurfaceObjectReplacementCharacter,
            ),
          );
      }
    }

    return ComposerSurfaceSnapshot(
      nodes: List.unmodifiable(snapshots),
      projectedText: snapshots.map((node) => node.projectedText).join(),
      inlineComponentCount: inlineCount,
      blockComponentCount: blockCount,
    );
  }
}

ComposerSurfaceComponent _toSurfaceComponent(
  ComposerComponentMatch<Object> match,
) {
  return ComposerSurfaceComponent(
    revision: match.revision,
    kind: match.kind,
    layout: match.layout,
    sourceRange: match.range,
    value: match.value,
  );
}
