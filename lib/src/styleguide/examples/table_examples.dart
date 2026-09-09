import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final tableExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'A responsive presentation table with shared columns and composable cells.',
  notes:
      'Base-nova Table geometry; native visual review pending. Header/body/footer/row '
      'are immutable composition values, cells and caption are widgets. Import '
      'package:discourse_native/discourse_ui.dart. Tables do not add sorting, '
      'pagination or selection controls: those belong to Data Table and callers. '
      'Actions compose DButton and native MenuAnchor pending '
      'Dropdown Menu. All examples use local data. Natural-width content '
      'scrolls horizontally; explicit columns can opt into wrapping. Child controls '
      'own keyboard focus, Form state, touch targets and menu restoration.',
  examples: [
    StyleguideExample(
      title: 'Default invoices',
      description:
          'The frozen seven invoices, 100px first column, spanning total and bottom caption.',
      code: _invoiceCode(),
      builder: (_) => const TableInvoiceExample(),
    ),
    StyleguideExample(
      title: 'Footer',
      description:
          'The reference three-row excerpt retains its displayed total of \$2,500.00.',
      code: _invoiceCode(count: 3),
      builder: (_) => const TableInvoiceExample(count: 3),
    ),
    StyleguideExample(
      title: 'Actions',
      description:
          'Open a product menu and Edit, Duplicate or Delete local rows. Open menus highlight their row.',
      code: _actionsCode,
      builder: (_) => const TableActionsExample(),
      states: const ['hover', 'expanded', 'keyboard', 'empty'],
    ),
    StyleguideExample(
      title: 'Controlled selection',
      description:
          'A composed action changes a controlled selected row and its semantic selected state.',
      code: _selectionCode,
      builder: (_) => const _Selection(),
      states: const ['selected', 'hover'],
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Frozen Arabic invoice composition with logical start/end alignment. Try 200% text and 360px width.',
      code: _invoiceCode(rtl: true),
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: TableInvoiceExample(arabic: true),
      ),
      states: const ['RTL', 'large text', 'horizontal overflow'],
    ),
  ],
);

const _invoices = [
  ('INV001', 'Paid', 'Credit Card', '\$250.00'),
  ('INV002', 'Pending', 'PayPal', '\$150.00'),
  ('INV003', 'Unpaid', 'Bank Transfer', '\$350.00'),
  ('INV004', 'Paid', 'Credit Card', '\$450.00'),
  ('INV005', 'Paid', 'PayPal', '\$550.00'),
  ('INV006', 'Pending', 'Bank Transfer', '\$200.00'),
  ('INV007', 'Unpaid', 'Credit Card', '\$300.00'),
];
const _arabic = {
  'Invoice': 'الفاتورة',
  'Status': 'الحالة',
  'Method': 'الطريقة',
  'Amount': 'المبلغ',
  'Paid': 'مدفوع',
  'Pending': 'قيد الانتظار',
  'Unpaid': 'غير مدفوع',
  'Credit Card': 'بطاقة ائتمانية',
  'Bank Transfer': 'تحويل بنكي',
};

