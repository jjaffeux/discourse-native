import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';

/// A passive, eager presentation table. Sorting, selection controls, forms and
/// menus belong to callers; use a virtualized grid for unbounded datasets.
///
/// Sections share intrinsic column widths. [columnWidths] overrides individual
/// columns using Flutter's fixed, flex or intrinsic sizing policies. Spanning
/// cells distribute their required width across their columns. Content scrolls
/// horizontally rather than truncating when its natural width exceeds the
/// viewport. The optional [controller] is borrowed and is never disposed here.
class DTable extends StatefulWidget {
  const DTable({
    super.key,
    this.header,
    required this.body,
    this.footer,
    this.caption,
    this.columnWidths = const {},
    this.minimumWidth = 0,
    this.controller,
    this.semanticLabel,
  }) : assert(minimumWidth >= 0);

  final DTableHeader? header;
  final DTableBody body;
  final DTableFooter? footer;
  final DTableCaption? caption;
  final Map<int, TableColumnWidth> columnWidths;
  final double minimumWidth;
  final ScrollController? controller;
  final String? semanticLabel;

  @override
  State<DTable> createState() => _DTableState();
}

class _DTableState extends State<DTable> {
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final rows = [
      ...?widget.header?.rows,
      ...widget.body.rows,
      ...?widget.footer?.rows,
    ];
    final headerCount = widget.header?.rows.length ?? 0;
    final footerStart = headerCount + widget.body.rows.length;
    final columns = rows.fold<int>(
      0,
      (count, row) =>
          math.max(count, row.cells.fold(0, (n, c) => n + c.columnSpan)),
    );
    assert(
      rows.every(
        (row) => row.cells.fold(0, (n, c) => n + c.columnSpan) == columns,
      ),
      'Every table row must cover the same number of columns.',
    );
    return DefaultTextStyle.merge(
      style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
          .copyWith(
            fontSize: DiscourseTypography.sm,
            height: 20 / DiscourseTypography.sm,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
            color: tokens.foreground,
          ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(
            widget.minimumWidth,
            constraints.hasBoundedWidth ? constraints.maxWidth : 0.0,
          );
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: widget.controller,
            primary: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  container: true,
                  explicitChildNodes: true,
                  label: widget.semanticLabel,
                  child: _TableLayout(
                    rows: rows,
                    columns: columns,
                    minimumWidth: width,
                    columnWidths: widget.columnWidths,
                    direction: Directionality.of(context),
                    borders: [
                      for (var r = 0; r < rows.length; r++)
                        r < headerCount ||
                            r < footerStart - 1 ||
                            (r >= footerStart && r < rows.length - 1),
                    ],
                    footerStart: footerStart < rows.length ? footerStart : -1,
                    border: tokens.border,
                    hasCaption: widget.caption != null,
                    children: [
                      for (var r = 0; r < rows.length; r++)
                        for (var c = 0; c < rows[r].cells.length; c++)
                          Semantics(
                            key:
                                rows[r].cells[c].key == null &&
                                    rows[r].key == null
                                ? null
                                : ValueKey((
                                    rows[r].key ?? r,
                                    rows[r].cells[c].key ?? c,
                                  )),
                            container: true,
                            sortKey: OrdinalSortKey(
                              (r * columns + c).toDouble(),
                            ),
                            role: rows[r].cells[c] is DTableHead
                                ? SemanticsRole.columnHeader
                                : SemanticsRole.cell,
                            header: rows[r].cells[c] is DTableHead,
                            selected: rows[r].selected ? true : null,
                            child: MouseRegion(
                              onEnter: (_) => setState(() => _hovered = r),
                              onExit: (_) {
                                if (_hovered == r) {
                                  setState(() => _hovered = null);
                                }
                              },
                              child: AnimatedContainer(
                                duration: DMotion.duration(
                                  context,
                                  const Duration(milliseconds: 150),
                                ),
                                curve: Curves.easeInOut,
                                color: rows[r].selected
                                    ? tokens.muted
                                    : (_hovered == r ||
                                          rows[r].expanded ||
                                          r >= footerStart)
                                    ? tokens.muted.withValues(
                                        alpha: tokens.muted.a * .5,
                                      )
                                    : tokens.muted.withValues(alpha: 0),
                                child: DefaultTextStyle.merge(
                                  style: TextStyle(
                                    fontWeight: r >= footerStart
                                        ? FontWeight.w500
                                        : FontWeight.w400,
                                  ),
                                  child: rows[r].cells[c],
                                ),
                              ),
                            ),
                          ),
                      ?widget.caption,
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Header rows, normally composed with [DTableHead] cells.
@immutable
class DTableHeader {
  const DTableHeader({required this.rows});
  final List<DTableRow> rows;
}

/// Body rows. The final body row has no bottom rule.
@immutable
class DTableBody {
  const DTableBody({required this.rows});
  final List<DTableRow> rows;
}

/// Summary rows, with a top rule, medium text and a half-muted background.
@immutable
class DTableFooter {
  const DTableFooter({required this.rows});
  final List<DTableRow> rows;
}

/// Presentation and controlled state only. Compose focusable controls inside
/// cells to activate actions or change selection. No extra row tab stop is added.
@immutable
class DTableRow {
  const DTableRow({
    this.key,
    required this.cells,
    this.selected = false,
    this.expanded = false,
  });
  final LocalKey? key;
  final List<DTableCell> cells;
  final bool selected;

  /// Matches the reference highlight while a caller-owned menu is expanded.
  final bool expanded;
}

/// A vertically centered cell. Text remains on one line by default; set
/// [softWrap] for authored multi-line content in explicitly sized columns.
/// [padding] also permits the reference checkbox composition's zero end inset.
class DTableCell extends StatelessWidget {
  const DTableCell({
    super.key,
    required this.child,
    this.columnSpan = 1,
    this.alignment = AlignmentDirectional.centerStart,
    this.padding = const EdgeInsets.all(8),
    this.softWrap = false,
    this.textStyle,
  }) : assert(columnSpan > 0);
  final Widget child;
  final int columnSpan;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;
  final bool softWrap;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Align(
      alignment: alignment,
      widthFactor: 1,
      heightFactor: 1,
      child: DefaultTextStyle.merge(
        softWrap: softWrap,
        style: textStyle,
        child: child,
      ),
    ),
  );
}

/// Column header with the reference's 40px minimum height and medium weight.
/// It grows to accommodate large text; padding remains eight logical pixels.
class DTableHead extends DTableCell {
  const DTableHead({
    super.key,
    required super.child,
    super.columnSpan,
    super.alignment,
    super.padding = const EdgeInsets.symmetric(horizontal: 8),
    super.softWrap,
    super.textStyle,
  });

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 40),
    child: DefaultTextStyle.merge(
      style: const TextStyle(fontWeight: FontWeight.w500),
      child: super.build(context),
    ),
  );
}

/// Bottom caption separated from the table by 16 logical pixels.
class DTableCaption extends StatelessWidget {
  const DTableCaption({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: DefaultTextStyle.merge(
      style: TextStyle(color: DTokens.of(context).mutedForeground),
      textAlign: TextAlign.center,
      child: child,
    ),
  );
}

class _TableLayout extends MultiChildRenderObjectWidget {
  const _TableLayout({
    required this.rows,
    required this.columns,
    required this.minimumWidth,
    required this.columnWidths,
    required this.direction,
    required this.borders,
    required this.footerStart,
    required this.border,
    required this.hasCaption,
    required super.children,
  });
  final List<DTableRow> rows;
  final int columns;
  final double minimumWidth;
  final Map<int, TableColumnWidth> columnWidths;
  final TextDirection direction;
  final List<bool> borders;
  final int footerStart;
  final Color border;
  final bool hasCaption;
  @override
  _RenderTable createRenderObject(BuildContext context) =>
      _RenderTable()..configure(this);
  @override
  void updateRenderObject(BuildContext context, _RenderTable renderObject) =>
      renderObject.configure(this);
}

class _CellData extends ContainerBoxParentData<RenderBox> {}

/// Flutter's stock Table has no column spans. This small eager layout keeps
/// spans, intrinsic overflow and shared row heights under one rendering owner.
class _RenderTable extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CellData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CellData> {
  late _TableLayout spec;
  List<double> _rowEnds = [];
  void configure(_TableLayout value) {
    spec = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CellData) child.parentData = _CellData();
  }

  List<RenderBox> get _cells => getChildrenAsList();

  List<double> _widths(List<RenderBox> cells) {
    final natural = List.filled(spec.columns, 0.0);
    final perColumn = List.generate(spec.columns, (_) => <RenderBox>[]);
    var index = 0;
    for (final row in spec.rows) {
      var column = 0;
      for (final cell in row.cells) {
        final box = cells[index++];
        if (cell.columnSpan == 1) {
          perColumn[column].add(box);
          if (!spec.columnWidths.containsKey(column)) {
            natural[column] = math.max(
              natural[column],
              box.getMaxIntrinsicWidth(double.infinity),
            );
          }
        }
        column += cell.columnSpan;
      }
    }
    final widths = List.generate(spec.columns, (c) {
      final policy = spec.columnWidths[c];
      return policy == null
          ? natural[c]
          : policy.maxIntrinsicWidth(perColumn[c], spec.minimumWidth);
    });
    index = 0;
    for (final row in spec.rows) {
      var column = 0;
      for (final cell in row.cells) {
        final box = cells[index++];
        if (cell.columnSpan > 1) {
          final covered = widths
              .sublist(column, column + cell.columnSpan)
              .fold(0.0, (a, b) => a + b);
          final missing = box.getMaxIntrinsicWidth(double.infinity) - covered;
          if (missing > 0) {
            for (var c = column; c < column + cell.columnSpan; c++) {
              widths[c] += missing / cell.columnSpan;
            }
          }
        }
        column += cell.columnSpan;
      }
    }
    final total = widths.fold(0.0, (a, b) => a + b);
    if (total < spec.minimumWidth && widths.isNotEmpty) {
      final flex = List.generate(
        spec.columns,
        (c) =>
            spec.columnWidths[c]?.flex(perColumn[c]) ??
            (spec.columnWidths[c] == null ? 1.0 : 0.0),
      );
      final sum = flex.fold(0.0, (a, b) => a + b);
      if (sum > 0) {
        for (var c = 0; c < widths.length; c++) {
          widths[c] += (spec.minimumWidth - total) * flex[c] / sum;
        }
      }
    }
    return widths;
  }

  @override
  void performLayout() {
    final cells = _cells;
    final widths = _widths(cells);
    final width = math.max(
      spec.minimumWidth,
      widths.fold(0.0, (a, b) => a + b),
    );
    var y = 0.0;
    var index = 0;
    _rowEnds = [];
    for (var r = 0; r < spec.rows.length; r++) {
      final row = spec.rows[r];
      var column = 0;
      var height = 0.0;
      final start = index;
      final cellWidths = <double>[];
      for (final cell in row.cells) {
        final w = widths
            .sublist(column, column + cell.columnSpan)
            .fold(0.0, (a, b) => a + b);
        cells[index].layout(
          BoxConstraints.tightFor(width: w),
          parentUsesSize: true,
        );
        height = math.max(height, cells[index++].size.height);
        cellWidths.add(w);
        column += cell.columnSpan;
      }
      // Collapsed borders occupy one pixel between rows, outside cell padding.
      final top = r == spec.footerStart ? 1.0 : 0.0;
      var x = 0.0;
      for (var c = 0; c < row.cells.length; c++) {
        final box = cells[start + c];
        final w = cellWidths[c];
        box.layout(BoxConstraints.tight(Size(w, height)), parentUsesSize: true);
        (box.parentData! as _CellData).offset = Offset(
          spec.direction == TextDirection.ltr ? x : width - x - w,
          y + top,
        );
        x += w;
      }
      y += top + height + (spec.borders[r] ? 1 : 0);
      _rowEnds.add(y);
    }
    if (spec.hasCaption) {
      final caption = cells.last;
      caption.layout(
        BoxConstraints.tightFor(width: width),
        parentUsesSize: true,
      );
      (caption.parentData! as _CellData).offset = Offset(0, y);
      y += caption.size.height;
    }
    size = constraints.constrain(Size(width, y));
  }

  final Map<int, SemanticsNode> _semanticRows = {};
  SemanticsNode? _semanticTable;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
    config.explicitChildNodes = true;
  }

  @override
  void clearSemantics() {
    super.clearSemantics();
    _semanticRows.clear();
    _semanticTable = null;
  }

  @override
  void assembleSemanticsNode(
    SemanticsNode node,
    SemanticsConfiguration config,
    Iterable<SemanticsNode> children,
  ) {
    final groups = List.generate(spec.rows.length, (_) => <SemanticsNode>[]);
    final captions = <SemanticsNode>[];
    for (final child in children) {
      final key = child.sortKey;
      if (key is OrdinalSortKey && spec.columns > 0) {
        final row = key.order ~/ spec.columns;
        if (row < groups.length) groups[row].add(child);
      } else {
        captions.add(child);
      }
    }
    final rows = <SemanticsNode>[];
    for (var r = 0; r < groups.length; r++) {
      final top = r == 0 ? 0.0 : _rowEnds[r - 1];
      final row = _semanticRows.putIfAbsent(r, () => SemanticsNode());
      // Identity transforms keep cell coordinates in table space. A row's
      // non-zero local rect bounds precisely its cells without moving them.
      row
        ..rect = Rect.fromLTWH(0, top, size.width, _rowEnds[r] - top)
        ..updateWith(
          config: SemanticsConfiguration()
            ..role = SemanticsRole.row
            ..indexInParent = r,
          childrenInInversePaintOrder: groups[r],
        );
      rows.add(row);
    }
    _semanticRows.removeWhere((r, _) => r >= groups.length);
    final table = _semanticTable ??= SemanticsNode();
    table
      ..rect = Rect.fromLTWH(0, 0, size.width, _rowEnds.lastOrNull ?? 0)
      ..updateWith(
        config: SemanticsConfiguration()..role = SemanticsRole.table,
        childrenInInversePaintOrder: rows,
      );
    node.updateWith(
      config: config,
      childrenInInversePaintOrder: [table, ...captions],
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
    final paint = Paint()..color = spec.border;
    for (var r = 0; r < _rowEnds.length; r++) {
      if (spec.borders[r]) {
        context.canvas.drawRect(
          Rect.fromLTWH(offset.dx, offset.dy + _rowEnds[r] - 1, size.width, 1),
          paint,
        );
      }
      if (r == spec.footerStart) {
        context.canvas.drawRect(
          Rect.fromLTWH(
            offset.dx,
            offset.dy + (r == 0 ? 0 : _rowEnds[r - 1]),
            size.width,
            1,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
