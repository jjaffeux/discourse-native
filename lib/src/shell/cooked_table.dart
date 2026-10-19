import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/html_escape.dart';

import '../theme/d_icons.dart';
import 'cooked_document.dart';
import 'cooked_dom.dart';

/// Adapts ordinary cooked Markdown tables. Document tables with merged cells,
/// multiple headers or footers retain the HTML renderer's structural support.
Widget? cookedTableWidgetBuilder(
  dom.Element element, {
  required CookedContent content,
}) {
  if (element.localName != 'table') return null;
  final rows = element.querySelectorAll('tr');
  if (rows.isEmpty ||
      element.querySelector('table, tfoot') != null ||
      childElements(rows.first).isEmpty ||
      childElements(rows.first).any((cell) => cell.localName != 'th')) {
    return null;
  }
  final headers = childElements(rows.first);
  // Interactive header content must keep its original targets.
  if (headers.any(
    (cell) => cell.querySelector('a, img, button, input') != null,
  )) {
    return null;
  }
  for (final (index, row) in rows.indexed) {
    if (childElements(row).length != headers.length ||
        childElements(row).any(
          (cell) =>
              cell.localName != (index == 0 ? 'th' : 'td') ||
              !{null, '1'}.contains(cell.attributes['colspan']) ||
              !{null, '1'}.contains(cell.attributes['rowspan']),
        )) {
      return null;
    }
  }
  return _CookedTable(
    key: ValueKey(content.stateKey(element)),
    headers: [for (final cell in headers) _Cell(cell)],
    rows: [
      for (final row in rows.skip(1))
        [for (final cell in childElements(row)) _Cell(cell)],
    ],
    caption: element.querySelector('caption')?.innerHtml,
    content: content,
  );
}

class _Cell {
  _Cell(dom.Element element)
    : text = element.text.trim().replaceAll(RegExp(r'\s+'), ' '),
      copyText = _copyCellText(element),
      html = _cellHtml(element);

  final String text;
  final String copyText;
  final String html;
}

final _cellRawText = RegExp(
  r'<(?:plaintext|script)(?:\s|>)',
  caseSensitive: false,
);

String _cellHtml(dom.Element element) {
  final body = element.innerHtml;
  if (_cellRawText.hasMatch(body)) {
    return (dom.Element.tag('div')
          ..attributes.addAll(element.attributes)
          ..innerHtml = body)
        .outerHtml;
  }
  final html = StringBuffer('<div');
  element.attributes.forEach((name, value) {
    html
      ..write(' ')
      ..write(name)
      ..write('="')
      ..write(htmlSerializeEscape(value, attributeMode: true))
      ..write('"');
  });
  return (html
        ..write('>')
        ..write(body)
        ..write('</div>'))
      .toString();
}

String _copyCellText(dom.Element element) {
  final text = StringBuffer();
  void visit(dom.Node node) {
    if (node is dom.Text) {
      text.write(node.data);
    } else if (node is dom.Element && node.localName == 'br') {
      text.write('<br>');
    } else {
      for (final child in node.nodes) {
        visit(child);
      }
    }
  }

  visit(element);
  return text.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

class _CookedTable extends StatefulWidget {
  const _CookedTable({
    super.key,
    required this.headers,
    required this.rows,
    required this.caption,
    required this.content,
  });

  final List<_Cell> headers;
  final List<List<_Cell>> rows;
  final String? caption;
  final CookedContent content;

  @override
  State<_CookedTable> createState() => _CookedTableState();
}

class _CookedTableState extends State<_CookedTable> {
  static const _pageSize = 25;

  bool _copied = false;
  Timer? _copyReset;
  ({TextStyle? style, TextDirection direction, TextScaler scaler})?
  _widthInputs;
  List<double> _initialWidths = [];
  late final List<int> _rowIndexes = List.generate(
    widget.rows.length,
    (index) => index,
  );
  List<DDataTableColumn<int>>? _columns;
  Locale? _columnLocale;

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

  DDataTableState _state = DDataTableState(pageSize: _pageSize);

  @override
  Widget build(BuildContext context) {
    final widthInputs = (
      style: Theme.of(context).textTheme.bodyMedium,
      direction: Directionality.of(context),
      scaler: MediaQuery.textScalerOf(context),
    );
    if (_widthInputs != widthInputs) {
      _initialWidths = [
        for (var index = 0; index < widget.headers.length; index++)
          _initialWidth(context, index),
      ];
      _widthInputs = widthInputs;
      _columns = null;
    }
    final locale = Localizations.localeOf(context);
    if (_columnLocale != locale) {
      _columnLocale = locale;
      _columns = null;
    }
    final columns = _columns ??= [
      for (var index = 0; index < widget.headers.length; index++)
        DDataTableColumn<int>(
          id: '$index',
          label: widget.headers[index].text.isEmpty
              ? context.l10n.columnCookedtable((index + 1).toString())
              : widget.headers[index].text,
          resizable: true,
          alignment: AlignmentDirectional.topStart,
          width: FixedColumnWidth(_initialWidths[index]),
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
              builder: (context) => widget.content(
                context,
                widget.rows[cell.row][index].html,
                style: DefaultTextStyle.of(context).style,
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
          data: _rowIndexes,
          columns: columns,
          rowId: (row) => row,
          state: _state,
          onStateChanged: (state) => setState(() => _state = state),
          empty: const SizedBox.shrink(),
        ),
        if (widget.rows.length > _pageSize) ...[
          const SizedBox(height: DSpacing.sm),
          DPaginationNavigation.controlled(
            page: _state.page,
            pageCount: DPaginationController.pageCountFor(
              totalItems: widget.rows.length,
              pageSize: _pageSize,
            ),
            pageSize: _pageSize,
            size: DButtonSize.post,
            onPageChanged: (page) => setState(() {
              _state = _state.copyWith(page: page);
            }),
          ),
        ],
        if (widget.caption case final caption?)
          DTableCaption(
            child: widget.content(
              context,
              caption,
              style: DefaultTextStyle.of(context).style,
            ),
          ),
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
        ...widget.rows.take(_pageSize).map((row) => row[column]),
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
