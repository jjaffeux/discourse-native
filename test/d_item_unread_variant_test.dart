import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.macOS),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 320, child: child),
    ),
  ),
);

/// The fill the row's own surface is painted in.
Color? _fill(WidgetTester tester, Finder row) => tester
    .widgetList<DecoratedBox>(
      find.descendant(of: row, matching: find.byType(DecoratedBox)),
    )
    .map((box) => box.decoration)
    .whereType<BoxDecoration>()
    .first
    .color;

void main() {
  testWidgets('an unread Item rests in the accent at 9% and gives way to '
      'hover and selection', (tester) async {
    Widget item({bool selected = false}) => _host(
      DItem(
        variant: DItemVariant.unread,
        selected: selected,
        onPressed: () {},
        children: const [
          DItemContent(children: [DItemTitle(child: Text('design'))]),
        ],
      ),
    );
    await tester.pumpWidget(item());
    final tokens = DTokens.of(tester.element(find.byType(DItem)));
    expect(tokens.unreadFill, tokens.primary.withValues(alpha: .09));
    expect(_fill(tester, find.byType(DItem)), tokens.unreadFill);

    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byType(DItem)));
    await tester.pump();
    expect(_fill(tester, find.byType(DItem)), isNot(tokens.unreadFill));
    await mouse.removePointer();
    await tester.pump();
    expect(_fill(tester, find.byType(DItem)), tokens.unreadFill);

    await tester.pumpWidget(item(selected: true));
    expect(_fill(tester, find.byType(DItem)), tokens.selectionTint);
  });

  testWidgets('an unread menu feed row stands in the unread fill and a read '
      'one on nothing', (tester) async {
    Widget row({required bool unread}) => _host(
      DMenuFeedRow(
        title: const Text('Sam replied to'),
        description: const Text('A useful topic'),
        time: '22m',
        unread: unread,
        onPressed: () {},
      ),
    );
    await tester.pumpWidget(row(unread: true));
    final tokens = DTokens.of(tester.element(find.byType(DMenuFeedRow)));
    expect(_fill(tester, find.byType(DMenuFeedRow)), tokens.unreadFill);
    final size = tester.getSize(find.byType(DMenuFeedRow));
    await tester.pumpWidget(row(unread: false));
    expect(_fill(tester, find.byType(DMenuFeedRow)), Colors.transparent);
    expect(
      tester.getSize(find.byType(DMenuFeedRow)),
      size,
      reason: 'The fill takes no room of its own',
    );
  });
}
