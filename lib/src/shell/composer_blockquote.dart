import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'markdown_highlight.dart';
import 'quote_panel.dart';

final _prefix = RegExp(r'^ {0,3}>+(?:[ \t]>+)*[ \t]', multiLine: true);

List<TextRange> composerBlockquotePrefixes(
  String source, {
  CodeRanges? knownCodeRanges,
}) {
  final matches = _prefix.allMatches(source).toList();
  if (matches.isEmpty) return const [];
  final code = knownCodeRanges ?? CodeRanges.of(scanMarkdown(source));
  return [
    for (final match in matches)
      if (!code.overlaps(match.start, match.end))
        TextRange(start: match.start, end: match.end),
  ];
}

/// Marks an editable quote line in the projected text without painting its body.
class ComposerBlockquoteMarker extends StatelessWidget {
  const ComposerBlockquoteMarker({
    super.key,
    required this.baseStyle,
    required this.depth,
    required this.range,
  });

  final TextStyle baseStyle;
  final int depth;
  final TextRange range;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Quote',
    child: SizedBox(
      // Keep a measurable endpoint for the caret on an empty quote line.
      width: 1,
      height: (baseStyle.fontSize ?? 14) * (baseStyle.height ?? 1.2),
    ),
  );
}

/// Paints quote panels behind the native editable text, using its actual layout.
class ComposerBlockquoteDecoration extends SingleChildRenderObjectWidget {
  const ComposerBlockquoteDecoration({
    super.key,
    required this.repaint,
    required super.child,
  });

  static const gutter = 12.0;

  final Listenable repaint;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final theme = Theme.of(context);
    return _RenderComposerBlockquoteDecoration(
      repaint,
      theme.shell.panel,
      theme.colorScheme.primary,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    final theme = Theme.of(context);
    (renderObject as _RenderComposerBlockquoteDecoration).update(
      repaint,
      theme.shell.panel,
      theme.colorScheme.primary,
    );
  }
}

class _RenderComposerBlockquoteDecoration extends RenderPadding {
  _RenderComposerBlockquoteDecoration(
    this._repaint,
    this._background,
    this._bar,
  ) : super(
        padding: const EdgeInsets.only(
          right: ComposerBlockquoteDecoration.gutter,
        ),
      );

  Listenable _repaint;
  Color _background;
  Color _bar;

  // Quotes use the composer's existing outer margin. Keeping the gutter out of
  // the editable's layout lets ordinary lines start at the field's left edge.
  @override
  Rect get paintBounds => Rect.fromLTRB(
    -ComposerBlockquoteDecoration.gutter,
    0,
    size.width,
    size.height,
  );

  void update(Listenable repaint, Color background, Color bar) {
    if (!identical(repaint, _repaint)) {
      if (attached) _repaint.removeListener(markNeedsPaint);
      _repaint = repaint;
      if (attached) _repaint.addListener(markNeedsPaint);
    }
    _background = background;
    _bar = bar;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _repaint.removeListener(markNeedsPaint);
    super.detach();
  }

  RenderEditable? _findEditable(RenderObject object) {
    if (object is RenderEditable) return object;
    RenderEditable? result;
    object.visitChildren((child) => result ??= _findEditable(child));
    return result;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final editable = child == null ? null : _findEditable(child!);
    if (editable != null) {
      final markers = <ComposerBlockquoteMarker>[];
      editable.text?.visitChildren((span) {
        if (span is WidgetSpan && span.child is ComposerBlockquoteMarker) {
          markers.add(span.child as ComposerBlockquoteMarker);
        }
        return true;
      });
      final transform = editable.getTransformTo(this);
      final panels = <({Rect rect, int end, int depth})>[];
      for (final marker in markers) {
        Rect? bounds;
        for (final box in editable.getBoxesForSelection(
          TextSelection(
            baseOffset: marker.range.start,
            extentOffset: marker.range.end,
          ),
        )) {
          if (box.bottom <= box.top) continue;
          final rect = MatrixUtils.transformRect(transform, box.toRect());
          bounds = bounds?.expandToInclude(rect) ?? rect;
        }
        if (bounds == null) continue;
        var panel = Rect.fromLTRB(
          -ComposerBlockquoteDecoration.gutter,
          bounds.top,
          size.width,
          bounds.bottom,
        );
        if (panels.isNotEmpty &&
            panels.last.end + 1 == marker.range.start &&
            panels.last.depth == marker.depth) {
          panel = panels.removeLast().rect.expandToInclude(panel);
        }
        panels.add((rect: panel, end: marker.range.end, depth: marker.depth));
      }

      final canvas = context.canvas;
      canvas.save();
      canvas.clipRect(paintBounds.shift(offset));
      for (final panel in panels) {
        QuotePanel.paintBackground(
          canvas,
          panel.rect.shift(offset),
          background: _background,
          bar: _bar,
        );
        // Additional quote levels share the gutter, leaving wrapped text clear.
        final step = math.min(
          6.0,
          ComposerBlockquoteDecoration.gutter / panel.depth,
        );
        for (var level = 1; level < panel.depth; level++) {
          canvas.drawRect(
            Rect.fromLTWH(
              offset.dx + panel.rect.left + level * step,
              offset.dy + panel.rect.top,
              math.min(3, step / 2),
              panel.rect.height,
            ),
            Paint()..color = _bar,
          );
        }
      }
      canvas.restore();
    }
    super.paint(context, offset);
  }
}

class ComposerBlockquoteInputFormatter extends TextInputFormatter {
  const ComposerBlockquoteInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final selection = oldValue.selection;
    if (!selection.isValid ||
        !selection.isCollapsed ||
        !newValue.selection.isCollapsed ||
        !newValue.composing.isCollapsed) {
      return newValue;
    }

    final caret = selection.extentOffset;
    if (caret > oldValue.text.length ||
        newValue.selection.extentOffset != caret + 1 ||
        newValue.text.length != oldValue.text.length + 1 ||
        newValue.text != oldValue.text.replaceRange(caret, caret, '\n')) {
      return newValue;
    }

    final lineStart = caret == 0
        ? 0
        : oldValue.text.lastIndexOf('\n', caret - 1) + 1;
    for (final range in composerBlockquotePrefixes(oldValue.text)) {
      if (range.start != lineStart || range.end > caret) continue;
      final lineEnd = oldValue.text.indexOf('\n', caret);
      final body = oldValue.text.substring(
        range.end,
        lineEnd == -1 ? oldValue.text.length : lineEnd,
      );
      if (body.trim().isEmpty) {
        // The second Enter exits the quote without leaving an empty quote row.
        final end = lineEnd == -1 ? oldValue.text.length : lineEnd;
        return TextEditingValue(
          text: oldValue.text.replaceRange(lineStart, end, ''),
          selection: TextSelection.collapsed(offset: lineStart),
        );
      }

      final prefix = range.textInside(oldValue.text);
      return TextEditingValue(
        text: newValue.text.replaceRange(caret + 1, caret + 1, prefix),
        selection: TextSelection.collapsed(offset: caret + 1 + prefix.length),
      );
    }
    return newValue;
  }
}
