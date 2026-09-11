import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final dataTableExamples = ComponentExamples(
  topLevelExampleIndex: 2,
  status: ComponentStatus.implemented,
  description:
      'A typed, headless-friendly table with sorting, filtering, visibility, stable selection, row actions, and local or server-controlled state.',
  notes:
      'Ports the frozen Base UI/base-nova Data Table guide without bringing a web TanStack dependency into Flutter. Columns define stable IDs, typed cell formatting and optional compare/filter functions; rows define stable IDs separately from their display order. DTable remains the semantic presentation owner while Checkbox, Input, Dropdown Menu, Button, Badge, Pagination and Select retain their independent interactions. Accepted shared owners are integrated. Independent rendered-reference and macOS review covers the documented compositions, keyboard actions, live palettes, RTL, reduced motion and narrow large-text layouts; exact evidence and platform limits are recorded in the component documentation.',
  examples: [
    StyleguideExample(
      title: 'Resizable virtual directory',
      description:
          'Scroll 1,000 rows beneath a stationary header. Drag a column edge or focus it and use arrow keys; widths survive table rebuilds.',
      code: _virtualCode,
      builder: (_) => const _VirtualDirectoryExample(),
      states: const ['resize', 'keyboard', 'large text', 'virtual scrolling'],
    ),
    StyleguideExample(
      title: 'Basic table and cell formatting',
      description:
          'Typed payment columns, a capitalized status Badge and end-aligned currency formatting.',
      code: _basicCode,
      builder: (_) => const DataTableBasicExample(),
      states: const ['empty', 'horizontal overflow', 'large text'],
    ),
    StyleguideExample(
      title: 'Sorting, filtering, visibility, selection, and actions',
      description:
          'Filter emails, open a sortable column header, toggle columns repeatedly, select stable row IDs and run independent row actions.',
      code: _interactiveCode,
      builder: (_) => const DataTableInteractiveExample(),
      states: const [
        'selected',
        'mixed',
        'hover',
        'focus',
        'keyboard',
        'empty',
      ],
    ),
    StyleguideExample(
      title: 'Dynamic data',
      description:
          'Reorder or remove immutable row snapshots while selection follows stable IDs rather than positions.',
      code: _dynamicCode,
      builder: (_) => const DataTableDynamicExample(),
      states: const ['controlled data', 'stable selection', 'empty'],
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Arabic labels, logical cell alignment and mirrored popup placement remain usable at 360px and 200% text.',
      code: _rtlCode,
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: DataTableInteractiveExample(arabic: true),
      ),
      states: const ['RTL', 'large text', 'horizontal overflow'],
    ),
  ],
);

enum _PaymentStatus { pending, processing, success, failed }

typedef _Payment = ({
  String id,
  int amount,
  _PaymentStatus status,
  String email,
});

const _payments = <_Payment>[
  (
    id: 'm5gr84i9',
    amount: 316,
    status: _PaymentStatus.success,
    email: 'ken99@example.com',
  ),
  (
    id: '3u1reuv4',
    amount: 242,
    status: _PaymentStatus.success,
    email: 'Abe45@example.com',
  ),
  (
    id: 'derv1ws0',
    amount: 837,
    status: _PaymentStatus.processing,
    email: 'Monserrat44@example.com',
  ),
  (
    id: '5kma53ae',
    amount: 874,
    status: _PaymentStatus.success,
    email: 'Silas22@example.com',
  ),
  (
    id: 'bhqecj4p',
    amount: 721,
    status: _PaymentStatus.failed,
    email: 'carmella@example.com',
  ),
];

const _extendedPayments = <_Payment>[
  ..._payments,
  (
    id: 'j8p6e3x1',
    amount: 128,
    status: _PaymentStatus.pending,
    email: 'nora@example.com',
  ),
  (
    id: 'v4m2r7k9',
    amount: 490,
    status: _PaymentStatus.processing,
    email: 'liam@example.com',
  ),
  (
    id: 'q2a7s5d8',
    amount: 605,
    status: _PaymentStatus.success,
    email: 'yara@example.com',
  ),
  (
    id: 'f6g1h9l3',
    amount: 274,
    status: _PaymentStatus.failed,
    email: 'omar@example.com',
  ),
  (
    id: 'c9b4n2w7',
    amount: 955,
    status: _PaymentStatus.success,
    email: 'sara@example.com',
  ),
  (
    id: 't5u8i1o6',
    amount: 346,
    status: _PaymentStatus.pending,
    email: 'noah@example.com',
  ),
  (
    id: 'r3e7y9p2',
    amount: 780,
    status: _PaymentStatus.processing,
    email: 'lina@example.com',
  ),
];

