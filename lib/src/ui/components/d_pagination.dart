import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'd_button.dart';

/// Owns one-based page, page-count, and page-size state for [DPaginationNavigation].
///
/// Empty data keeps [page] at one while [hasPages] is false. Changing page size
/// preserves the first visible item by default. Callers own loading, server
/// requests, caches, and URL synchronization.
class DPaginationController extends ChangeNotifier {
  DPaginationController({int page = 1, int pageCount = 1, int pageSize = 25})
    : assert(page >= 1),
      assert(pageCount >= 0),
      assert(pageSize > 0),
      _pageCount = pageCount,
      _pageSize = pageSize,
      _page = _clampPage(page, pageCount);

  int _page;
  int _pageCount;
  int _pageSize;

  int get page => _page;
  int get pageCount => _pageCount;
  int get pageSize => _pageSize;
  bool get hasPages => _pageCount > 0;
  bool get canGoBack => hasPages && _page > 1;
  bool get canGoForward => hasPages && _page < _pageCount;

  static int pageCountFor({required int totalItems, required int pageSize}) {
    assert(totalItems >= 0);
    assert(pageSize > 0);
    return (totalItems / pageSize).ceil();
  }

  bool goToPage(int value) {
    if (!hasPages) return false;
    final next = _clampPage(value, _pageCount);
    if (next == _page) return false;
    _page = next;
    notifyListeners();
    return true;
  }

  bool first() => goToPage(1);
  bool previous() => goToPage(_page - 1);
  bool next() => goToPage(_page + 1);
  bool last() => goToPage(_pageCount);

  /// Updates the bounded paging model and emits at most one notification.
  ///
  /// When [pageSize] changes, [preserveFirstItem] keeps the old first visible
  /// item on screen. Passing [page] overrides that derived page.
  void update({
    int? page,
    int? pageCount,
    int? pageSize,
    bool preserveFirstItem = true,
  }) {
    assert(page == null || page >= 1);
    assert(pageCount == null || pageCount >= 0);
    assert(pageSize == null || pageSize > 0);
    final oldPage = _page;
    final oldPageCount = _pageCount;
    final oldPageSize = _pageSize;
    final nextPageCount = pageCount ?? oldPageCount;
    final nextPageSize = pageSize ?? oldPageSize;
    final firstItem = (oldPage - 1) * oldPageSize;
    final requestedPage =
        page ??
        (pageSize != null && preserveFirstItem
            ? firstItem ~/ nextPageSize + 1
            : oldPage);

    _pageCount = nextPageCount;
    _pageSize = nextPageSize;
    _page = _clampPage(requestedPage, nextPageCount);
    if (_page != oldPage ||
        _pageCount != oldPageCount ||
        _pageSize != oldPageSize) {
      notifyListeners();
    }
  }

  void updateTotalItems(
    int totalItems, {
    int? pageSize,
    bool preserveFirstItem = true,
  }) {
    assert(totalItems >= 0);
    final nextPageSize = pageSize ?? _pageSize;
    update(
      pageCount: pageCountFor(totalItems: totalItems, pageSize: nextPageSize),
      pageSize: nextPageSize,
      preserveFirstItem: preserveFirstItem,
    );
  }

  static int _clampPage(int page, int pageCount) =>
      page.clamp(1, math.max(1, pageCount));
}

/// The navigation landmark and alignment owner for explicit pagination parts.
class DPagination extends StatelessWidget {
  const DPagination({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
    this.semanticLabel = 'Pagination',
    this.semanticValue,
  });

  final Widget child;
  final AlignmentGeometry alignment;
  final String semanticLabel;
  final String? semanticValue;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: semanticLabel,
    value: semanticValue,
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: constraints.hasBoundedWidth ? constraints.maxWidth : 0,
          ),
          child: Align(alignment: alignment, heightFactor: 1, child: child),
        ),
      ),
    ),
  );
}

