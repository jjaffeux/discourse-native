import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;

import '../models/post_checklist.dart';
import '../theme/d_icons.dart';

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
    key: ValueKey(PostChecklistDocument.contentKey(element.outerHtml)),
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
      copyText = _copyCellText(element),
      html =
          (dom.Element.tag('div')
                ..attributes.addAll(element.attributes)
                ..innerHtml = element.innerHtml)
              .outerHtml;

  final String text;
  final String copyText;
  final String html;
}

String _copyCellText(dom.Element element) {
  final copy = element.clone(true);
  for (final br in copy.querySelectorAll('br')) {
    br.replaceWith(dom.Text('<br>'));
  }
  return copy.text.trim().replaceAll(RegExp(r'\s+'), ' ');
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
  bool _copied = false;
  Timer? _copyReset;

  Future<void> _copyTable() async {
    String line(List<_Cell> cells) =>
        '| ${cells.map((cell) => cell.copyText.replaceAll(r'\', r'\\').replaceAll('|', r'\|')).join(' | ')} |';
    await Clipboard.setData(
      ClipboardData(
        text: [
          line(widget.headers),
          '| ${List.filled(widget.headers.length, '---').join(' | ')} |',
          ...widget.rows.map(line),
        ].join('\n'),
      ),
    );
    if (!mounted) return;
    setState(() => _copied = true);
    _copyReset?.cancel();
    _copyReset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _copyReset?.cancel();
    super.dispose();
  }

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
              ? context.l10n.columnCookedtable((index + 1).toString())
              : widget.headers[index].text,
          resizable: true,
          alignment: AlignmentDirectional.topStart,
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
            size: DControlSize.post,
          ),
          cellBuilder: (context, cell) => DefaultTextStyle.merge(
            style: TextStyle(
              fontWeight: index == 0 ? FontWeight.w600 : FontWeight.w400,
            ),
            child: Builder(
              builder: (context) => widget.cellBuilder(
                context,
                widget.rows[cell.row][index].html,
              ),
            ),
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            DButton.iconOnly(
              tooltip: _copied
                  ? context.l10n.tableCopied
                  : context.l10n.copyTable,
              variant: DButtonVariant.outline,
              size: DButtonSize.post,
              icon: DIcon(_copied ? DIcons.check : DIcons.copy, size: 16),
              onPressed: _copyTable,
            ),
            const SizedBox(width: DSpacing.sm),
            DDataTableColumnToggle(
              columns: columns,
              hiddenColumnIds: _state.hiddenColumnIds,
              onChanged: (hidden) => setState(() {
                _state = _state.copyWith(hiddenColumnIds: hidden);
              }),
              size: DControlSize.post,
            ),
          ],
        ),
        const SizedBox(height: DSpacing.sm),
        DDataTable<int>(
          variant: DDataTableVariant.softHeader,
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