List<DDataTableColumn<_Payment>> _paymentColumns({
  required bool arabic,
  bool interactiveHeaders = false,
  ValueChanged<_Payment>? onAction,
}) {
  String t(String english, String translated) => arabic ? translated : english;
  DDataTableColumn<_Payment> column({
    required String id,
    required String label,
    required DDataTableCellBuilder<_Payment> cell,
    DDataTableComparator<_Payment>? compare,
    String Function(_Payment)? filterText,
    bool hideable = true,
    AlignmentGeometry alignment = AlignmentDirectional.centerStart,
    AlignmentGeometry headerAlignment = AlignmentDirectional.centerStart,
    TableColumnWidth? width,
  }) => DDataTableColumn(
    id: id,
    label: label,
    compare: compare,
    filterText: filterText,
    hideable: hideable,
    alignment: alignment,
    headerAlignment: headerAlignment,
    width: width,
    headerBuilder: compare == null || !interactiveHeaders
        ? null
        : (context, header) => DDataTableColumnHeader(
            title: header.column.label,
            sortDirection: header.sortDirection,
            onSortChanged: header.onSortChanged,
            onHide: header.onVisibilityChanged == null
                ? null
                : () => header.onVisibilityChanged!(false),
            ascendingLabel: t('Sort ascending', 'ترتيب تصاعدي'),
            descendingLabel: t('Sort descending', 'ترتيب تنازلي'),
            hideLabel: t('Hide column', 'إخفاء العمود'),
          ),
    cellBuilder: cell,
  );

  return [
    column(
      id: 'status',
      label: t('Status', 'الحالة'),
      compare: (first, second) =>
          first.status.index.compareTo(second.status.index),
      filterText: (row) => row.status.name,
      cell: (context, cell) => DBadge(
        variant: switch (cell.row.status) {
          _PaymentStatus.failed => DBadgeVariant.destructive,
          _PaymentStatus.processing => DBadgeVariant.secondary,
          _ => DBadgeVariant.outline,
        },
        child: Text(switch (cell.row.status) {
          _PaymentStatus.pending => t('Pending', 'قيد الانتظار'),
          _PaymentStatus.processing => t('Processing', 'قيد المعالجة'),
          _PaymentStatus.success => t('Success', 'ناجح'),
          _PaymentStatus.failed => t('Failed', 'فشل'),
        }),
      ),
    ),
    column(
      id: 'email',
      label: t('Email', 'البريد الإلكتروني'),
      compare: (first, second) =>
          first.email.toLowerCase().compareTo(second.email.toLowerCase()),
      filterText: (row) => row.email,
      width: const MaxColumnWidth(
        FixedColumnWidth(180),
        IntrinsicColumnWidth(),
      ),
      cell: (context, cell) => Text(cell.row.email.toLowerCase()),
    ),
    column(
      id: 'amount',
      label: t('Amount', 'المبلغ'),
      compare: (first, second) => first.amount.compareTo(second.amount),
      filterText: (row) => '${row.amount}',
      alignment: AlignmentDirectional.centerEnd,
      headerAlignment: AlignmentDirectional.centerEnd,
      cell: (context, cell) => Text(
        '\$${cell.row.amount.toStringAsFixed(2)}',
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
    ),
    if (onAction != null)
      DDataTableColumn<_Payment>(
        id: 'actions',
        label: t('Actions', 'الإجراءات'),
        hideable: false,
        width: const FixedColumnWidth(48),
        alignment: AlignmentDirectional.centerEnd,
        headerAlignment: AlignmentDirectional.centerEnd,
        headerBuilder: (context, header) => Semantics(
          label: header.column.label,
          child: const SizedBox.shrink(),
        ),
        cellBuilder: (context, cell) => _PaymentActions(
          payment: cell.row,
          arabic: arabic,
          onAction: onAction,
        ),
      ),
  ];
}

class DataTableBasicExample extends StatelessWidget {
  const DataTableBasicExample({super.key});

  @override
  Widget build(BuildContext context) => DDataTable<_Payment>(
    data: _payments,
    columns: _paymentColumns(arabic: false),
    rowId: (row) => row.id,
    semanticLabel: 'Recent payments',
    minimumWidth: 480,
  );
}

class DataTableInteractiveExample extends StatefulWidget {
  const DataTableInteractiveExample({super.key, this.arabic = false});

  final bool arabic;

  @override
  State<DataTableInteractiveExample> createState() =>
      _DataTableInteractiveExampleState();
}

class _DataTableInteractiveExampleState
    extends State<DataTableInteractiveExample> {
  late final DDataTableController _controller = DDataTableController();
  String _status = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final arabic = widget.arabic;
    String t(String english, String translated) =>
        arabic ? translated : english;
    final columns = _paymentColumns(
      arabic: arabic,
      interactiveHeaders: true,
      onAction: (payment) => setState(() {
        _status = t('Opened ${payment.id}', 'تم فتح ${payment.id}');
      }),
    );
    final filter = _controller.value.filters['email'] ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            alignment: WrapAlignment.spaceBetween,
            runAlignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: mathMin(384, constraints.maxWidth),
                child: DDataTableFilterField(
                  value: filter,
                  hintText: t('Filter emails...', 'تصفية البريد الإلكتروني...'),
                  onChanged: (value) => _controller.setFilter('email', value),
                ),
              ),
              DDataTableColumnToggle<_Payment>(
                columns: columns,
                hiddenColumnIds: _controller.value.hiddenColumnIds,
                label: t('Columns', 'الأعمدة'),
                menuLabel: t('Toggle columns', 'تبديل الأعمدة'),
                onChanged: (hidden) => _controller.value = _controller.value
                    .copyWith(hiddenColumnIds: hidden, page: 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DDataTable<_Payment>(
          data: _extendedPayments,
          columns: columns,
          rowId: (row) => row.id,
          controller: _controller,
          selectable: true,
          selectAllLabel: t('Select all', 'تحديد الكل'),
          selectRowLabel: (row) =>
              t('Select ${row.email}', 'تحديد ${row.email}'),
          semanticLabel: t('Payments', 'المدفوعات'),
          minimumWidth: 620,
          footerBuilder: (context, metrics) => DDataTablePagination(
            metrics: metrics,
            rowsPerPageLabel: t('Rows per page', 'صفوف لكل صفحة'),
            pageLabel: arabic
                ? (page, pages) => 'الصفحة $page من $pages'
                : null,
            selectionLabel: arabic
                ? (selected, total) => '$selected من $total صف(وف) محدد.'
                : null,
            paginationLabel: t('Table pagination', 'ترقيم صفحات الجدول'),
            previousLabel: t('Previous', 'السابق'),
            nextLabel: t('Next', 'التالي'),
            onPageChanged: _controller.setPage,
            onPageSizeChanged: _controller.setPageSize,
          ),
        ),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(_status)),
        ],
      ],
    );
  }
}