/// The compact horizontal list used by the reference composition.
class DPaginationContent extends StatelessWidget {
  const DPaginationContent({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var index = 0; index < children.length; index++) ...[
        if (index > 0) const SizedBox(width: 2),
        children[index],
      ],
    ],
  );
}

/// A semantic grouping hook matching the reference list-item anatomy.
class DPaginationItem extends StatelessWidget {
  const DPaginationItem({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// A page link. Routing remains application-owned through [onPressed].
class DPaginationLink extends StatelessWidget {
  const DPaginationLink({
    super.key,
    required this.page,
    required this.onPressed,
    this.isCurrent = false,
    this.label,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
  }) : assert(page >= 1);

  final int page;
  final VoidCallback? onPressed;
  final bool isCurrent;
  final Widget? label;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: isCurrent,
    child: SizedBox.square(
      dimension: 32,
      child: DButton(
        label: label ?? Text('$page'),
        onPressed: onPressed,
        variant: isCurrent ? DButtonVariant.outline : DButtonVariant.ghost,
        size: DButtonSize.regular,
        isLink: true,
        semanticLabel:
            semanticLabel ??
            (isCurrent ? 'Page $page, current page' : 'Go to page $page'),
        focusNode: focusNode,
        autofocus: autofocus,
        padding: EdgeInsets.zero,
      ),
    ),
  );
}

class DPaginationPrevious extends StatelessWidget {
  const DPaginationPrevious({
    super.key,
    required this.onPressed,
    this.text = 'Previous',
    this.semanticLabel = 'Go to previous page',
    this.showText,
    this.variant = DButtonVariant.ghost,
    this.focusNode,
  });

  final VoidCallback? onPressed;
  final String text;
  final String semanticLabel;
  final bool? showText;
  final DButtonVariant variant;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => _PaginationDirectionAction(
    onPressed: onPressed,
    text: text,
    semanticLabel: semanticLabel,
    showText: showText,
    forward: false,
    variant: variant,
    focusNode: focusNode,
  );
}

class DPaginationNext extends StatelessWidget {
  const DPaginationNext({
    super.key,
    required this.onPressed,
    this.text = 'Next',
    this.semanticLabel = 'Go to next page',
    this.showText,
    this.variant = DButtonVariant.ghost,
    this.focusNode,
  });

  final VoidCallback? onPressed;
  final String text;
  final String semanticLabel;
  final bool? showText;
  final DButtonVariant variant;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => _PaginationDirectionAction(
    onPressed: onPressed,
    text: text,
    semanticLabel: semanticLabel,
    showText: showText,
    forward: true,
    variant: variant,
    focusNode: focusNode,
  );
}

class DPaginationFirst extends StatelessWidget {
  const DPaginationFirst({
    super.key,
    required this.onPressed,
    this.semanticLabel = 'Go to first page',
    this.variant = DButtonVariant.ghost,
    this.focusNode,
  });

  final VoidCallback? onPressed;
  final String semanticLabel;
  final DButtonVariant variant;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => DButton.iconOnly(
    icon: const _PaginationChevron(doubleArrow: true, forward: false),
    tooltip: semanticLabel,
    semanticLabel: semanticLabel,
    onPressed: onPressed,
    variant: variant,
    size: DButtonSize.regular,
    focusNode: focusNode,
  );
}

class DPaginationLast extends StatelessWidget {
  const DPaginationLast({
    super.key,
    required this.onPressed,
    this.semanticLabel = 'Go to last page',
    this.variant = DButtonVariant.ghost,
    this.focusNode,
  });

  final VoidCallback? onPressed;
  final String semanticLabel;
  final DButtonVariant variant;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => DButton.iconOnly(
    icon: const _PaginationChevron(doubleArrow: true, forward: true),
    tooltip: semanticLabel,
    semanticLabel: semanticLabel,
    onPressed: onPressed,
    variant: variant,
    size: DButtonSize.regular,
    focusNode: focusNode,
  );
}

/// The 32px, non-interactive omitted-pages marker.
class DPaginationEllipsis extends StatelessWidget {
  const DPaginationEllipsis({
    super.key,
    this.semanticLabel = 'More pages',
    this.excludeFromSemantics = true,
  });

  final String semanticLabel;
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) {
    final child = SizedBox.square(
      dimension: 32,
      child: Center(
        child: ExcludeSemantics(
          child: CustomPaint(
            size: const Size.square(16),
            painter: _DotsPainter(color: IconTheme.of(context).color),
          ),
        ),
      ),
    );
    return excludeFromSemantics
        ? ExcludeSemantics(child: child)
        : Semantics(label: semanticLabel, child: child);
  }
}

enum _PaginationOwnership { local, controlled, controller }

/// Builds complete bounded navigation with local, controlled, or controller state.
class DPaginationNavigation extends StatefulWidget {
  const DPaginationNavigation.local({
    super.key,
    this.initialPage = 1,
    required this.pageCount,
    this.initialPageSize = 25,
    this.onPageChanged,
    this.showPageNumbers = true,
    this.showFirstLast = false,
    this.siblingCount = 1,
    this.boundaryCount = 1,
    this.alignment = Alignment.center,
    this.semanticLabel = 'Pagination',
    this.previousText = 'Previous',
    this.nextText = 'Next',
    this.showDirectionText,
    this.directionVariant = DButtonVariant.ghost,
    this.enabled = true,
  }) : assert(initialPage >= 1),
       assert(pageCount >= 0),
       assert(initialPageSize > 0),
       assert(siblingCount >= 0),
       assert(boundaryCount >= 0),
       page = null,
       pageSize = null,
       controller = null,
       _ownership = _PaginationOwnership.local;

