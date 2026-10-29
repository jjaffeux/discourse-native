import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' as fixture;

Finder _filters() => find.byKey(const ValueKey('topic-list-filter'));

List<String?> _labels(WidgetTester tester) => find
    .descendant(of: _filters(), matching: find.byType(Text))
    .evaluate()
    .map((element) => (element.widget as Text).data)
    .toList();

void main() {
  // The test font draws every glyph a square, so the row's pills are wider
  // than on a phone: at 520 the row holds Latest, Categories and Tags with
  // short Tags and Filters beside them, and at 360 not even that.
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

  double top(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey(key))).top;

  testWidgets('Filters keeps its count beside the other filters for room', (
    tester,
  ) async {
    await pumpList(tester, 520, 'status:open');
    expect(_labels(tester), ['1']);
    expect(
      find.descendant(of: _filters(), matching: find.byType(DIcon)),
      findsOneWidget,
    );
    expect(
      top(tester, 'topic-list-filter'),
      top(tester, 'topic-list-tag-filter'),
    );
    expect(
      tester.getSemantics(_filters()),
      matchesSemantics(
        label: 'Filters · 1',
        isButton: true,
        hasTapAction: true,
        isFocusable: true,
        hasEnabledState: true,
        isEnabled: true,
        hasExpandedState: true,
        hasFocusAction: true,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Filters without a filter set keeps only its glyph for room', (
    tester,
  ) async {
    await pumpList(tester, 520, '');
    expect(_labels(tester), isEmpty);
    expect(
      find.descendant(of: _filters(), matching: find.byType(DIcon)),
      findsOneWidget,
    );
    expect(
      top(tester, 'topic-list-filter'),
      top(tester, 'topic-list-tag-filter'),
    );
    expect(tester.getSemantics(_filters()).label, 'Filters');
    expect(tester.takeException(), isNull);
  });

  testWidgets('crowded filters shorten before taking a third line', (
    tester,
  ) async {
    await pumpList(tester, 360, 'status:open');
    expect(_labels(tester), ['1']);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('topic-list-filter-bar')))
          .height,
      lessThanOrEqualTo(80),
    );
    expect(tester.takeException(), isNull);
  });
}
