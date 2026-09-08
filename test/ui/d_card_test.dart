import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  Widget child, {
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme,
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Directionality(
      textDirection: direction,
      child: Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 384, child: child),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  for (final direction in TextDirection.values) {
    testWidgets(
      'compact action reaches $direction end and title uses remaining width',
      (tester) async {
        await tester.pumpWidget(
          host(
            const DCard(
              children: [
                DCardHeader(
                  title: DCardTitle(
                    child: Text(
                      'A longer title that needs the remaining header width',
                      key: Key('title'),
                    ),
                  ),
                  description: DCardDescription(child: Text('Description')),
                  action: DCardAction(
                    child: SizedBox(key: Key('action'), width: 32, height: 20),
                  ),
                ),
              ],
            ),
            direction: direction,
          ),
        );
        final action = tester.getRect(find.byKey(const Key('action')));
        final title = tester.getRect(find.byKey(const Key('title')));
        expect(action.top, 16);
        if (direction == TextDirection.ltr) {
          expect(action.right, 368);
          expect(title.left, 16);
          expect(title.width, 316);
        } else {
          expect(action.left, 16);
          expect(title.right, 368);
          expect(title.width, 316);
        }
      },
    );
  }

  for (final inset in [12.0, 16.0, 24.0, 32.0]) {
    testWidgets(
      'shared $inset spacing reaches parts and footer has no extra bottom',
      (tester) async {
        for (final slot in [true, false]) {
          const footer = DCardFooter(
            child: SizedBox(key: Key('footer'), height: 10),
          );
          await tester.pumpWidget(
            host(
              DCard(
                spacing: inset,
                footer: slot ? footer : null,
                children: [
                  const DCardContent(
                    child: SizedBox(key: Key('content'), height: 10),
                  ),
                  if (!slot) footer,
                ],
              ),
            ),
          );
          final content = tester.getRect(find.byKey(const Key('content')));
          final foot = tester.getRect(find.byKey(const Key('footer')));
          final card = tester.getRect(find.byType(DCard));
          expect(content.left, inset);
          expect(content.top, inset);
          expect(foot.top, inset + 10 + inset + 1 + inset);
          expect(card.bottom - foot.bottom, inset);
        }
      },
    );
  }

  testWidgets('small title metrics, image edges and joined content', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const DCard(
          size: DCardSize.small,
          leading: SizedBox(key: Key('image'), height: 90),
          footer: DCardFooter(child: Text('Footer')),
          children: [
            DCardHeader(
              title: DCardTitle(child: Text('Small', key: Key('title'))),
            ),
            DCardContent(
              edgeToEdge: true,
              joinNext: true,
              child: SizedBox(key: Key('content'), height: 20),
            ),
          ],
        ),
      ),
    );
    expect(tester.getTopLeft(find.byKey(const Key('image'))), Offset.zero);
    expect(tester.getSize(find.byKey(const Key('image'))).width, 384);
    final text = tester.element(find.byKey(const Key('title')));
    final style = DefaultTextStyle.of(text).style;
    expect(style.fontSize, 14);
    expect(style.height, 1.375);
    expect(style.fontWeight, FontWeight.w500);
    expect(
      tester.getTopLeft(find.byType(DCardFooter)).dy,
      tester.getBottomLeft(find.byKey(const Key('content'))).dy,
    );
    expect(tester.getSize(find.byKey(const Key('content'))).width, 384);
  });

  testWidgets(
    'palette spacing and direction changes retain editing focus and callbacks',
    (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      int count = 0;
      Widget card() => DCard(
        children: [
          DCardContent(
            child: Column(
              children: [
                TextField(controller: controller, focusNode: focus),
                DButton(
                  onPressed: () => count++,
                  label: const Text('Activate'),
                ),
              ],
            ),
          ),
        ],
      );
      await tester.pumpWidget(host(card()));
      await tester.enterText(find.byType(TextField), 'Retained draft');
      focus.requestFocus();
      await tester.pump();
      await tester.pumpWidget(
        host(card(), direction: TextDirection.rtl, theme: ThemeData.dark()),
      );
      await tester.pumpAndSettle();
      expect(controller.text, 'Retained draft');
      expect(focus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(count, 1);
      final material = tester.widget<Material>(
        find
            .descendant(of: find.byType(DCard), matching: find.byType(Material))
            .first,
      );
      expect(material.color, DTokens.fromTheme(ThemeData.dark()).surface);
      await tester.pumpWidget(const SizedBox());
      expect(focus.hasFocus, isFalse);
      controller.text = 'Still caller owned';
    },
  );

  testWidgets('header action retains element and focus when reflowing', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    Widget card() => DCard(
      children: [
        DCardHeader(
          title: const DCardTitle(child: Text('A responsive header')),
          action: DCardAction(
            child: SizedBox(width: 100, child: TextField(focusNode: focus)),
          ),
        ),
      ],
    );
    await tester.pumpWidget(host(card()));
    await tester.enterText(find.byType(TextField), 'Draft');
    final element = tester.element(find.byType(TextField));
    await tester.pumpWidget(
      host(card(), scale: 2, direction: TextDirection.rtl),
    );
    await tester.pump();
    expect(tester.element(find.byType(TextField)), same(element));
    expect(find.text('Draft'), findsOneWidget);
    expect(focus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'narrow 200 percent RTL wraps action and passive card has no action semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 180,
            child: DCard(
              children: [
                DCardHeader(
                  title: DCardTitle(
                    child: Text('A title that wraps at large text'),
                  ),
                  action: DCardAction(child: Text('Action')),
                ),
                DCardContent(child: Text('Content')),
              ],
            ),
          ),
          direction: TextDirection.rtl,
          scale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.text('Action')).dy,
        greaterThan(
          tester
              .getBottomLeft(find.text('A title that wraps at large text'))
              .dy,
        ),
      );
      expect(
        tester
            .getSemantics(find.byType(DCard))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
      semantics.dispose();
    },
  );
}
