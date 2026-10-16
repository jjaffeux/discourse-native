import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../foundation/code_editor_theme.dart';
import '../foundation/code_source.dart';
import '../foundation/code_typography.dart';
import 'd_scroll_area.dart';

part 'd_code_viewer_render.dart';

/// A read-only, unwrapped code document in the enclosing selection area.
///
/// Keeps its natural height while shaping visible rows and selection endpoints.
/// Horizontal extent grows to include the widest line visited so far.
class DCodeViewer extends StatefulWidget {
  const DCodeViewer({
    super.key,
    required this.source,
    this.lineNumbers,
    this.highlightedLines = const {},
    this.lineSpanBuilder,
    this.horizontalController,
    this.semanticLabel,
  });

  final String source;

  /// One entry per source line. Null hides the gutter; null entries are blank.
  final List<int?>? lineNumbers;

  /// Zero-based source lines whose entire row receives a background highlight.
  final Set<int> highlightedLines;

  /// Called on demand. The span's plain text must equal the indexed source line.
  final InlineSpan Function(int index)? lineSpanBuilder;

  /// Borrowed. An internal controller is used when omitted.
  final ScrollController? horizontalController;
  final String? semanticLabel;

  @override
  State<DCodeViewer> createState() => _DCodeViewerState();
}

class _DCodeViewerState extends State<DCodeViewer> {
  final _ownedHorizontal = ScrollController();
  late CodeSource _source = CodeSource(widget.source);

  @override
  void didUpdateWidget(DCodeViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _source = CodeSource(widget.source);
  }

  @override
  void dispose() {
    _ownedHorizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.lineNumbers == null ||
          widget.lineNumbers!.length == _source.lines.length,
    );
    final theme = Theme.of(context);
    final horizontal = widget.horizontalController ?? _ownedHorizontal;
    final vertical = Scrollable.maybeOf(context, axis: Axis.vertical);
    final style = monospaceTextStyle.copyWith(
      fontSize: DiscourseTypography.sm,
      height: DiscourseTypography.codeLineHeight,
      color: theme.discourse.primaryVeryHigh,
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) => DScrollBar(
          axis: Axis.horizontal,
          controller: horizontal,
          backgroundColor: codeEditorColors(theme).blockBackground,
          child: SingleChildScrollView(
            controller: horizontal,
            scrollDirection: Axis.horizontal,
            child: _CodeView(
              source: _source,
              lineNumbers: widget.lineNumbers,
              highlightedLines: widget.highlightedLines,
              lineSpanBuilder: widget.lineSpanBuilder,
              style: style,
              gutterColor: theme.colorScheme.onSurfaceVariant,
              highlightColor: theme.colorScheme.tertiaryContainer,
              selectionColor: theme.colorScheme.primary.withValues(alpha: .28),
              textScaler: MediaQuery.textScalerOf(context),
              locale: Localizations.maybeLocaleOf(context),
              screenSize: MediaQuery.sizeOf(context),
              minWidth: constraints.hasBoundedWidth ? constraints.maxWidth : 0,
              vertical: vertical,
              semanticLabel: widget.semanticLabel,
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeView extends LeafRenderObjectWidget {
  const _CodeView({
    required this.source,
    required this.lineNumbers,
    required this.highlightedLines,
    required this.lineSpanBuilder,
    required this.style,
    required this.gutterColor,
    required this.highlightColor,
    required this.selectionColor,
    required this.textScaler,
    required this.locale,
    required this.screenSize,
    required this.minWidth,
    required this.vertical,
    required this.semanticLabel,
  });

  final CodeSource source;
  final List<int?>? lineNumbers;
  final Set<int> highlightedLines;
  final InlineSpan Function(int)? lineSpanBuilder;
  final TextStyle style;
  final Color gutterColor;
  final Color highlightColor;
  final Color selectionColor;
  final TextScaler textScaler;
  final Locale? locale;
  final Size screenSize;
  final double minWidth;
  final ScrollableState? vertical;
  final String? semanticLabel;

  @override
  _RenderCodeViewer createRenderObject(BuildContext context) =>
      _RenderCodeViewer(this, context);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCodeViewer renderObject,
  ) {
    renderObject.update(this, context);
  }
}