  const DPaginationNavigation.controlled({
    super.key,
    required int page,
    required this.pageCount,
    int pageSize = 25,
    required this.onPageChanged,
    this.showPageNumbers = true,
    this.showFirstLast = false,
    this.siblingCount = 1,
    this.boundaryCount = 1,
    this.alignment = Alignment.center,
    this.semanticLabel = 'Pagination',
    this.previousText = 'Previous',
    this.nextText = 'Next',
    this.showDirectionText,
    this.directionVariant = DButtonVariant.ghost,
    this.enabled = true,
  }) : assert(page >= 1),
       assert(pageCount >= 0),
       assert(pageSize > 0),
       assert(siblingCount >= 0),
       assert(boundaryCount >= 0),
       initialPage = 1,
       initialPageSize = 25,
       page = page,
       pageSize = pageSize,
       controller = null,
       _ownership = _PaginationOwnership.controlled;

  const DPaginationNavigation.controller({
    super.key,
    required this.controller,
    this.onPageChanged,
    this.showPageNumbers = true,
    this.showFirstLast = false,
    this.siblingCount = 1,
    this.boundaryCount = 1,
    this.alignment = Alignment.center,
    this.semanticLabel = 'Pagination',
    this.previousText = 'Previous',
    this.nextText = 'Next',
    this.showDirectionText,
    this.directionVariant = DButtonVariant.ghost,
    this.enabled = true,
  }) : assert(siblingCount >= 0),
       assert(boundaryCount >= 0),
       initialPage = 1,
       initialPageSize = 25,
       page = null,
       pageCount = 0,
       pageSize = null,
       _ownership = _PaginationOwnership.controller;

  final int initialPage;
  final int initialPageSize;
  final int? page;
  final int pageCount;
  final int? pageSize;
  final DPaginationController? controller;
  final ValueChanged<int>? onPageChanged;
  final bool showPageNumbers;
  final bool showFirstLast;
  final int siblingCount;
  final int boundaryCount;
  final AlignmentGeometry alignment;
  final String semanticLabel;
  final String previousText;
  final String nextText;
  final bool? showDirectionText;
  final DButtonVariant directionVariant;
  final bool enabled;
  final _PaginationOwnership _ownership;

  @override
  State<DPaginationNavigation> createState() => _DPaginationNavigationState();
}

class _DPaginationNavigationState extends State<DPaginationNavigation> {
  DPaginationController? _ownedController;

