import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  Widget child, {
  TargetPlatform platform = TargetPlatform.macOS,
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
  bool reducedMotion = false,
  DTokens? tokens,
}) => MaterialApp(
  theme: ThemeData(platform: platform, extensions: [?tokens]),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reducedMotion,
      ),
      child: Directionality(textDirection: direction, child: child),
    ),
  ),
);

DAccordionItem<String> item(String value, {Widget? content}) =>
    DAccordionItem<String>(
      key: ValueKey('item-$value'),
      value: value,

      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DAccordionHeader(
            child: DAccordionTrigger(
              key: ValueKey('trigger-$value'),

              child: Text('Question $value'),
            ),
          ),
          DAccordionContent(child: content ?? Text('Answer $value')),
        ],
      ),
    );

void main() {
  testWidgets('unkeyed direct items do not receive duplicate wrapper keys', (
    tester,
  ) async {
    DAccordionItem<String> unkeyed(String value) => DAccordionItem<String>(
      value: value,
      child: Column(
        children: [
          DAccordionHeader(
            child: DAccordionTrigger(child: Text('Question $value')),
          ),
          DAccordionContent(child: Text('Answer $value')),
        ],
      ),
    );

    await tester.pumpWidget(
      host(DAccordion<String>(children: [unkeyed('a'), unkeyed('b')])),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Question'), findsNWidgets(2));
  });

  testWidgets('item values must be unique within an accordion', (tester) async {
    final first = item('a');
    await tester.pumpWidget(
      host(
        DAccordion<String>(
          children: [
            first,
            DAccordionItem<String>(
              key: const ValueKey('duplicate-item-a'),
              value: 'a',
              child: first.child,
            ),
          ],
        ),
      ),
    );

    expect(
      tester.takeException(),
      isA<AssertionError>().having(
        (error) => error.message,
        'message',
        contains('unique value'),
      ),
    );
  });

  testWidgets('Tab follows document order and keyboard activation is native', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(DAccordion<String>(children: [item('a'), item('b')])),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(Focus.of(tester.element(find.text('Question a'))).hasFocus, isTrue);
    expect(find.text('Answer a'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Answer a'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Answer a'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(Focus.of(tester.element(find.text('Question b'))).hasFocus, isTrue);
  });

  testWidgets(
    'heading, bounded expanded button and panel descendants stay distinct',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          host(
            DAccordion<String>(
              defaultValues: const ['a'],
              children: [item('a', content: const TextField())],
            ),
          ),
        );
        final trigger = tester.getSemantics(
          find.byKey(const ValueKey('trigger-a')),
        );
        expect(trigger.flagsCollection.isButton, isTrue);
        expect(trigger.flagsCollection.isExpanded, Tristate.isTrue);
        expect(trigger.label, 'Question a');
        expect(find.byType(TextField), findsOneWidget);
        expect(
          tester.getSemantics(find.byType(TextField)).flagsCollection.isButton,
          isFalse,
        );
        expect(
          tester
              .getSemantics(find.byType(DAccordionHeader))
              .flagsCollection
              .isHeader,
          isTrue,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'inherited retention preserves fields and collapse restores trigger focus',
    (tester) async {
      await tester.pumpWidget(
        host(
          DAccordion<String>(
            keepMounted: true,
            defaultValues: const ['a'],
            children: [item('a', content: const TextField())],
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Retained');
      await tester.tap(find.text('Question a'));
      await tester.pumpAndSettle();
      expect(
        Focus.of(tester.element(find.text('Question a'))).hasFocus,
        isTrue,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextField, skipOffstage: false), findsOneWidget);
      await tester.tap(find.text('Question a'));
      await tester.pumpAndSettle();
      expect(find.text('Retained'), findsOneWidget);
    },
  );

  testWidgets('RTL, 200% text, live tokens and reduced motion preserve state', (
    tester,
  ) async {
    DTokens palette(Color seed, double radius) {
      final scheme = ColorScheme.fromSeed(seedColor: seed);
      return DTokens(
        colors: scheme,
        background: scheme.surface,
        surface: scheme.surface,
        muted: scheme.surfaceContainer,
        border: scheme.outlineVariant,
        hover: scheme.surfaceContainerHigh,
        selected: scheme.secondaryContainer,
        selectedForeground: scheme.onSecondaryContainer,
        radius: radius,
      );
    }

    Widget build(DTokens tokens) => host(
      SizedBox(
        width: 180,
        child: DAccordion<String>(
          defaultValues: const ['a'],
          children: [
            item(
              'a',
              content: const Text('A long answer wraps over several lines'),
            ),
          ],
        ),
      ),
      direction: TextDirection.rtl,
      textScale: 2,
      reducedMotion: true,
      tokens: tokens,
    );
    await tester.pumpWidget(build(palette(Colors.blue, 4)));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(build(palette(Colors.green, 12)));
    await tester.pump();
    expect(find.textContaining('long answer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
