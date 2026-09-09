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

DAccordionItem<String> item(
  String value, {
  bool disabled = false,
  FocusNode? focusNode,
  Widget? content,
}) => DAccordionItem<String>(
  key: ValueKey('item-$value'),
  value: value,
  disabled: disabled,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DAccordionHeader(
        child: DAccordionTrigger(
          key: ValueKey('trigger-$value'),
          focusNode: focusNode,
          child: Text('Question $value'),
        ),
      ),
      DAccordionContent(child: content ?? Text('Answer $value')),
    ],
  ),
);

void main() {
  testWidgets('local single mode opens one item and permits closing all', (
    tester,
  ) async {
    final changes = <Set<String>>[];
    await tester.pumpWidget(
      host(
        DAccordion<String>(
          defaultValues: const ['a'],
          onValuesChange: (value) => changes.add({...value}),
          children: [item('a'), item('b'), item('c')],
        ),
      ),
    );
    expect(find.text('Answer a'), findsOneWidget);
    expect(find.text('Answer b'), findsNothing);

    await tester.tap(find.text('Question b'));
    await tester.pumpAndSettle();
    expect(find.text('Answer a'), findsNothing);
    expect(find.text('Answer b'), findsOneWidget);
    await tester.tap(find.text('Question b'));
    await tester.pumpAndSettle();
    expect(find.text('Answer b'), findsNothing);
    expect(changes, [
      {'b'},
      <String>{},
    ]);
  });

  testWidgets('multiple mode retains independently opened items', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        DAccordion<String>(
          multiple: true,
          defaultValues: const ['a'],
          children: [item('a'), item('b')],
        ),
      ),
    );
    await tester.tap(find.text('Question b'));
    await tester.pumpAndSettle();
    expect(find.text('Answer a'), findsOneWidget);
    expect(find.text('Answer b'), findsOneWidget);
  });

  testWidgets(
    'controlled state only changes when its owner accepts the request',
    (tester) async {
      final changes = <Set<String>>[];
      Widget build(Set<String> values) => host(
        DAccordion<String>(
          values: values,
          onValuesChange: (value) => changes.add({...value}),
          children: [item('a'), item('b')],
        ),
      );
      await tester.pumpWidget(build({}));
      await tester.tap(find.text('Question a'));
      await tester.pumpAndSettle();
      expect(changes, [
        {'a'},
      ]);
      expect(find.text('Answer a'), findsNothing);
      await tester.pumpWidget(build({'a'}));
      await tester.pumpAndSettle();
      expect(find.text('Answer a'), findsOneWidget);
    },
  );

  testWidgets(
    'borrowed controller supports programmatic state and survives root disposal',
    (tester) async {
      final controller = DAccordionController<String>(multiple: true);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          DAccordion<String>(
            controller: controller,
            multiple: true,
            children: [item('a'), item('b')],
          ),
        ),
      );
      controller.replace(const ['a', 'b']);
      await tester.pumpAndSettle();
      expect(find.textContaining('Answer'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(() => controller.close('a'), returnsNormally);
    },
  );

  testWidgets(
    'root and item disabled states remain discoverable and block input',
    (tester) async {
      final first = FocusNode();
      final second = FocusNode();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await tester.pumpWidget(
        host(
          DAccordion<String>(
            children: [
              item('a', disabled: true, focusNode: first),
              item('b', focusNode: second),
            ],
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(first.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Answer a'), findsNothing);
      await tester.tap(find.text('Question b'));
      await tester.pumpAndSettle();
      expect(find.text('Answer b'), findsOneWidget);

      await tester.pumpWidget(
        host(
          DAccordion<String>(
            key: const ValueKey('disabled-root'),
            disabled: true,
            children: [item('b')],
          ),
        ),
      );
      await tester.tap(find.text('Question b'));
      await tester.pumpAndSettle();
      expect(find.text('Answer b'), findsNothing);
    },
  );

  testWidgets(
    'removed values are pruned while reordered items preserve state',
    (tester) async {
      final controller = DAccordionController<String>(
        multiple: true,
        initialValues: const ['a', 'b'],
      );
      addTearDown(controller.dispose);
      Widget build(List<String> values) => host(
        DAccordion<String>(
          controller: controller,
          multiple: true,
          children: [for (final value in values) item(value)],
        ),
      );
      await tester.pumpWidget(build(['a', 'b']));
      await tester.pumpWidget(build(['b', 'a']));
      await tester.pump();
      expect(find.textContaining('Answer'), findsNWidgets(2));
      await tester.pumpWidget(build(['b']));
      await tester.pump();
      expect(controller.values, {'b'});
    },
  );

  testWidgets('Tab follows document order and keyboard activation is native', (
    tester,
  ) async {
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(
      host(
        DAccordion<String>(
          children: [
            item('a', focusNode: first),
            item('b', focusNode: second),
          ],
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(first.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(second.hasFocus, isTrue);
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
      final trigger = FocusNode();
      addTearDown(trigger.dispose);
      await tester.pumpWidget(
        host(
          DAccordion<String>(
            keepMounted: true,
            defaultValues: const ['a'],
            children: [
              item('a', focusNode: trigger, content: const TextField()),
            ],
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Retained');
      await tester.tap(find.text('Question a'));
      await tester.pumpAndSettle();
      expect(trigger.hasFocus, isTrue);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextField, skipOffstage: false), findsOneWidget);
      await tester.tap(find.text('Question a'));
      await tester.pumpAndSettle();
      expect(find.text('Retained'), findsOneWidget);
    },
  );

  testWidgets(
    'base geometry, outlined composition and native touch target match mapping',
    (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: DAccordion<String>(
              outlined: true,
              defaultValues: const ['a'],
              children: [item('a'), item('b')],
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('trigger-a'))).height,
        40,
      );
      expect(
        tester.getSize(find.byType(DAccordionContent).first).height,
        greaterThan(20),
      );
      final firstItem = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(const ValueKey('item-a')),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(firstItem.padding, const EdgeInsets.symmetric(horizontal: 16));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        host(
          DAccordion<String>(children: [item('a')]),
          platform: TargetPlatform.iOS,
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('trigger-a'))).height,
        48,
      );
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