class _PaymentActions extends StatelessWidget {
  const _PaymentActions({
    required this.payment,
    required this.arabic,
    required this.onAction,
  });

  final _Payment payment;
  final bool arabic;
  final ValueChanged<_Payment> onAction;

  @override
  Widget build(BuildContext context) {
    String t(String english, String translated) =>
        arabic ? translated : english;
    return DDropdownMenu(
      content: DDropdownMenuContent(
        align: DPopoverAlign.end,
        width: 176,
        semanticLabel: t('Payment actions', 'إجراءات الدفع'),
        children: [
          DDropdownMenuLabel(child: Text(t('Actions', 'الإجراءات'))),
          DDropdownMenuItem(
            onPressed: () => onAction(payment),
            child: Text(t('Copy payment ID', 'نسخ معرف الدفع')),
          ),
          const DDropdownMenuSeparator(),
          DDropdownMenuItem(
            onPressed: () => onAction(payment),
            child: Text(t('View customer', 'عرض العميل')),
          ),
          DDropdownMenuItem(
            onPressed: () => onAction(payment),
            child: Text(t('View payment details', 'عرض تفاصيل الدفع')),
          ),
        ],
      ),
      child: DDropdownMenuTrigger(
        builder: (context, trigger) => DButton.iconOnly(
          icon: const Icon(Icons.more_horiz),
          tooltip: t(
            'Open menu for ${payment.email}',
            'فتح قائمة ${payment.email}',
          ),
          variant: DButtonVariant.ghost,
          size: DButtonSize.extraSmall,
          hasPopup: true,
          expanded: trigger.open,
          focusNode: trigger.focusNode,
          onPressed: trigger.toggle,
        ),
      ),
    );
  }
}

