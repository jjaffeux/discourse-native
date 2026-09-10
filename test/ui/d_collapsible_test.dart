import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {bool reduced = false}) => MaterialApp(
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: child,
    ),
  ),
);
Widget disclosure({
  bool? open,
  bool defaultOpen = false,
  bool disabled = false,
  ValueChanged<bool>? onChange,
  bool retained = false,
  Duration duration = Duration.zero,
  FocusNode? trigger,
  Widget content = const Text('Details'),
}) => DCollapsible(
  open: open,
  defaultOpen: defaultOpen,
  disabled: disabled,
  onOpenChange: onChange,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DCollapsibleTrigger(focusNode: trigger, child: const Text('Toggle')),
      DCollapsibleContent(
        keepMounted: retained,
        duration: duration,
        child: content,
      ),
    ],
  ),
);

void main() {
  testWidgets(
    'uncontrolled trigger toggles with pointer Enter and Space and announces expanded state',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final node = FocusNode();
        addTearDown(node.dispose);
        final changes = <bool>[];
        await tester.pumpWidget(
          host(disclosure(trigger: node, onChange: changes.add)),
        );
        expect(find.text('Details'), findsNothing);
        expect(
          tester.getSemantics(find.byType(DCollapsibleTrigger)),
          matchesSemantics(
            label: 'Toggle',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasExpandedState: true,
            isExpanded: false,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
          ),
        );
        await tester.tap(find.text('Toggle'));
        await tester.pumpAndSettle();
        expect(find.text('Details'), findsOneWidget);
        node.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(find.text('Details'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text('Details'), findsOneWidget);
        expect(changes, [true, false, true]);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'pointer activation keeps focus without painting the keyboard outline',
    (tester) async {
      final strategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
      final node = FocusNode();
      addTearDown(node.dispose);
      late DCollapsibleTriggerState triggerState;
      await tester.pumpWidget(
        host(
          DCollapsible(
            child: DCollapsibleTrigger(
              focusNode: node,
              builder: (context, state) {
                triggerState = state;
                return const Text('Section');
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Section'));
      await tester.pump();
      expect(node.hasPrimaryFocus, isTrue);
      expect(triggerState.focused, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(triggerState.focused, isTrue);
    },
  );

  testWidgets(
    'controlled state only changes when owner accepts request and disabled blocks activation',
    (tester) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        host(disclosure(open: false, onChange: changes.add)),
      );
      await tester.tap(find.text('Toggle'));
      await tester.pump();
      expect(changes, [true]);
      expect(find.text('Details'), findsNothing);
      await tester.pumpWidget(
        host(disclosure(open: true, disabled: true, onChange: changes.add)),
      );
      expect(find.text('Details'), findsOneWidget);
      await tester.tap(find.text('Toggle'));
      await tester.pump();
      expect(changes, [true]);
      await tester.pumpWidget(
        host(disclosure(open: false, disabled: true, onChange: changes.add)),
      );
      expect(find.text('Details'), findsNothing);
    },
  );

  testWidgets(
    'disabled trigger remains discoverable but keyboard cannot toggle it',
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(host(disclosure(disabled: true, trigger: node)));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(node.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsNothing);
    },
  );

  testWidgets('trigger remains a bounded control inside a semantic container', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        host(
          Semantics(
            key: const ValueKey('card-semantics'),
            container: true,
            child: const DCollapsible(
              child: Row(
                children: [
                  Expanded(child: TextField()),
                  DCollapsibleTrigger(
                    key: ValueKey('bounded-trigger'),
                    semanticLabel: 'More settings',
                    child: Icon(Icons.expand_more),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final card = tester.getSemantics(
        find.byKey(const ValueKey('card-semantics')),
      );
      expect(card.flagsCollection.isButton, isFalse);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('bounded-trigger'))),
        matchesSemantics(
          label: 'More settings',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasExpandedState: true,
          isExpanded: false,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
    } finally {
      semantics.dispose();
    }
  });

  for (final retained in [false, true]) {
    testWidgets(
      '${retained ? 'retained' : 'lazy'} editor restores focus and ${retained ? 'preserves' : 'resets'} edits after collapse',
      (tester) async {
        final trigger = FocusNode();
        addTearDown(trigger.dispose);
        Widget build(bool open) => host(
          disclosure(
            open: open,
            trigger: trigger,
            retained: retained,
            content: const TextField(
              decoration: InputDecoration(labelText: 'Draft'),
            ),
          ),
        );
        await tester.pumpWidget(build(true));
        await tester.enterText(find.byType(TextField), 'Edited');
        await tester.pump();
        await tester.pumpWidget(build(false));
        await tester.pumpAndSettle();
        expect(trigger.hasFocus, isTrue);
        expect(find.byType(TextField), findsNothing);
        expect(
          find.byType(TextField, skipOffstage: false),
          retained ? findsOneWidget : findsNothing,
        );
        await tester.pumpWidget(build(true));
        await tester.pumpAndSettle();
        expect(find.text('Edited'), retained ? findsOneWidget : findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(() => trigger.requestFocus(), returnsNormally);
      },
    );
  }

  testWidgets(
    'nested disclosures retain independent expansion and hide descendants from traversal',
    (tester) async {
      await tester.pumpWidget(
        host(
          DCollapsible(
            defaultOpen: true,
            child: Column(
              children: [
                const DCollapsibleTrigger(child: Text('Outer')),
                DCollapsibleContent(keepMounted: true, child: disclosure()),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Toggle'));
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsOneWidget);
      await tester.tap(find.text('Outer'));
      await tester.pumpAndSettle();
      expect(find.text('Toggle'), findsNothing);
      await tester.tap(find.text('Outer'));
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsOneWidget);
    },
  );

  testWidgets(
    'transition reverses before unmount and reduced motion removes closed content immediately',
    (tester) async {
      Widget build(bool open, {bool reduced = false}) => host(
        disclosure(
          open: open,
          duration: const Duration(milliseconds: 200),
          content: const SizedBox(height: 100, child: Text('Details')),
        ),
        reduced: reduced,
      );
      await tester.pumpWidget(build(true));
      await tester.pumpWidget(build(false));
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('Details'), findsOneWidget);
      await tester.pumpWidget(build(true));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(DCollapsibleContent)).height, 100);
      await tester.pumpWidget(build(false, reduced: true));
      expect(find.text('Details'), findsNothing);
    },
  );

  testWidgets(
    'retained fields stay in Form validation and reset while closed',
    (tester) async {
      final form = GlobalKey<FormState>();
      await tester.pumpWidget(
        host(
          Form(
            key: form,
            child: disclosure(
              defaultOpen: true,
              retained: true,
              content: TextFormField(
                initialValue: 'initial',
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.text('Toggle'));
      await tester.pumpAndSettle();
      expect(form.currentState!.validate(), isFalse);
      form.currentState!.reset();
      await tester.tap(find.text('Toggle'));
      await tester.pumpAndSettle();
      expect(find.text('initial'), findsOneWidget);
      expect(form.currentState!.validate(), isTrue);
    },
  );

  testWidgets(
    'large text RTL and live tokens preserve open state and visible focus',
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      Widget build(Color color) => MaterialApp(
        theme: ThemeData(colorSchemeSeed: color),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: SizedBox(
                width: 180,
                child: disclosure(
                  trigger: node,
                  content: const Text('Long content wraps over multiple lines'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(build(Colors.blue));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(node.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.pumpWidget(build(Colors.green));
      await tester.pumpAndSettle();
      expect(
        find.text('Long content wraps over multiple lines'),
        findsOneWidget,
      );
      expect(node.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