  @override
  void initState() {
    super.initState();
    _createOwnedController();
  }

  @override
  void didUpdateWidget(DPaginationNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget._ownership != oldWidget._ownership) {
      _ownedController?.dispose();
      _ownedController = null;
      _createOwnedController();
    } else if (widget._ownership == _PaginationOwnership.local) {
      _ownedController!.update(
        pageCount: widget.pageCount,
        pageSize: widget.initialPageSize,
      );
    }
  }

  void _createOwnedController() {
    if (widget._ownership == _PaginationOwnership.local) {
      _ownedController = DPaginationController(
        page: widget.initialPage,
        pageCount: widget.pageCount,
        pageSize: widget.initialPageSize,
      );
    }
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listenable = switch (widget._ownership) {
      _PaginationOwnership.local => _ownedController!,
      _PaginationOwnership.controller => widget.controller!,
      _PaginationOwnership.controlled => null,
    };
    if (listenable == null) return _buildNavigation(context);
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => _buildNavigation(context),
    );
  }

  Widget _buildNavigation(BuildContext context) {
    final controller = switch (widget._ownership) {
      _PaginationOwnership.local => _ownedController,
      _PaginationOwnership.controller => widget.controller,
      _PaginationOwnership.controlled => null,
    };
    final pageCount = controller?.pageCount ?? widget.pageCount;
    final pageSize =
        controller?.pageSize ?? widget.pageSize ?? widget.initialPageSize;
    final page = DPaginationController._clampPage(
      controller?.page ?? widget.page!,
      pageCount,
    );
    final hasPages = pageCount > 0;
    final canActivate =
        widget.enabled &&
        (widget._ownership != _PaginationOwnership.controlled ||
            widget.onPageChanged != null);

    void changePage(int next) {
      if (!canActivate || !hasPages) return;
      final normalized = DPaginationController._clampPage(next, pageCount);
      final changed = controller?.goToPage(normalized) ?? normalized != page;
      if (changed) widget.onPageChanged?.call(normalized);
    }

    final children = <Widget>[];
    if (widget.showFirstLast) {
      children.add(
        DPaginationItem(
          child: DPaginationFirst(
            variant: widget.directionVariant,
            onPressed: canActivate && page > 1 ? () => changePage(1) : null,
          ),
        ),
      );
    }
    children.add(
      DPaginationItem(
        child: DPaginationPrevious(
          text: widget.previousText,
          showText: widget.showDirectionText,
          variant: widget.directionVariant,
          onPressed: canActivate && page > 1
              ? () => changePage(page - 1)
              : null,
        ),
      ),
    );
    if (widget.showPageNumbers && hasPages) {
      for (final entry in _pageEntries(
        page: page,
        pageCount: pageCount,
        siblingCount: widget.siblingCount,
        boundaryCount: widget.boundaryCount,
      )) {
        children.add(
          DPaginationItem(
            child: entry == null
                ? const DPaginationEllipsis()
                : DPaginationLink(
                    page: entry,
                    isCurrent: entry == page,
                    onPressed: canActivate ? () => changePage(entry) : null,
                  ),
          ),
        );
      }
    }
    children.add(
      DPaginationItem(
        child: DPaginationNext(
          text: widget.nextText,
          showText: widget.showDirectionText,
          variant: widget.directionVariant,
          onPressed: canActivate && page < pageCount
              ? () => changePage(page + 1)
              : null,
        ),
      ),
    );
    if (widget.showFirstLast) {
      children.add(
        DPaginationItem(
          child: DPaginationLast(
            variant: widget.directionVariant,
            onPressed: canActivate && page < pageCount
                ? () => changePage(pageCount)
                : null,
          ),
        ),
      );
    }

    return DPagination(
      alignment: widget.alignment,
      semanticLabel: widget.semanticLabel,
      semanticValue: pageCount == 0
          ? 'No pages, $pageSize items per page'
          : 'Page $page of $pageCount, $pageSize items per page',
      child: DPaginationContent(children: children),
    );
  }
}