/// Local-data fixture also used by the native review runner.
class TableInvoiceExample extends StatelessWidget {
  const TableInvoiceExample({super.key, this.count = 7, this.arabic = false});
  final int count;
  final bool arabic;
  @override
  Widget build(BuildContext context) {
    String t(String text) => arabic ? _arabic[text] ?? text : text;
    return DTable(
      columnWidths: const {
        0: MaxColumnWidth(FixedColumnWidth(100), IntrinsicColumnWidth()),
      },
      caption: DTableCaption(
        child: Text(
          arabic
              ? 'قائمة بفواتيرك الأخيرة.'
              : 'A list of your recent invoices.',
        ),
      ),
      header: DTableHeader(
        rows: [
          DTableRow(
            cells: [
              for (final name in ['Invoice', 'Status', 'Method', 'Amount'])
                DTableHead(
                  alignment: name == 'Amount'
                      ? AlignmentDirectional.centerEnd
                      : AlignmentDirectional.centerStart,
                  child: Text(t(name)),
                ),
            ],
          ),
        ],
      ),
      body: DTableBody(
        rows: [
          for (final row in _invoices.take(count))
            DTableRow(
              key: ValueKey(row.$1),
              cells: [
                DTableCell(
                  textStyle: const TextStyle(fontWeight: FontWeight.w500),
                  child: Text(row.$1),
                ),
                DTableCell(child: Text(t(row.$2))),
                DTableCell(child: Text(t(row.$3))),
                DTableCell(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(row.$4),
                ),
              ],
            ),
        ],
      ),
      footer: DTableFooter(
        rows: [
          DTableRow(
            cells: [
              DTableCell(
                columnSpan: 3,
                child: Text(arabic ? 'المجموع' : 'Total'),
              ),
              const DTableCell(
                alignment: AlignmentDirectional.centerEnd,
                child: Text('\$2,500.00'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TableActionsExample extends StatefulWidget {
  const TableActionsExample({super.key});
  @override
  State<TableActionsExample> createState() => _TableActionsExampleState();
}

class _TableActionsExampleState extends State<TableActionsExample> {
  final _products = <(int, String, String)>[
    (0, 'Wireless Mouse', '\$29.99'),
    (1, 'Mechanical Keyboard', '\$129.99'),
    (2, 'USB-C Hub', '\$49.99'),
  ];
  int _nextId = 3;
  int? _expanded;
  String _status = '';
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DTable(
        header: const DTableHeader(
          rows: [
            DTableRow(
              cells: [
                DTableHead(child: Text('Product')),
                DTableHead(child: Text('Price')),
                DTableHead(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text('Actions'),
                ),
              ],
            ),
          ],
        ),
        body: DTableBody(
          rows: [
            for (final product in _products)
              DTableRow(
                key: ValueKey(product.$1),
                expanded: _expanded == product.$1,
                cells: [
                  DTableCell(
                    textStyle: const TextStyle(fontWeight: FontWeight.w500),
                    child: Text(product.$2),
                  ),
                  DTableCell(child: Text(product.$3)),
                  DTableCell(
                    alignment: AlignmentDirectional.centerEnd,
                    child: MenuAnchor(
                      onOpen: () => setState(() => _expanded = product.$1),
                      onClose: () => setState(() => _expanded = null),
                      menuChildren: [
                        for (final action in ['Edit', 'Duplicate', 'Delete'])
                          MenuItemButton(
                            autofocus: action == 'Edit',
                            onPressed: () => setState(() {
                              final index = _products.indexWhere(
                                (p) => p.$1 == product.$1,
                              );
                              if (action == 'Edit') {
                                _products[index] = (
                                  product.$1,
                                  '${product.$2} (edited)',
                                  product.$3,
                                );
                              }
                              if (action == 'Duplicate') {
                                _products.insert(index + 1, (
                                  _nextId++,
                                  '${product.$2} (copy)',
                                  product.$3,
                                ));
                              }
                              if (action == 'Delete') _products.removeAt(index);
                              _status = '$action: ${product.$2}';
                            }),
                            child: Text(action),
                          ),
                      ],
                      builder: (context, controller, child) => DButton.iconOnly(
                        variant: DButtonVariant.ghost,
                        size: DButtonSize.regular,
                        hasPopup: true,
                        tooltip: 'Open menu for ${product.$2}',
                        icon: const Icon(Icons.more_horiz),
                        onPressed: () => controller.isOpen
                            ? controller.close()
                            : controller.open(),
                      ),
                    ),
                  ),
                ],
              ),
            if (_products.isEmpty)
              const DTableRow(
                cells: [
                  DTableCell(
                    columnSpan: 3,
                    child: Text(
                      'No products. Use Reset to restore the sample.',
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      if (_status.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Semantics(liveRegion: true, child: Text(_status)),
        ),
    ],
  );
}

class _Selection extends StatefulWidget {
  const _Selection();
  @override
  State<_Selection> createState() => _SelectionState();
}

class _SelectionState extends State<_Selection> {
  bool _selected = false;
  @override
  Widget build(BuildContext context) => DTable(
    header: const DTableHeader(
      rows: [
        DTableRow(
          cells: [
            DTableHead(child: Text('Invoice')),
            DTableHead(child: Text('Selection')),
          ],
        ),
      ],
    ),
    body: DTableBody(
      rows: [
        DTableRow(
          selected: _selected,
          cells: [
            const DTableCell(child: Text('INV001')),
            DTableCell(
              child: DButton(
                variant: DButtonVariant.ghost,
                label: Text(_selected ? 'Selected — clear' : 'Select invoice'),
                onPressed: () => setState(() => _selected = !_selected),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

String _invoiceCode({int count = 7, bool rtl = false}) {
  final data = _invoices
      .take(count)
      .map(
        (r) =>
            "  ('${r.$1}', '${rtl ? _arabic[r.$2] : r.$2}', '${rtl ? _arabic[r.$3] ?? r.$3 : r.$3}', r'${r.$4}'),",
      )
      .join('\n');
  return """import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

class InvoiceTable extends StatelessWidget {
  const InvoiceTable({super.key});
  @override
  Widget build(BuildContext context) {
    const invoices = [
$data
    ];
    return Directionality(textDirection: TextDirection.${rtl ? 'rtl' : 'ltr'}, child: DTable(
      columnWidths: const {0: MaxColumnWidth(FixedColumnWidth(100), IntrinsicColumnWidth())},
      caption: const DTableCaption(child: Text('${rtl ? 'قائمة بفواتيرك الأخيرة.' : 'A list of your recent invoices.'}')),
      header: const DTableHeader(rows: [DTableRow(cells: [
        DTableHead(child: Text('${rtl ? 'الفاتورة' : 'Invoice'}')),
        DTableHead(child: Text('${rtl ? 'الحالة' : 'Status'}')),
        DTableHead(child: Text('${rtl ? 'الطريقة' : 'Method'}')),
        DTableHead(alignment: AlignmentDirectional.centerEnd, child: Text('${rtl ? 'المبلغ' : 'Amount'}')),
      ])]),
      body: DTableBody(rows: [for (final row in invoices) DTableRow(cells: [
        DTableCell(textStyle: const TextStyle(fontWeight: FontWeight.w500), child: Text(row.\$1)),
        DTableCell(child: Text(row.\$2)), DTableCell(child: Text(row.\$3)),
        DTableCell(alignment: AlignmentDirectional.centerEnd, child: Text(row.\$4)),
      ])]),
      footer: const DTableFooter(rows: [DTableRow(cells: [
        DTableCell(columnSpan: 3, child: Text('${rtl ? 'المجموع' : 'Total'}')),
        DTableCell(alignment: AlignmentDirectional.centerEnd, child: Text(r'\$2,500.00')),
      ])]),
    ));
  }
}""";
}

// These complete usage listings mirror the runnable state owners above.
const _actionsCode = r'''
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

class ProductTable extends StatefulWidget {
  const ProductTable({super.key});
  @override
  State<ProductTable> createState() => _ProductTableState();
}
class _ProductTableState extends State<ProductTable> {
  final products = <(int, String, String)>[
    (0, 'Wireless Mouse', '$29.99'), (1, 'Mechanical Keyboard', '$129.99'), (2, 'USB-C Hub', '$49.99')];
  int nextId = 3;
  int? expanded;
  @override
  Widget build(BuildContext context) => DTable(
    header: const DTableHeader(rows: [DTableRow(cells: [
      DTableHead(child: Text('Product')), DTableHead(child: Text('Price')),
      DTableHead(alignment: AlignmentDirectional.centerEnd, child: Text('Actions')),
    ])]),
    body: DTableBody(rows: [for (final p in products)
      DTableRow(key: ValueKey(p.$1), expanded: expanded == p.$1, cells: [
        DTableCell(child: Text(p.$2)), DTableCell(child: Text(p.$3)),
        DTableCell(alignment: AlignmentDirectional.centerEnd, child: MenuAnchor(
          onOpen: () => setState(() => expanded = p.$1),
          onClose: () => setState(() => expanded = null),
          menuChildren: [for (final action in ['Edit', 'Duplicate', 'Delete'])
            MenuItemButton(autofocus: action == 'Edit', onPressed: () => setState(() {
              final i = products.indexWhere((item) => item.$1 == p.$1);
              if (action == 'Edit') products[i] = (p.$1, '${p.$2} (edited)', p.$3);
              if (action == 'Duplicate') products.insert(i + 1, (nextId++, '${p.$2} (copy)', p.$3));
              if (action == 'Delete') products.removeAt(i);
            }), child: Text(action)),
          ],
          builder: (context, menu, child) => DButton(
            onPressed: () => menu.isOpen ? menu.close() : menu.open(),
            label: Text('Open menu for ${p.$2}')),
        )),
      ]),
      if (products.isEmpty) const DTableRow(cells: [DTableCell(columnSpan: 3, child: Text('No products'))]),
    ]),
  );
}
''';
const _selectionCode = r'''
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

class SelectedTable extends StatefulWidget {
  const SelectedTable({super.key});
  @override
  State<SelectedTable> createState() => _SelectedTableState();
}
class _SelectedTableState extends State<SelectedTable> {
  bool selected = false;
  @override
  Widget build(BuildContext context) => DTable(
    header: const DTableHeader(rows: [DTableRow(cells: [
      DTableHead(child: Text('Invoice')), DTableHead(child: Text('Selection')),
    ])]),
    body: DTableBody(rows: [DTableRow(selected: selected, cells: [
      const DTableCell(child: Text('INV001')),
      DTableCell(child: DButton(onPressed: () => setState(() => selected = !selected),
        label: Text(selected ? 'Selected — clear' : 'Select invoice'))),
    ])]),
  );
}
''';
