import 'dart:ui' show SemanticsRole;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/pagination_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'controller clamps pages and preserves the first item on size changes',
    () {
      final controller = DPaginationController(
        page: 8,
        pageCount: 10,
        pageSize: 25,
      );
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.updateTotalItems(63);
      expect((controller.page, controller.pageCount), (3, 3));
      controller.update(pageSize: 50);
      expect((controller.page, controller.pageSize), (2, 50));
      controller.updateTotalItems(0);
      expect(
        (controller.page, controller.pageCount, controller.hasPages),
        (1, 0, false),
      );
      expect(controller.next(), isFalse);
      controller.updateTotalItems(1);
      expect((controller.page, controller.pageCount), (1, 1));
      expect(notifications, 4);
    },
  );

  test('pageCountFor handles exact, partial, and empty pages', () {
    expect(DPaginationController.pageCountFor(totalItems: 0, pageSize: 25), 0);
    expect(DPaginationController.pageCountFor(totalItems: 50, pageSize: 25), 2);
    expect(DPaginationController.pageCountFor(totalItems: 51, pageSize: 25), 3);
  });

  testWidgets(
    'controlled navigation exposes boundaries and current semantics',
    (tester) async {
      var page = 50;
      await _mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) => DPaginationNavigation.controlled(
            page: page,
            pageCount: 100,
            showFirstLast: true,
            onPageChanged: (value) => setState(() => page = value),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Go to page 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Go to page 49'), findsOneWidget);
      expect(find.bySemanticsLabel('Page 50, current page'), findsOneWidget);
      expect(find.bySemanticsLabel('Go to page 51'), findsOneWidget);
      expect(find.bySemanticsLabel('Go to page 100'), findsOneWidget);
      expect(find.byType(DPaginationEllipsis), findsNWidgets(2));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Pagination')).value,
        'Page 50 of 100, 25 items per page',
      );
      expect(
        tester.getSemantics(find.byType(DPagination)).getSemanticsData().role,
        SemanticsRole.navigation,
      );
      expect(
        tester
            .getSemantics(find.byType(DPaginationContent))
            .getSemanticsData()
            .role,
        SemanticsRole.list,
      );
      expect(
        tester
            .getSemantics(find.byType(DPaginationItem).first)
            .getSemanticsData()
            .role,
        SemanticsRole.listItem,
      );
      final firstPageSurface = find.descendant(
        of: find.byType(DPaginationLink).first,
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      expect(tester.getSize(firstPageSurface), const Size.square(48));
      expect(
        tester
            .getSize(
              find.descendant(
                of: firstPageSurface,
                matching: find.byType(Material),
              ),
            )
            .height,
        DControlStyle.regularHeight,
      );

      await tester.tap(find.bySemanticsLabel('Go to last page'));
      await tester.pump();
      expect(page, 100);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Go to next page')),
        isSemantics(
          label: 'Go to next page',
          isLink: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
    },
  );

  testWidgets('keyboard activates a focused directional link', (tester) async {
    var activations = 0;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await _mount(
      tester,
      DPagination(
        child: DPaginationNext(
          focusNode: focusNode,
          onPressed: () => activations++,
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activations, 1);
  });

  testWidgets('embedded navigation can use outline direction actions', (
    tester,
  ) async {
    await _mount(
      tester,
      const DPaginationNavigation.controlled(
        page: 2,
        pageCount: 3,
        showPageNumbers: false,
        showFirstLast: true,
        directionVariant: DButtonVariant.outline,
        onPageChanged: _ignorePage,
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DButton && widget.variant == DButtonVariant.outline,
      ),
      findsNWidgets(4),
    );
  });

  testWidgets('local state clamps when page count changes', (tester) async {
    var pageCount = 10;
    late StateSetter rebuild;
    await _mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return DPaginationNavigation.local(
            initialPage: 8,
            pageCount: pageCount,
          );
        },
      ),
    );
    expect(find.bySemanticsLabel('Page 8, current page'), findsOneWidget);

    rebuild(() => pageCount = 3);
    await tester.pump();
    expect(find.bySemanticsLabel('Page 3, current page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('borrowed controller is not disposed by navigation', (
    tester,
  ) async {
    final controller = DPaginationController(pageCount: 3);
    addTearDown(controller.dispose);
    await _mount(
      tester,
      DPaginationNavigation.controller(controller: controller),
    );
    await _mount(tester, const SizedBox());

    expect(() => controller.addListener(_noop), returnsNormally);
    controller.removeListener(_noop);
    expect(controller.goToPage(2), isTrue);
  });

  testWidgets('empty and single page states disable movement', (tester) async {
    for (final count in [0, 1]) {
      await _mount(
        tester,
        DPaginationNavigation.controlled(
          page: 1,
          pageCount: count,
          onPageChanged: (_) => fail('disabled navigation activated'),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Go to previous page'));
      await tester.tap(find.bySemanticsLabel('Go to next page'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      if (count == 0) {
        expect(find.byType(DPaginationLink), findsNothing);
      } else {
        expect(find.bySemanticsLabel('Page 1, current page'), findsOneWidget);
      }
    }
  });

  testWidgets('navigation shrink-wraps inside a bounded-height footer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: const Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: Size(240, 568),
              textScaler: TextScaler.linear(2),
            ),
            child: SizedBox(
              width: 240,
              height: 568,
              child: Wrap(
                children: [
                  DPaginationNavigation.controlled(
                    page: 2,
                    pageCount: 8,
                    showPageNumbers: false,
                    onPageChanged: _ignorePage,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(DPagination)), const Size(240, 34));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'explicit parts retain logical order and link activation in RTL',
    (tester) async {
      var page = 0;
      await _mount(
        tester,
        Directionality(
          textDirection: TextDirection.rtl,
          child: DPagination(
            semanticLabel: 'ترقيم الصفحات',
            child: DPaginationContent(
              children: [
                DPaginationPrevious(
                  text: 'السابق',
                  showText: true,
                  onPressed: () => page = 1,
                ),
                DPaginationLink(
                  page: 2,
                  label: const Text('٢'),
                  onPressed: () => page = 2,
                ),
                DPaginationNext(
                  text: 'التالي',
                  showText: true,
                  onPressed: () => page = 3,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Go to page 2'));
      expect(page, 2);
      expect(find.bySemanticsLabel('ترقيم الصفحات'), findsOneWidget);
    },
  );

  testWidgets('all examples mount at narrow 200 percent in live themes', (
    tester,
  ) async {
    expect(componentExamples['pagination'], same(paginationExamples));
    expect(paginationExamples.status, ComponentStatus.implemented);
    expect(paginationExamples.examples.map((example) => example.title), [
      'Default',
      'Simple',
      'Icons Only',
      'Routing links',
      'Controller and changing totals',
      'RTL',
    ]);

    for (final example in paginationExamples.examples) {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(
                  size: Size(216, 640),
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: SizedBox(
                  width: 216,
                  child: SingleChildScrollView(
                    child: Builder(builder: example.builder),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: example.title);
      }
    }
  });
}

Future<void> _mount(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: child)),
  ),
);

void _noop() {}

void _ignorePage(int _) {}
