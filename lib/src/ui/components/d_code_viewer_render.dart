part of 'd_code_viewer.dart';

class _CodeLinePainters {
  _CodeLinePainters(this.text, this.number);
  final TextPainter text;
  final TextPainter? number;

  void dispose() {
    text.dispose();
    number?.dispose();
  }
}

class _RenderCodeViewer extends RenderBox with Selectable, SelectionRegistrant {
  _RenderCodeViewer(this._configuration, BuildContext context) {
    _bind(context);
  }

  _CodeView _configuration;
  CodeSource get _source => _configuration.source;
  final _painters = <int, _CodeLinePainters>{};
  final _geometry = ValueNotifier<SelectionGeometry>(
    const SelectionGeometry(status: SelectionStatus.none, hasContent: true),
  );
  final List<ScrollPosition> _positions = [];
  final List<ScrollableState> _scrollables = [];
  ScrollableState? _horizontal;
  SelectionRegistrar? _desiredRegistrar;
  TextSelection? _selection;
  TextRange? _originBoundary;
  LayerLink? _startHandle;
  LayerLink? _endHandle;
  double _rowHeight = 21;
  double _gutterWidth = 0;
  double _visitedWidth = 0;
  int _cacheLimit = 16;
  bool _typographyDirty = true;
  bool _geometryScheduled = false;
  bool _layoutScheduled = false;
  bool _disposed = false;
  bool _visibilityScheduled = false;
  VoidCallback? _removeCompositionCallback;
  int? _pendingReveal;

  static const double _topPadding = 4;
  static const double _bottomPadding = 12;
  double get _textLeft => _gutterWidth + 8;
  double _rowTop(int row) => _topPadding + row * _rowHeight;

