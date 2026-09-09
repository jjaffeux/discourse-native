import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final paginationExamples = ComponentExamples(
  status: ComponentStatus.baseline,
  description:
      'Bounded page navigation with numbered, compact, and linked compositions.',
  notes:
      'Pages are one-based. DPaginationNavigation supports local, controlled, '
      'or borrowed DPaginationController ownership; the controller also owns '
      'page size and clamps safely as totals change. Below 640px, Previous/Next '
      'text hides like the reference sm breakpoint while spoken labels remain. '
      'Server paging, loading, query strings, and caches stay in adapters. '
      'Cursor and infinite-scroll feeds are intentionally unchanged. The final '
      'Field/Select composition remains baseline until Select and Pagination '
      'pass independent rendered/native review.',
  examples: [
    StyleguideExample(
      title: 'Default',
      description: 'Previous, page links, omitted pages, and Next.',
      states: const ['Controlled', 'Current page', 'Ellipsis'],
      code: '''DPaginationNavigation.controlled(
  page: page, pageCount: 10,
  onPageChanged: (next) => setState(() => page = next),
)''',
      builder: (_) => const _ControlledExample(),
    ),
    StyleguideExample(
      title: 'Simple',
      description: 'Five page links without directional controls.',
      states: const ['Explicit composition', 'Page links'],
      code: '''DPagination(
  child: DPaginationContent(children: [
    DPaginationLink(page: 1, onPressed: openPage),
    DPaginationLink(page: 2, isCurrent: true, onPressed: openPage),
    // Pages 3–5…
  ]),
)''',
      builder: (_) => const _SimpleExample(),
    ),
    StyleguideExample(
      title: 'Icons Only',
      description:
          'Rows-per-page Field/Select composition with compact directional navigation.',
      states: const ['Field', 'Select', 'Page size', 'Icons only'],
      code: '''DField(
  orientation: DFieldOrientation.horizontal,
  children: [
    const DFieldLabel(child: Text('Rows per page')),
    DSelect<int>(
      entries: const [
        DSelectOption(value: 10, label: '10'),
        DSelectOption(value: 25, label: '25'),
        DSelectOption(value: 50, label: '50'),
        DSelectOption(value: 100, label: '100'),
      ],
      initialValue: 25, size: DSelectSize.small, width: 80,
      onChanged: updatePageSize,
    ),
  ],
)
DPaginationNavigation.controller(
  controller: controller, showPageNumbers: false,
)''',
      builder: (_) => const _PageSizeExample(),
    ),
    StyleguideExample(
      title: 'Routing links',
      description:
          'Caller-owned route/query synchronization through native link semantics.',
      states: const ['Link semantics', 'Caller-owned routing'],
      code: '''DPaginationLink(
  page: page,
  isCurrent: page == currentPage,
  onPressed: () => openRoute('/topics?page=\$page'),
)''',
      builder: (_) => const _RoutingExample(),
    ),
    StyleguideExample(
      title: 'Controller and changing totals',
      description:
          'First/last, clamping, page-size preservation, single-page, and empty states.',
      states: const ['Controller', 'First/last', 'Dynamic count', 'Empty'],
      code: '''final controller = DPaginationController(
  page: 8, pageCount: 10, pageSize: 25);
controller.updateTotalItems(63); // clamps to page 3
controller.update(pageSize: 50); // preserves first visible item''',
      builder: (_) => const _DynamicExample(),
    ),
    StyleguideExample(
      title: 'RTL',
      description: 'Arabic labels and numerals with logical icon direction.',
      states: const ['RTL', 'Localized labels', 'Logical icons'],
      code: '''Directionality(
  textDirection: TextDirection.rtl,
  child: DPagination(
    child: DPaginationContent(children: [
      DPaginationPrevious(text: 'السابق', onPressed: previous),
      // Arabic page labels…
      DPaginationNext(text: 'التالي', onPressed: next),
    ]),
  ),
)''',
      builder: (_) => const _RtlExample(),
    ),
  ],
);

class _ControlledExample extends StatefulWidget {
  const _ControlledExample();
  @override
  State<_ControlledExample> createState() => _ControlledExampleState();
}

class _ControlledExampleState extends State<_ControlledExample> {
  int page = 2;
  @override
  Widget build(BuildContext context) => DPaginationNavigation.controlled(
    page: page,
    pageCount: 10,
    onPageChanged: (next) => setState(() => page = next),
  );
}

class _SimpleExample extends StatefulWidget {
  const _SimpleExample();
  @override
  State<_SimpleExample> createState() => _SimpleExampleState();
}

