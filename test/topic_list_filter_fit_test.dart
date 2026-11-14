import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' as fixture;

Finder _filters() => find.byKey(const ValueKey('topic-list-filter'));

void main() {
  Future<void> pumpList(WidgetTester tester, double width, String query) async {
    final shell = await fixture.pumpMobileShellFixture(
      tester,
      size: Size(width, 844),
    );
    await tester.pumpAndSettle();
    if (query.isNotEmpty) {
      await shell.applyTopicListFilterQuery(query);
      await tester.pumpAndSettle();
    }
  }

  for (final query in ['status:open', '']) {
    testWidgets('advanced filters are available through Search for $query', (
      tester,
    ) async {
      await pumpList(tester, 360, query);
      expect(_filters(), findsNothing);
      final search = find.byKey(const ValueKey('mobile-search-button'));
      final badge = find.byKey(const ValueKey('mobile-search-filter-count'));
      expect(badge, query.isEmpty ? findsNothing : findsOneWidget);
      await tester.tap(search);
      await tester.pumpAndSettle();
      final filters = find.byKey(const ValueKey('search-filters-button'));
      expect(filters.hitTestable(), findsOneWidget);
      await tester.tap(filters);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topic-filter-input')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('crowded filters shorten before taking a third line', (
    tester,
  ) async {
    await pumpList(tester, 360, 'status:open');
    expect(_filters(), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('topic-list-filter-bar')))
          .height,
      lessThanOrEqualTo(80),
    );
    expect(tester.takeException(), isNull);
  });
}
