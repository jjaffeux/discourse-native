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
      // Indent quoted line starts with their source prefix, leaving ordinary
      // paragraphs at the native editable's left edge.
      width: ComposerBlockquoteDecoration.gutter,
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

  // Only the border extends outside the editable. A quote's text indentation
  // belongs to its prefix, rather than an outdent of the whole quote panel.
  @override
  Rect get paintBounds => Rect.fromLTRB(
    -ComposerBlockquoteDecoration.gutter - QuotePanel.barWidth,
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
          -QuotePanel.barWidth,
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
        // Keep every level's border outside the editable so it cannot cover
        // text that wraps back to the native left edge.
        final step = math.min(
          6.0,
          ComposerBlockquoteDecoration.gutter / panel.depth,
        );
        for (var level = 1; level < panel.depth; level++) {
          canvas.drawRect(
            Rect.fromLTWH(
              offset.dx + panel.rect.left - level * step,
              offset.dy + panel.rect.top,
              math.min(QuotePanel.barWidth, step / 2),
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
  ComposerBlockquoteInputFormatter({this.isShiftPressed});

  final bool Function()? isShiftPressed;
  TextEditingValue? _lastPlainEnter;

  void reset() => _lastPlainEnter = null;

  void observeValue(TextEditingValue value) {
    if (value != _lastPlainEnter) reset();
  }

  bool isInQuote(TextEditingValue value) => _prefixAtSelection(value) != null;

  TextRange? _prefixAtSelection(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || selection.end > value.text.length) return null;
    final caret = selection.start;
    final lineStart = caret == 0
        ? 0
        : value.text.lastIndexOf('\n', caret - 1) + 1;
    for (final range in composerBlockquotePrefixes(value.text)) {
      if (range.start == lineStart && range.end <= caret) return range;
    }
    return null;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final followsPlainEnter = oldValue == _lastPlainEnter;
    reset();
    final selection = oldValue.selection;
    if (!selection.isValid ||
        selection.end > oldValue.text.length ||
        !newValue.selection.isCollapsed ||
        !newValue.composing.isCollapsed) {
      return newValue;
    }

    final caret = selection.start;
    if (selection.isCollapsed &&
        oldValue.composing.isCollapsed &&
        caret > 0 &&
        newValue.selection.extentOffset == caret - 1 &&
        newValue.text == oldValue.text.replaceRange(caret - 1, caret, '')) {
      final range = _prefixAtSelection(oldValue);
      if (range != null && caret == range.end) {
        // The prefix is hidden in the editor. Backspace at the visible line
        // start joins the preceding quote line instead of exposing a bare >.
        final joinsPreviousQuote =
            range.start > 0 &&
            _prefixAtSelection(
                  oldValue.copyWith(
                    selection: TextSelection.collapsed(offset: range.start - 1),
                  ),
                ) !=
                null;
        final start = joinsPreviousQuote ? range.start - 1 : range.start;
        return TextEditingValue(
          text: oldValue.text.replaceRange(start, range.end, ''),
          selection: TextSelection.collapsed(offset: start),
        );
      }
      return newValue;
    }

    if (newValue.selection.extentOffset != caret + 1 ||
        newValue.text !=
            oldValue.text.replaceRange(caret, selection.end, '\n')) {
      return newValue;
    }

    final range = _prefixAtSelection(oldValue);
    if (range != null) {
      final shift =
          isShiftPressed?.call() ?? HardwareKeyboard.instance.isShiftPressed;
      final lineEnd = oldValue.text.indexOf('\n', caret);
      final body = oldValue.text.substring(
        range.end,
        lineEnd == -1 ? oldValue.text.length : lineEnd,
      );
      if (!shift && followsPlainEnter && body.trim().isEmpty) {
        // The second Enter exits the quote without leaving an empty quote row.
        final end = lineEnd == -1 ? oldValue.text.length : lineEnd;
        return TextEditingValue(
          text: oldValue.text.replaceRange(range.start, end, ''),
          selection: TextSelection.collapsed(offset: range.start),
        );
      }

      final prefix = range.textInside(oldValue.text);
      final result = TextEditingValue(
        text: newValue.text.replaceRange(caret + 1, caret + 1, prefix),
        selection: TextSelection.collapsed(offset: caret + 1 + prefix.length),
      );
      if (!shift) _lastPlainEnter = result;
      return result;
    }
    return newValue;
  }
}