class DataTableDynamicExample extends StatefulWidget {
  const DataTableDynamicExample({super.key});

  @override
  State<DataTableDynamicExample> createState() =>
      _DataTableDynamicExampleState();
}

class _DataTableDynamicExampleState extends State<DataTableDynamicExample> {
  final DDataTableController _controller = DDataTableController(
    initialState: DDataTableState(selectedRowIds: const {'3u1reuv4'}),
  );
  var _rows = List<_Payment>.of(_payments.take(3));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DButton(
            label: const Text('Reverse rows'),
            variant: DButtonVariant.outline,
            onPressed: () => setState(() => _rows = _rows.reversed.toList()),
          ),
          DButton(
            label: const Text('Remove first'),
            variant: DButtonVariant.ghost,
            onPressed: _rows.isEmpty
                ? null
                : () => setState(() => _rows = _rows.skip(1).toList()),
          ),
          DButton(
            label: const Text('Reset data'),
            variant: DButtonVariant.ghost,
            onPressed: () => setState(() {
              _rows = List<_Payment>.of(_payments.take(3));
            }),
          ),
        ],
      ),
      const SizedBox(height: 16),
      DDataTable<_Payment>(
        data: _rows,
        columns: _paymentColumns(arabic: false),
        rowId: (row) => row.id,
        controller: _controller,
        selectable: true,
        selectRowLabel: (row) => 'Select ${row.email}',
        minimumWidth: 480,
      ),
    ],
  );
}

double mathMin(double first, double second) => first < second ? first : second;

const _basicCode = '''
DDataTable<Payment>(
  data: payments,
  rowId: (payment) => payment.id,
  columns: [
    DDataTableColumn(
      id: 'amount',
      label: 'Amount',
      alignment: AlignmentDirectional.centerEnd,
      cellBuilder: (context, cell) => Text(format(cell.row.amount)),
    ),
  ],
)
''';

const _interactiveCode = '''
final controller = DDataTableController();

DDataTableFilterField(
  value: controller.value.filters['email'] ?? '',
  onChanged: (value) => controller.setFilter('email', value),
)
DDataTable<Payment>(
  data: payments,
  columns: columns,
  rowId: (payment) => payment.id,
  controller: controller,
  selectable: true,
)
''';

const _dynamicCode = '''
// Stable row IDs keep selection attached when immutable snapshots reorder.
DDataTable<Payment>(
  data: currentRows,
  rowId: (payment) => payment.id,
  columns: columns,
  controller: controller,
  selectable: true,
)
''';

const _rtlCode = '''
Directionality(
  textDirection: TextDirection.rtl,
  child: DDataTable<Payment>(
    data: payments,
    columns: arabicColumns,
    rowId: (payment) => payment.id,
  ),
)
''';

class _VirtualDirectoryExample extends StatefulWidget {
  const _VirtualDirectoryExample();
  @override
  State<_VirtualDirectoryExample> createState() =>
      _VirtualDirectoryExampleState();
}

class _VirtualDirectoryExampleState extends State<_VirtualDirectoryExample> {
  Map<String, double> _widths = {};
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 320,
    child: DDataTable<int>(
      data: List.generate(1000, (index) => index),
      rowId: (row) => row,
      operationMode: DDataTableOperationMode.manual,
      virtualized: true,
      columnWidths: _widths,
      onColumnWidthsChanged: (widths) => setState(() => _widths = widths),
      columns: [
        DDataTableColumn(
          id: 'user',
          label: 'User',
          resizable: true,
          width: const FixedColumnWidth(240),
          cellBuilder: (context, cell) => Text('Member ${cell.row + 1}'),
        ),
        DDataTableColumn(
          id: 'posts',
          label: 'Posts',
          resizable: true,
          width: const FixedColumnWidth(160),
          cellBuilder: (context, cell) => Text('${cell.row * 7}'),
        ),
      ],
    ),
  );
}

const _virtualCode = r'''SizedBox(
  height: 320,
  child: DDataTable<int>(
    data: List.generate(1000, (index) => index),
    rowId: (row) => row,
    operationMode: DDataTableOperationMode.manual,
    virtualized: true,
    columnWidths: widths,
    onColumnWidthsChanged: (next) => setState(() => widths = next),
    columns: [
      DDataTableColumn(
        id: 'user', label: 'User', resizable: true,
        width: const FixedColumnWidth(240),
        cellBuilder: (context, cell) => Text('Member ${cell.row + 1}'),
      ),
    ],
  ),
)''';