  void _bind(BuildContext context) {
    _horizontal = Scrollable.maybeOf(context, axis: Axis.horizontal);
    _desiredRegistrar = SelectionContainer.maybeOf(context);
    for (final position in _positions) {
      position.removeListener(_scrolled);
    }
    final scrollables = <ScrollableState>{
      ?_configuration.vertical,
      ?_horizontal,
    };
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        scrollables.add(element.state as ScrollableState);
      }
      return true;
    });
    _scrollables
      ..clear()
      ..addAll(scrollables);
    _positions
      ..clear()
      ..addAll({for (final scrollable in _scrollables) scrollable.position});
    if (attached) {
      for (final position in _positions) {
        position.addListener(_scrolled);
      }
      registrar = _desiredRegistrar;
    }
  }

  void update(_CodeView configuration, BuildContext context) {
    final previous = _configuration;
    _configuration = configuration;
    _bind(context);
    if (previous.source != configuration.source) {
      _selection = null;
      _originBoundary = null;
      _pendingReveal = null;
    }
    _clearPainters();
    _typographyDirty = true;
    if (previous.source != configuration.source ||
        previous.textScaler != configuration.textScaler ||
        previous.locale != configuration.locale) {
      _visitedWidth = 0;
    }
    markNeedsLayout();
    markNeedsPaint();
    markNeedsSemanticsUpdate();
    _scheduleGeometry();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    for (final position in _positions) {
      position.addListener(_scrolled);
    }
    registrar = _desiredRegistrar;
  }

  @override
  void detach() {
    _removeCompositionCallback?.call();
    _removeCompositionCallback = null;
    registrar = null;
    for (final position in _positions) {
      position.removeListener(_scrolled);
    }
    super.detach();
  }

  @override
  void dispose() {
    _disposed = true;
    _removeCompositionCallback?.call();
    _removeCompositionCallback = null;
    registrar = null;
    for (final position in _positions) {
      position.removeListener(_scrolled);
    }
    _clearPainters();
    _geometry.dispose();
    super.dispose();
  }

  void _clearPainters() {
    for (final painters in _painters.values) {
      painters.dispose();
    }
    _painters.clear();
  }

  void _scrolled() {
    markNeedsPaint();
    _scheduleGeometry();
  }

  TextPainter _createPainter(InlineSpan span) => TextPainter(
    text: span,
    textDirection: TextDirection.ltr,
    textScaler: _configuration.textScaler,
    locale: _configuration.locale,
    strutStyle: StrutStyle.fromTextStyle(
      _configuration.style,
      forceStrutHeight: true,
    ),
    maxLines: 1,
  )..layout();

  void _measureTypography() {
    final sample = _createPainter(
      TextSpan(text: '0', style: _configuration.style),
    );
    _rowHeight = sample.height;
    sample.dispose();
    _gutterWidth = 0;
    if (_configuration.lineNumbers case final numbers?) {
      var digits = 0;
      var negativeDigits = 0;
      for (final number in numbers) {
        if (number == null) continue;
        if (number < 0) {
          negativeDigits = math.max(
            negativeDigits,
            number.toString().length - 1,
          );
        } else {
          digits = math.max(digits, number.toString().length);
        }
      }
      for (final text in [
        if (digits > 0) '8' * digits,
        if (negativeDigits > 0) '-${'8' * negativeDigits}',
      ]) {
        final painter = _createPainter(
          TextSpan(text: text, style: _configuration.style),
        );
        _gutterWidth = math.max(_gutterWidth, painter.width);
        painter.dispose();
      }
      _gutterWidth += 12;
    }
  }

  @override
  void performLayout() {
    if (_typographyDirty) {
      _measureTypography();
      _typographyDirty = false;
    }
    size = constraints.constrain(
      Size(
        math.max(_configuration.minWidth, _visitedWidth + _textLeft + 12),
        _topPadding + _source.lines.length * _rowHeight + _bottomPadding,
      ),
    );
    _scheduleGeometry();
    if (_pendingReveal case final offset?) {
      _pendingReveal = null;
      final source = _source;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && attached && identical(source, _source)) {
          _revealCaret(offset);
        }
      });
    }
  }

  Rect get _visibleRect {
    var global = Offset.zero & _configuration.screenSize;
    for (final scrollable in _scrollables) {
      final viewport = scrollable.context.findRenderObject();
      if (viewport is RenderBox && viewport.hasSize && viewport.attached) {
        final bounds = MatrixUtils.transformRect(
          viewport.getTransformTo(null),
          Offset.zero & viewport.size,
        );
        global = global.intersect(bounds);
      }
    }
    if (global.isEmpty) return Rect.zero;
    final transform = getTransformTo(null);
    if (transform.invert() == 0) return Rect.zero;
    return MatrixUtils.transformRect(
      transform,
      global,
    ).intersect(Offset.zero & size);
  }

  (int, int) get _visibleRows {
    final rect = _visibleRect;
    if (rect.isEmpty) return (0, 0);
    final first = ((rect.top - _topPadding) / _rowHeight).floor() - 1;
    final end = ((rect.bottom - _topPadding) / _rowHeight).ceil() + 1;
    return (
      first.clamp(0, _source.lines.length),
      end.clamp(0, _source.lines.length),
    );
  }

  _CodeLinePainters _line(int index) {
    final cached = _painters.remove(index);
    if (cached != null) {
      _painters[index] = cached;
      return cached;
    }
    final span =
        _configuration.lineSpanBuilder?.call(index) ??
        TextSpan(text: _source.lines[index]);
    assert(
      span.toPlainText(includeSemanticsLabels: false) == _source.lines[index],
    );
    final painter = _createPainter(
      TextSpan(style: _configuration.style, children: [span]),
    );
    final number = _configuration.lineNumbers?[index];
    final painters = _CodeLinePainters(
      painter,
      number == null
          ? null
          : _createPainter(
              TextSpan(
                text: number.toString(),
                style: _configuration.style.copyWith(
                  color: _configuration.gutterColor,
                ),
              ),
            ),
    );
    _painters[index] = painters;
    while (_painters.length > _cacheLimit) {
      _painters.remove(_painters.keys.first)!.dispose();
    }
    return painters;
  }

  void _learnWidth(double width) {
    if (width <= _visitedWidth) return;
    _visitedWidth = width;
    if (_layoutScheduled) return;
    _layoutScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutScheduled = false;
      if (!_disposed && attached) markNeedsLayout();
    });
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final paintedRect = _visibleRect;
    _removeCompositionCallback?.call();
    // Retained ancestor clips can change without child layout or scrolling.
    _removeCompositionCallback = context.addCompositionCallback((layer) {
      if (!attached ||
          !layer.attached ||
          _visibilityScheduled ||
          _visibleRect == paintedRect) {
        return;
      }
      _visibilityScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _visibilityScheduled = false;
        if (!_disposed && attached) _scrolled();
      });
    });
    final (first, end) = _visibleRows;
    _cacheLimit = math.max(16, end - first + 4);
    while (_painters.length > _cacheLimit) {
      _painters.remove(_painters.keys.first)!.dispose();
    }
    final canvas = context.canvas;
    canvas.save();
    canvas.clipRect((Offset.zero & size).shift(offset));
    for (var row = first; row < end; row++) {
      final painters = _line(row);
      _learnWidth(painters.text.width);
      final top = _rowTop(row);
      if (_configuration.highlightedLines.contains(row)) {
        canvas.drawRect(
          Rect.fromLTWH(offset.dx, offset.dy + top, size.width, _rowHeight),
          Paint()..color = _configuration.highlightColor,
        );
      }
      for (final rect in _selectionRects(row, painters.text)) {
        canvas.drawRect(
          rect.shift(offset),
          Paint()..color = _configuration.selectionColor,
        );
      }
      painters.number?.paint(
        canvas,
        offset + Offset(_gutterWidth - painters.number!.width, top),
      );
      painters.text.paint(canvas, offset + Offset(_textLeft, top));
    }
    canvas.restore();
    _paintHandle(context, offset, _startHandle, value.startSelectionPoint);
    _paintHandle(context, offset, _endHandle, value.endSelectionPoint);
    _scheduleGeometry();
  }

  void _paintHandle(
    PaintingContext context,
    Offset offset,
    LayerLink? link,
    SelectionPoint? point,
  ) {
    if (link == null ||
        point == null ||
        !_visibleRect.contains(
          point.localPosition - Offset(0, _rowHeight / 2),
        )) {
      return;
    }
    context.pushLayer(
      LeaderLayer(link: link, offset: offset + point.localPosition),
      (context, offset) {},
      Offset.zero,
    );
  }

  Iterable<Rect> _selectionRects(int row, TextPainter painter) sync* {
    final selection = _selection;
    if (selection == null || selection.isCollapsed) return;
    final start = _source.starts[row];
    final end = _source.endOf(row);
    if (selection.end < start || selection.start > end) return;
    for (final box in painter.getBoxesForSelection(
      TextSelection(
        baseOffset: (selection.start - start).clamp(0, end - start),
        extentOffset: (selection.end - start).clamp(0, end - start),
      ),
      boxHeightStyle: BoxHeightStyle.strut,
    )) {
      yield box.toRect().shift(Offset(_textLeft, _rowTop(row)));
    }
    if (selection.start <= end &&
        selection.end > end &&
        row + 1 < _source.lines.length) {
      yield Rect.fromLTWH(
        _textLeft + painter.width,
        _rowTop(row),
        2,
        _rowHeight,
      );
    }
  }

  @override
  SelectionGeometry get value => _geometry.value;
  @override
  void addListener(VoidCallback listener) => _geometry.addListener(listener);
  @override
  void removeListener(VoidCallback listener) =>
      _geometry.removeListener(listener);
  @override
  int get contentLength => _source.text.length;
  @override
  List<Rect> get boundingBoxes => [Offset.zero & size];

  @override
  SelectedContent? getSelectedContent() => _selection == null
      ? null
      : SelectedContent(
          plainText: _source.text.substring(_selection!.start, _selection!.end),
        );

  @override
  SelectedContentRange? getSelection() => _selection == null
      ? null
      : SelectedContentRange(
          startOffset: _selection!.baseOffset,
          endOffset: _selection!.extentOffset,
        );

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (!attached) {
      assert(startHandle == null && endHandle == null);
      return;
    }
    _startHandle = startHandle;
    _endHandle = endHandle;
    markNeedsPaint();
  }

  void _scheduleGeometry() {
    if (_geometryScheduled) return;
    _geometryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geometryScheduled = false;
      if (!_disposed && attached && hasSize) _updateGeometry();
    });
  }

  Offset _caret(int offset) {
    final row = _source.lineAt(offset);
    final painter = _line(row).text;
    final caret = painter.getOffsetForCaret(
      TextPosition(
        offset: (offset - _source.starts[row]).clamp(
          0,
          _source.lines[row].length,
        ),
      ),
      Rect.zero,
    );
    return Offset(_textLeft + caret.dx, _rowTop(row) + _rowHeight);
  }

  void _updateGeometry() {
    final selection = _selection;
    if (selection == null) {
      _geometry.value = SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: contentLength > 0,
      );
      return;
    }
    final (first, end) = _visibleRows;
    final reversed = selection.baseOffset > selection.extentOffset;
    final collapsed = selection.isCollapsed;
    _geometry.value = SelectionGeometry(
      startSelectionPoint: SelectionPoint(
        localPosition: _caret(selection.baseOffset),
        lineHeight: _rowHeight,
        handleType: collapsed
            ? TextSelectionHandleType.collapsed
            : reversed
            ? TextSelectionHandleType.right
            : TextSelectionHandleType.left,
      ),
      endSelectionPoint: SelectionPoint(
        localPosition: _caret(selection.extentOffset),
        lineHeight: _rowHeight,
        handleType: collapsed
            ? TextSelectionHandleType.collapsed
            : reversed
            ? TextSelectionHandleType.left
            : TextSelectionHandleType.right,
      ),
      selectionRects: [
        for (var row = first; row < end; row++)
          ..._selectionRects(row, _line(row).text),
      ],
      status: collapsed
          ? SelectionStatus.collapsed
          : SelectionStatus.uncollapsed,
      hasContent: contentLength > 0,
    );
  }

  int _positionOnRow(int row, double x) {
    if (x <= _textLeft) return _source.starts[row];
    if (!x.isFinite) return _source.endOf(row);
    final painter = _line(row).text;
    final position = painter.getPositionForOffset(
      Offset(x - _textLeft, _rowHeight / 2),
    );
    return _source.starts[row] +
        position.offset.clamp(0, _source.lines[row].length);
  }

  int _position(Offset local) {
    if (local.dy < _topPadding) return 0;
    if (local.dy >= _rowTop(_source.lines.length)) return contentLength;
    final row = ((local.dy - _topPadding) / _rowHeight).floor().clamp(
      0,
      _source.lines.length - 1,
    );
    return _positionOnRow(row, local.dx);
  }

  TextRange _wordAt(int offset) {
    final row = _source.lineAt(offset);
    final start = _source.starts[row];
    final word = _line(row).text.getWordBoundary(
      TextPosition(
        offset: (offset - start).clamp(0, _source.lines[row].length),
      ),
    );
    return TextRange(start: start + word.start, end: start + word.end);
  }

  TextRange _paragraphAt(int offset) {
    final row = _source.lineAt(offset);
    return TextRange(
      start: _source.starts[row],
      end: row + 1 < _source.lines.length
          ? _source.starts[row + 1]
          : contentLength,
    );
  }

  void _setEdge(int offset, {required bool isEnd}) {
    final previous = _selection ?? TextSelection.collapsed(offset: offset);
    _selection = isEnd
        ? previous.copyWith(extentOffset: offset)
        : previous.copyWith(baseOffset: offset);
  }

  SelectionResult _edge(SelectionEdgeUpdateEvent event) {
    final global = event.globalPosition;
    final local = global.dx.isFinite && global.dy.isFinite
        ? globalToLocal(global)
        : Offset(
            global.dx.isNegative ? 0 : size.width,
            global.dy.isNegative ? -1 : size.height + 1,
          );
    final result = SelectionUtils.getResultBasedOnRect(
      Offset.zero & size,
      local,
    );
    final offset = _position(
      SelectionUtils.adjustDragOffset(Offset.zero & size, local),
    );
    final isEnd = event.type == SelectionEventType.endEdgeUpdate;
    if (event.granularity == TextGranularity.word ||
        event.granularity == TextGranularity.paragraph) {
      final boundary = event.granularity == TextGranularity.word
          ? _wordAt(offset)
          : _paragraphAt(offset);
      final previous = _selection;
      final stationary = isEnd ? previous?.baseOffset : previous?.extentOffset;
      final moving = isEnd ? previous?.extentOffset : previous?.baseOffset;
      final origin = _originBoundary;
      final reversed =
          stationary != null &&
          (isEnd ? offset < stationary : offset > stationary);
      if (offset != moving) {
        _setEdge(
          isEnd
              ? (reversed ? boundary.start : boundary.end)
              : (reversed ? boundary.end : boundary.start),
          isEnd: isEnd,
        );
      }
      if (origin != null &&
          stationary != null &&
          stationary >= origin.start &&
          stationary <= origin.end) {
        _setEdge(
          isEnd
              ? (reversed ? origin.end : origin.start)
              : (reversed ? origin.start : origin.end),
          isEnd: !isEnd,
        );
      }
    } else {
      _setEdge(offset, isEnd: isEnd);
    }
    if (offset == contentLength) return SelectionResult.next;
    if (offset == 0) return SelectionResult.previous;
    return result;
  }

  int _move(int offset, bool forward, TextGranularity granularity) {
    final row = _source.lineAt(offset);
    switch (granularity) {
      case TextGranularity.character:
        final boundary = CharacterBoundary(_source.text);
        return forward
            ? boundary.getTrailingTextBoundaryAt(offset) ?? contentLength
            : boundary.getLeadingTextBoundaryAt(offset - 1) ?? 0;
      case TextGranularity.word:
        if (forward && offset == _source.endOf(row)) {
          return row + 1 < _source.lines.length
              ? _source.starts[row + 1]
              : contentLength;
        }
        if (!forward && offset == _source.starts[row]) {
          return row > 0 ? _source.endOf(row - 1) : 0;
        }
        final boundary = _line(row).text.wordBoundaries.moveByWordBoundary;
        final local = offset - _source.starts[row];
        return _source.starts[row] +
            (forward
                ? boundary.getTrailingTextBoundaryAt(local) ??
                      _source.lines[row].length
                : boundary.getLeadingTextBoundaryAt(local - 1) ?? 0);
      case TextGranularity.paragraph:
        final boundary = ParagraphBoundary(_source.text);
        return forward
            ? boundary.getTrailingTextBoundaryAt(offset) ?? contentLength
            : boundary.getLeadingTextBoundaryAt(offset - 1) ?? 0;
      case TextGranularity.line:
        return forward ? _source.endOf(row) : _source.starts[row];
      case TextGranularity.document:
        return forward ? contentLength : 0;
    }
  }

  SelectionResult _extend(GranularlyExtendSelectionEvent event) {
    _originBoundary = null;
    _selection ??= TextSelection.collapsed(
      offset: event.forward ? 0 : contentLength,
    );
    final offset = event.isEnd
        ? _selection!.extentOffset
        : _selection!.baseOffset;
    if (event.forward && offset == contentLength) return SelectionResult.next;
    if (!event.forward && offset == 0) return SelectionResult.previous;
    _setEdge(
      _move(offset, event.forward, event.granularity),
      isEnd: event.isEnd,
    );
    if (event.granularity == TextGranularity.document) {
      return event.forward ? SelectionResult.next : SelectionResult.previous;
    }
    return SelectionResult.end;
  }

  SelectionResult _extendDirection(DirectionallyExtendSelectionEvent event) {
    _originBoundary = null;
    final forward =
        event.direction == SelectionExtendDirection.forward ||
        event.direction == SelectionExtendDirection.nextLine;
    _selection ??= TextSelection.collapsed(offset: forward ? 0 : contentLength);
    final offset = event.isEnd
        ? _selection!.extentOffset
        : _selection!.baseOffset;
    var row = _source.lineAt(offset);
    switch (event.direction) {
      case SelectionExtendDirection.previousLine:
        row--;
      case SelectionExtendDirection.nextLine:
        row++;
      case SelectionExtendDirection.forward:
      case SelectionExtendDirection.backward:
        break;
    }
    if (row < 0 || row >= _source.lines.length) {
      _setEdge(row < 0 ? 0 : contentLength, isEnd: event.isEnd);
      return row < 0 ? SelectionResult.previous : SelectionResult.next;
    }
    final x = event.dx.isFinite
        ? globalToLocal(Offset(event.dx, 0)).dx
        : event.dx;
    _setEdge(_positionOnRow(row, x), isEnd: event.isEnd);
    return SelectionResult.end;
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final SelectionResult result;
    switch (event.type) {
      case SelectionEventType.clear:
        _selection = null;
        _originBoundary = null;
        result = SelectionResult.none;
      case SelectionEventType.selectAll:
        _selection = TextSelection(baseOffset: 0, extentOffset: contentLength);
        _originBoundary = null;
        result = SelectionResult.none;
      case SelectionEventType.startEdgeUpdate:
      case SelectionEventType.endEdgeUpdate:
        result = _edge(event as SelectionEdgeUpdateEvent);
      case SelectionEventType.selectWord:
        final offset = _position(
          globalToLocal((event as SelectWordSelectionEvent).globalPosition),
        );
        final selection = _selection;
        if (selection != null &&
            !selection.isCollapsed &&
            offset >= selection.start &&
            offset <= selection.end) {
          result = SelectionResult.end;
          break;
        }
        final word = _originBoundary = _wordAt(offset);
        _selection = TextSelection(
          baseOffset: word.start,
          extentOffset: word.end,
        );
        result = SelectionResult.end;
      case SelectionEventType.selectParagraph:
        final paragraphEvent = event as SelectParagraphSelectionEvent;
        final paragraph = _originBoundary = paragraphEvent.absorb
            ? TextRange(start: 0, end: contentLength)
            : _paragraphAt(
                _position(globalToLocal(paragraphEvent.globalPosition)),
              );
        _selection = TextSelection(
          baseOffset: paragraph.start,
          extentOffset: paragraph.end,
        );
        result = paragraphEvent.absorb
            ? SelectionResult.next
            : SelectionResult.end;
      case SelectionEventType.granularlyExtendSelection:
        result = _extend(event as GranularlyExtendSelectionEvent);
      case SelectionEventType.directionallyExtendSelection:
        result = _extendDirection(event as DirectionallyExtendSelectionEvent);
    }
    _updateGeometry();
    markNeedsPaint();
    markNeedsSemanticsUpdate();
    return result;
  }

  void _semanticMove(bool forward, bool extend, TextGranularity granularity) {
    final offset = _selection?.extentOffset ?? 0;
    final next = _move(offset, forward, granularity).clamp(0, contentLength);
    _selection = TextSelection(
      baseOffset: extend ? _selection?.baseOffset ?? offset : next,
      extentOffset: next,
    );
    _updateGeometry();
    markNeedsPaint();
    markNeedsSemanticsUpdate();
    _revealCaret(next);
  }

  void _revealCaret(int offset) {
    _learnWidth(_line(_source.lineAt(offset)).text.width);
    if (_visitedWidth + _textLeft + 12 > size.width) _pendingReveal = offset;
    final caret = _caret(offset);
    showOnScreen(
      rect: Rect.fromLTWH(caret.dx, caret.dy - _rowHeight, 1, _rowHeight),
    );
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..isTextField = true
      ..isReadOnly = true
      ..isMultiline = true
      ..textDirection = TextDirection.ltr
      ..label = _configuration.semanticLabel ?? ''
      ..value = _source.text
      ..textSelection = _selection ?? const TextSelection.collapsed(offset: -1)
      ..onSetSelection = (selection) {
        _selection = TextSelection(
          baseOffset: selection.baseOffset.clamp(0, contentLength),
          extentOffset: selection.extentOffset.clamp(0, contentLength),
        );
        _updateGeometry();
        markNeedsPaint();
        markNeedsSemanticsUpdate();
        _revealCaret(_selection!.extentOffset);
      }
      ..onMoveCursorForwardByCharacter = (extend) {
        _semanticMove(true, extend, TextGranularity.character);
      }
      ..onMoveCursorBackwardByCharacter = (extend) {
        _semanticMove(false, extend, TextGranularity.character);
      }
      ..onMoveCursorForwardByWord = (extend) {
        _semanticMove(true, extend, TextGranularity.word);
      }
      ..onMoveCursorBackwardByWord = (extend) {
        _semanticMove(false, extend, TextGranularity.word);
      }
      ..onCopy = () {
        final text = getSelectedContent()?.plainText;
        if (text != null) {
          unawaited(Clipboard.setData(ClipboardData(text: text)));
        }
      };
  }
}