class _SimpleExampleState extends State<_SimpleExample> {
  int page = 2;
  @override
  Widget build(BuildContext context) => DPagination(
    child: DPaginationContent(
      children: [
        for (var value = 1; value <= 5; value++)
          DPaginationItem(
            child: DPaginationLink(
              page: value,
              isCurrent: page == value,
              onPressed: () => setState(() => page = value),
            ),
          ),
      ],
    ),
  );
}

class _PageSizeExample extends StatefulWidget {
  const _PageSizeExample();
  @override
  State<_PageSizeExample> createState() => _PageSizeExampleState();
}

class _PageSizeExampleState extends State<_PageSizeExample> {
  late final DPaginationController controller = DPaginationController(
    pageCount: 8,
    pageSize: 25,
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    alignment: WrapAlignment.spaceBetween,
    children: [
      DField(
        orientation: DFieldOrientation.horizontal,
        children: [
          const DFieldLabel(child: Text('Rows per page')),
          DSelect<int>(
            entries: const [
              DSelectOption(value: 10, label: '10', child: Text('10')),
              DSelectOption(value: 25, label: '25', child: Text('25')),
              DSelectOption(value: 50, label: '50', child: Text('50')),
              DSelectOption(value: 100, label: '100', child: Text('100')),
            ],
            initialValue: 25,
            size: DSelectSize.small,
            width: 80,
            semanticLabel: 'Rows per page',
            onChanged: (value) {
              if (value != null) controller.update(pageSize: value);
            },
          ),
        ],
      ),
      DPaginationNavigation.controller(
        controller: controller,
        showPageNumbers: false,
      ),
    ],
  );
}

class _RoutingExample extends StatefulWidget {
  const _RoutingExample();
  @override
  State<_RoutingExample> createState() => _RoutingExampleState();
}

class _RoutingExampleState extends State<_RoutingExample> {
  int page = 2;
  String route = '/topics?page=2';

  void open(int value) => setState(() {
    page = value;
    route = '/topics?page=$value';
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DPagination(
        child: DPaginationContent(
          children: [
            for (var value = 1; value <= 3; value++)
              DPaginationLink(
                page: value,
                isCurrent: page == value,
                onPressed: () => open(value),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text(route, textAlign: TextAlign.center),
    ],
  );
}

class _DynamicExample extends StatefulWidget {
  const _DynamicExample();
  @override
  State<_DynamicExample> createState() => _DynamicExampleState();
}

class _DynamicExampleState extends State<_DynamicExample> {
  late final DPaginationController controller = DPaginationController(
    page: 8,
    pageCount: 10,
    pageSize: 25,
  );
  int totalItems = 250;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void setTotal(int value) {
    totalItems = value;
    controller.updateTotalItems(value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DPaginationNavigation.controller(
        controller: controller,
        showFirstLast: true,
      ),
      const SizedBox(height: 12),
      ListenableBuilder(
        listenable: controller,
        builder: (_, _) => Text(
          '$totalItems items · page ${controller.page} of ${controller.pageCount}',
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final value in const [250, 63, 1, 0])
            DButton(
              label: Text(value == 0 ? 'Empty' : '$value items'),
              variant: DButtonVariant.outline,
              onPressed: () => setTotal(value),
            ),
        ],
      ),
    ],
  );
}

class _RtlExample extends StatefulWidget {
  const _RtlExample();
  @override
  State<_RtlExample> createState() => _RtlExampleState();
}

class _RtlExampleState extends State<_RtlExample> {
  int page = 2;
  static const numerals = ['٠', '١', '٢', '٣'];

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: DPagination(
      semanticLabel: 'ترقيم الصفحات',
      child: DPaginationContent(
        children: [
          DPaginationPrevious(
            text: 'السابق',
            semanticLabel: 'انتقل إلى الصفحة السابقة',
            onPressed: page > 1 ? () => setState(() => page--) : null,
          ),
          for (var value = 1; value <= 3; value++)
            DPaginationLink(
              page: value,
              label: Text(numerals[value]),
              isCurrent: page == value,
              semanticLabel: page == value
                  ? 'الصفحة ${numerals[value]}، الصفحة الحالية'
                  : 'انتقل إلى الصفحة ${numerals[value]}',
              onPressed: () => setState(() => page = value),
            ),
          const DPaginationEllipsis(),
          DPaginationNext(
            text: 'التالي',
            semanticLabel: 'انتقل إلى الصفحة التالية',
            onPressed: page < 3 ? () => setState(() => page++) : null,
          ),
        ],
      ),
    ),
  );
}
