import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

/// Adapts ordinary cooked Markdown tables. Document tables with merged cells,
/// multiple headers or footers retain the HTML renderer's structural support.
Widget? cookedTableWidgetBuilder(
  dom.Element element, {
  required Widget Function(BuildContext, String) cellBuilder,
}) {
  if (element.localName != 'table') return null;
  final rows = element.querySelectorAll('tr');
  if (rows.isEmpty ||
      element.querySelector('table, tfoot') != null ||
      rows.first.children.isEmpty ||
      rows.first.children.any((cell) => cell.localName != 'th')) {
    return null;
  }
  final headers = rows.first.children;
  // Interactive header content must keep its original targets.
  if (headers.any(
    (cell) => cell.querySelector('a, img, button, input') != null,
  )) {
    return null;
  }
  for (final (index, row) in rows.indexed) {
    if (row.children.length != headers.length ||
        row.children.any(
          (cell) =>
              cell.localName != (index == 0 ? 'th' : 'td') ||
              !{null, '1'}.contains(cell.attributes['colspan']) ||
              !{null, '1'}.contains(cell.attributes['rowspan']),
        )) {
      return null;
    }
  }
  return _CookedTable(
    key: ValueKey(element.outerHtml),
    headers: [for (final cell in headers) _Cell(cell)],
    rows: [
      for (final row in rows.skip(1))
        [for (final cell in row.children) _Cell(cell)],
    ],
    caption: element.querySelector('caption')?.innerHtml,
    cellBuilder: cellBuilder,
  );
}

class _Cell {
  _Cell(dom.Element element)
    : text = element.text.trim().replaceAll(RegExp(r'\s+'), ' '),
      html =
          (dom.Element.tag('div')
                ..attributes.addAll(element.attributes)
                ..innerHtml = element.innerHtml)
              .outerHtml;

  final String text;
  final String html;
}

class _CookedTable extends StatefulWidget {
  const _CookedTable({
    super.key,
    required this.headers,
    required this.rows,
    required this.caption,
    required this.cellBuilder,
  });

  final List<_Cell> headers;
  final List<List<_Cell>> rows;
  final String? caption;
  final Widget Function(BuildContext, String) cellBuilder;

  @override
  State<_CookedTable> createState() => _CookedTableState();
}

class _CookedTableState extends State<_CookedTable> {
  late DDataTableState _state = DDataTableState(
    pageSize: math.max(1, widget.rows.length),
  );

  @override
  Widget build(BuildContext context) {
    final columns = [
      for (var index = 0; index < widget.headers.length; index++)
        DDataTableColumn<int>(
          id: '$index',
          label: widget.headers[index].text.isEmpty
              ? 'Column ${index + 1}'
              : widget.headers[index].text,
          resizable: true,
          width: FixedColumnWidth(_initialWidth(context, index)),
          compare: (first, second) => _compare(
            widget.rows[first][index].text,
            widget.rows[second][index].text,
          ),
          headerBuilder: (context, header) => DDataTableColumnHeader(
            title: header.column.label,
            sortDirection: header.sortDirection,
            onSortChanged: header.onSortChanged,
            onHide: () => header.onVisibilityChanged!(false),
          ),
          cellBuilder: (context, cell) =>
              widget.cellBuilder(context, widget.rows[cell.row][index].html),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: DDataTableColumnToggle(
            columns: columns,
            hiddenColumnIds: _state.hiddenColumnIds,
            onChanged: (hidden) => setState(() {
              _state = _state.copyWith(hiddenColumnIds: hidden);
            }),
          ),
        ),
        const SizedBox(height: DSpacing.sm),
        DDataTable<int>(
          data: List.generate(widget.rows.length, (index) => index),
          columns: columns,
          rowId: (row) => row,
          state: _state,
          onStateChanged: (state) => setState(() => _state = state),
          empty: const SizedBox.shrink(),
        ),
        if (widget.caption case final caption?)
          DTableCaption(child: widget.cellBuilder(context, caption)),
      ],
    );
  }

  double _initialWidth(BuildContext context, int column) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    try {
      var width = 140.0;
      for (final cell in [
        widget.headers[column],
        ...widget.rows.map((row) => row[column]),
      ]) {
        painter.text = TextSpan(
          text: cell.text,
          style: Theme.of(context).textTheme.bodyMedium,
        );
        painter.layout(maxWidth: 320);
        width = math.max(width, painter.width + 48);
        if (width >= 360) return 360;
      }
      return width;
    } finally {
      painter.dispose();
    }
  }
}

int _compare(String first, String second) {
  final a = num.tryParse(first);
  final b = num.tryParse(second);
  if (a != null && b != null) return a.compareTo(b);
  if (a != null) return -1;
  if (b != null) return 1;
  return first.toLowerCase().compareTo(second.toLowerCase());
}