class _PaginationDirectionAction extends StatelessWidget {
  const _PaginationDirectionAction({
    required this.onPressed,
    required this.text,
    required this.semanticLabel,
    required this.showText,
    required this.forward,
    required this.variant,
    required this.focusNode,
  });

  final VoidCallback? onPressed;
  final String text;
  final String semanticLabel;
  final bool? showText;
  final bool forward;
  final DButtonVariant variant;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final includeText = showText ?? MediaQuery.sizeOf(context).width >= 640;
    if (!includeText) {
      return DButton.iconOnly(
        icon: _PaginationChevron(forward: forward),
        tooltip: semanticLabel,
        semanticLabel: semanticLabel,
        onPressed: onPressed,
        variant: variant,
        size: DButtonSize.regular,
        focusNode: focusNode,
      );
    }
    return DButton(
      label: Text(text),
      onPressed: onPressed,
      icon: _PaginationChevron(forward: forward),
      iconPosition: forward
          ? DButtonIconPosition.end
          : DButtonIconPosition.start,
      variant: variant,
      size: DButtonSize.regular,
      isLink: true,
      semanticLabel: semanticLabel,
      focusNode: focusNode,
      padding: EdgeInsetsDirectional.only(
        start: forward ? 11 : 6,
        end: forward ? 6 : 11,
        top: 1,
        bottom: 1,
      ),
    );
  }
}

class _PaginationChevron extends StatelessWidget {
  const _PaginationChevron({required this.forward, this.doubleArrow = false});

  final bool forward;
  final bool doubleArrow;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(16),
    painter: _ChevronPainter(
      color: IconTheme.of(context).color,
      forward: forward,
      doubleArrow: doubleArrow,
      textDirection: Directionality.of(context),
    ),
  );
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({
    required this.color,
    required this.forward,
    required this.doubleArrow,
    required this.textDirection,
  });

  final Color? color;
  final bool forward;
  final bool doubleArrow;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final pointsForward = forward == (textDirection == TextDirection.ltr);
    final paint = Paint()
      ..color = color ?? const Color(0xFF000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    void addChevron(double centerX) {
      final outsideX = pointsForward ? centerX - 2.5 : centerX + 2.5;
      final pointX = pointsForward ? centerX + 1.5 : centerX - 1.5;
      path.moveTo(outsideX, 3.5);
      path.lineTo(pointX, 8);
      path.lineTo(outsideX, 12.5);
    }

    if (doubleArrow) {
      addChevron(6);
      addChevron(10);
    } else {
      addChevron(8);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      color != oldDelegate.color ||
      forward != oldDelegate.forward ||
      doubleArrow != oldDelegate.doubleArrow ||
      textDirection != oldDelegate.textDirection;
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter({required this.color});

  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color ?? const Color(0xFF000000);
    for (final x in const [3.5, 8.0, 12.5]) {
      canvas.drawCircle(Offset(x, 8), 1, paint);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => color != oldDelegate.color;
}

List<int?> _pageEntries({
  required int page,
  required int pageCount,
  required int siblingCount,
  required int boundaryCount,
}) {
  if (pageCount <= 0) return const [];
  final visible = <int>{};
  for (var value = 1; value <= math.min(boundaryCount, pageCount); value++) {
    visible.add(value);
  }
  for (
    var value = math.max(1, pageCount - boundaryCount + 1);
    value <= pageCount;
    value++
  ) {
    visible.add(value);
  }
  for (
    var value = math.max(1, page - siblingCount);
    value <= math.min(pageCount, page + siblingCount);
    value++
  ) {
    visible.add(value);
  }
  if (visible.isEmpty) visible.add(page);
  final sorted = visible.toList()..sort();
  final result = <int?>[];
  for (var index = 0; index < sorted.length; index++) {
    if (index > 0) {
      final gap = sorted[index] - sorted[index - 1];
      if (gap == 2) {
        result.add(sorted[index - 1] + 1);
      } else if (gap > 2) {
        result.add(null);
      }
    }
    result.add(sorted[index]);
  }
  return result;
}
