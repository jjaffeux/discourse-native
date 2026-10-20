import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() => radioListNavigationTests();

void radioListNavigationTests() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('lazy radio reaches all 200 choices at text scale $scale', (
      tester,
    ) async {
      final key = GlobalKey<_LazyRadiosState>();
      await _pumpRadios(tester, key, scale: scale);
      final mounted = find
          .byType(DRadioGroupItem<int>, skipOffstage: false)
          .evaluate()
          .length;
      debugPrint('LAZY_RADIO native scale=$scale mounted=$mounted total=200');
      expect(mounted, lessThan(10));
      await _focus(tester, 0);
      for (var index = 1; index < 200; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(key.currentState!.selected, 199);
      expect(_radio(tester, 199).focusNode.hasFocus, isTrue);
      expect(find.text('Choice 199').hitTestable(), findsOneWidget);
      expect(
        find
            .byType(DRadioGroupItem<int>, skipOffstage: false)
            .evaluate()
            .length,
        lessThan(10),
      );
    });
  }

  for (final direction in TextDirection.values) {
    testWidgets('lazy radio matches mounted radio arrows in $direction', (
      tester,
    ) async {
      Future<List<int?>> sequence({required bool eager}) async {
        final key = GlobalKey<_LazyRadiosState>();
        await _pumpRadios(tester, key, direction: direction, eager: eager);
        key.currentState!.change(() => key.currentState!.disabled = {1, 199});
        await tester.pump();
        await _focus(tester, 0);
        final result = <int?>[];
        for (final arrow in [
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowLeft,
        ]) {
          await _press(tester, arrow);
          result.add(key.currentState!.selected);
        }
        return result;
      }

      final mounted = await sequence(eager: true);
      expect(mounted, [2, 0, 198, 0, 198]);
      expect(await sequence(eager: false), mounted);
    });
  }

  testWidgets(
    'lazy radio keeps accepted controlled values separate from focus proposals',
    (tester) async {
      final key = GlobalKey<_LazyRadiosState>();
      await _pumpRadios(tester, key, accept: false);
      await _focus(tester, 0);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(key.currentState!.proposals, [1]);
      expect(key.currentState!.selected, 0);
      expect(
        tester.state<FormFieldState<int>>(find.byType(DRadioGroup<int>)).value,
        0,
      );
      expect(_radio(tester, 1).focusNode.hasFocus, isTrue);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(key.currentState!.proposals, [1, 2]);
      expect(_radio(tester, 2).focusNode.hasFocus, isTrue);
    },
  );

  testWidgets('lazy radio retains keyboard focus when its row scrolls away', (
    tester,
  ) async {
    final key = GlobalKey<_LazyRadiosState>();
    await _pumpRadios(tester, key);
    await _focus(tester, 0);
    key.currentState!.scroll.jumpTo(8000);
    await tester.pumpAndSettle();
    expect(_radio(tester, 0).focusNode.hasFocus, isTrue);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(key.currentState!.selected, 1);
    expect(_radio(tester, 1).focusNode.hasFocus, isTrue);
    expect(find.text('Choice 1').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'rapid lazy radio arrows keep the latest logical cursor and reveal',
    (tester) async {
      final key = GlobalKey<_LazyRadiosState>();
      final gates = <int, Completer<void>>{};
      await _pumpRadios(
        tester,
        key,
        beforeReveal: (value) => (gates[value] ??= Completer<void>()).future,
      );
      await _focus(tester, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(key.currentState!.proposals, [3, 4]);
      gates[4]!.complete();
      await tester.pumpAndSettle();
      expect(_radio(tester, 4).focusNode.hasFocus, isTrue);
      final offset = key.currentState!.scroll.offset;
      gates[3]!.complete();
      await tester.pumpAndSettle();
      expect(key.currentState!.selected, 4);
      expect(_radio(tester, 4).focusNode.hasFocus, isTrue);
      expect(key.currentState!.scroll.offset, offset);
    },
  );

  for (final reverse in [false, true]) {
    testWidgets(
      'lazy radio enters far accepted choice with ${reverse ? 'ShiftTab' : 'Tab'} and exits once',
      (tester) async {
        final key = GlobalKey<_LazyRadiosState>();
        await _pumpRadios(tester, key);
        key.currentState!.change(() => key.currentState!.selected = 190);
        await tester.pump();
        (reverse ? key.currentState!.after : key.currentState!.outside)
            .requestFocus();
        await tester.pump();
        await _tab(tester, reverse: reverse);
        expect(_focusedValues(tester), [190]);
        expect(key.currentState!.proposals, isEmpty);
        expect(key.currentState!.selected, 190);
        await _tab(tester);
        expect(key.currentState!.after.hasFocus, isTrue);
        await _tab(tester, reverse: true);
        expect(_focusedValues(tester), [190]);
        await _tab(tester, reverse: true);
        expect(key.currentState!.outside.hasFocus, isTrue);
      },
    );
  }

  for (final selected in [null, 190, 999]) {
    testWidgets(
      'lazy radio enters first enabled choice for unavailable selection $selected',
      (tester) async {
        final key = GlobalKey<_LazyRadiosState>();
        await _pumpRadios(tester, key);
        key.currentState!.change(() {
          key.currentState!.selected = selected;
          key.currentState!.disabled = {0, 190};
        });
        await tester.pump();
        key.currentState!.outside.requestFocus();
        await tester.pump();
        await _tab(tester);
        expect(_radio(tester, 1).focusNode.hasFocus, isTrue);
        expect(key.currentState!.selected, selected);
        expect(key.currentState!.proposals, isEmpty);
        await _tab(tester);
        expect(key.currentState!.after.hasFocus, isTrue);
      },
    );
  }

  for (final empty in [false, true]) {
    testWidgets('Tab skips ${empty ? 'empty' : 'disabled'} lazy choices', (
      tester,
    ) async {
      final key = GlobalKey<_LazyRadiosState>();
      await _pumpRadios(tester, key);
      key.currentState!.change(() {
        if (empty) {
          key.currentState!.values.clear();
        } else {
          key.currentState!.disabled = key.currentState!.values.toSet();
        }
      });
      await tester.pump();
      key.currentState!.outside.requestFocus();
      await tester.pump();
      await _tab(tester);
      expect(key.currentState!.after.hasFocus, isTrue);
      expect(key.currentState!.proposals, isEmpty);
    });
  }

  for (final replacement in [
    'query',
    'selection',
    'disabled',
    'removed',
    'focus',
  ]) {
    testWidgets('$replacement retires pending lazy Tab entry', (tester) async {
      final key = GlobalKey<_LazyRadiosState>();
      final gate = Completer<void>();
      await _pumpRadios(tester, key, beforeReveal: (_) => gate.future);
      key.currentState!.change(() => key.currentState!.selected = 190);
      await tester.pump();
      key.currentState!.outside.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      key.currentState!.change(() {
        switch (replacement) {
          case 'query':
            key.currentState!.revision++;
          case 'selection':
            key.currentState!.selected = 99;
          case 'disabled':
            key.currentState!.disabled = {190};
          case 'removed':
            key.currentState!.values.remove(190);
          case 'focus':
            key.currentState!.after.requestFocus();
        }
      });
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();
      expect(key.currentState!.revealed, isEmpty);
      expect(key.currentState!.proposals, isEmpty);
      expect(key.currentState!.scroll.offset, 0);
      if (replacement != 'focus') {
        await _tab(tester);
        expect(key.currentState!.after.hasFocus, isTrue);
      }
    });
  }

  testWidgets('uncontrolled lazy navigation and reset update the Form owner', (
    tester,
  ) async {
    final key = GlobalKey<_LazyRadiosState>();
    await _pumpRadios(tester, key);
    key.currentState!.change(() => key.currentState!.controlled = false);
    await tester.pump();
    await _focus(tester, 0);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    final field = tester.state<FormFieldState<int>>(
      find.byType(DRadioGroup<int>),
    );
    expect(field.value, 1);
    key.currentState!.form.currentState!.reset();
    await tester.pumpAndSettle();
    expect(field.value, 0);
    expect(key.currentState!.selected, 0);
  });

  testWidgets('Space during lazy reveal focuses without selecting twice', (
    tester,
  ) async {
    final key = GlobalKey<_LazyRadiosState>();
    final gate = Completer<void>();
    await _pumpRadios(tester, key, beforeReveal: (_) => gate.future);
    await _focus(tester, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(key.currentState!.proposals, [3]);
    expect(_radio(tester, 3).focusNode.hasFocus, isTrue);
  });

  testWidgets('Form reset retires a pending lazy radio reveal', (tester) async {
    final key = GlobalKey<_LazyRadiosState>();
    final gate = Completer<void>();
    await _pumpRadios(tester, key, beforeReveal: (_) => gate.future);
    await _focus(tester, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    key.currentState!.form.currentState!.reset();
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(key.currentState!.revealed, isEmpty);
    expect(key.currentState!.selected, 0);
    expect(key.currentState!.scroll.offset, 0);
  });

  for (final replacement in [
    'query',
    'selection',
    'removed',
    'disabled',
    'group disabled',
    'ownership',
    'pointer',
    'focus',
  ]) {
    testWidgets('$replacement retires a pending lazy radio reveal', (
      tester,
    ) async {
      final key = GlobalKey<_LazyRadiosState>();
      final gate = Completer<void>();
      await _pumpRadios(tester, key, beforeReveal: (_) => gate.future);
      await _focus(tester, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      switch (replacement) {
        case 'query':
          key.currentState!.change(() => key.currentState!.revision++);
        case 'selection':
          key.currentState!.change(() => key.currentState!.selected = 99);
        case 'removed':
          key.currentState!.change(() => key.currentState!.values.remove(3));
        case 'disabled':
          key.currentState!.change(() => key.currentState!.disabled = {3});
        case 'group disabled':
          key.currentState!.change(() => key.currentState!.enabled = false);
        case 'ownership':
          key.currentState!.change(() => key.currentState!.controlled = false);
        case 'pointer':
          await tester.tap(find.text('Choice 0'));
        case 'focus':
          key.currentState!.outside.requestFocus();
      }
      await tester.pumpAndSettle();
      final offset = key.currentState!.scroll.offset;
      gate.complete();
      await tester.pumpAndSettle();
      expect(key.currentState!.scroll.offset, offset);
      expect(key.currentState!.revealed, isEmpty);
      if (replacement == 'selection') expect(key.currentState!.selected, 99);
      if (replacement == 'pointer') expect(key.currentState!.selected, 0);
      if (replacement == 'focus') {
        expect(key.currentState!.outside.hasFocus, isTrue);
      }
    });
  }

  testWidgets('disposing a lazy group retires a pending reveal', (
    tester,
  ) async {
    final key = GlobalKey<_LazyRadiosState>();
    final gate = Completer<void>();
    await _pumpRadios(tester, key, beforeReveal: (_) => gate.future);
    await _focus(tester, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _tab(WidgetTester tester, {bool reverse = false}) async {
  if (reverse) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (reverse) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

List<int> _focusedValues(WidgetTester tester) => find
    .byType(RawRadio<int>, skipOffstage: false)
    .evaluate()
    .map((element) => element.widget as RawRadio<int>)
    .where((radio) => radio.focusNode.hasFocus)
    .map((radio) => radio.value)
    .toList();

RawRadio<int> _radio(WidgetTester tester, int value) =>
    tester.widget<RawRadio<int>>(
      find.descendant(
        of: find.byKey(ValueKey('choice-$value'), skipOffstage: false),
        matching: find.byType(RawRadio<int>, skipOffstage: false),
        skipOffstage: false,
      ),
    );

Future<void> _focus(WidgetTester tester, int value) async {
  _radio(tester, value).focusNode.requestFocus();
  await tester.pump();
}

Future<void> _pumpRadios(
  WidgetTester tester,
  GlobalKey<_LazyRadiosState> key, {
  double scale = 1,
  bool accept = true,
  bool eager = false,
  TextDirection direction = TextDirection.ltr,
  Future<void> Function(int)? beforeReveal,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Directionality(
          textDirection: direction,
          child: _LazyRadios(
            key: key,
            eager: eager,
            accept: accept,
            beforeReveal: beforeReveal,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _LazyRadios extends StatefulWidget {
  const _LazyRadios({
    super.key,
    required this.accept,
    this.beforeReveal,
    this.eager = false,
  });
  final bool accept;
  final bool eager;
  final Future<void> Function(int)? beforeReveal;
  @override
  State<_LazyRadios> createState() => _LazyRadiosState();
}

class _LazyRadiosState extends State<_LazyRadios> {
  final form = GlobalKey<FormState>();
  final scroll = ScrollController();
  final outside = FocusNode();
  final after = FocusNode();
  final proposals = <int?>[];
  final revealed = <int>[];
  final values = List.generate(200, (index) => index);
  Set<int> disabled = {};
  int revision = 0;
  int? selected = 0;
  bool enabled = true;
  bool controlled = true;

  void change(VoidCallback mutation) => setState(mutation);

  Future<void> reveal(int value, bool Function() isCurrent) async {
    await widget.beforeReveal?.call(value);
    if (!mounted || !isCurrent()) return;
    revealed.add(value);
    scroll.jumpTo(values.indexOf(value) * 80);
    await WidgetsBinding.instance.endOfFrame;
  }

  @override
  void dispose() {
    scroll.dispose();
    outside.dispose();
    after.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget item(int value) => DRadioGroupItem<int>(
      key: ValueKey('choice-$value'),
      value: value,
      enabled: !disabled.contains(value),
      card: true,
      label: Text('Choice $value'),
    );
    final child = SizedBox(
      height: 240,
      child: widget.eager
          ? SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  for (final value in values)
                    SizedBox(height: 80, child: item(value)),
                ],
              ),
            )
          : ListView.builder(
              controller: scroll,
              scrollCacheExtent: const ScrollCacheExtent.pixels(0),
              itemExtent: 80,
              itemCount: values.length,
              itemBuilder: (context, index) => item(values[index]),
            ),
    );
    final navigation =
        widget.eager || const bool.fromEnvironment('RADIO_COLLECTION_BASELINE')
        ? null
        : DRadioGroupNavigation<int>(
            values: values,
            disabledValues: disabled,
            revision: revision,
            reveal: reveal,
          );
    void changed(int? value) {
      proposals.add(value);
      if (widget.accept) setState(() => selected = value);
    }

    return Column(
      children: [
        DButton(
          focusNode: outside,
          onPressed: () {},
          label: const Text('Outside'),
        ),
        Form(
          key: form,
          child: controlled
              ? DRadioGroup<int>.controlled(
                  groupValue: selected,
                  initialValue: 0,
                  enabled: enabled,
                  navigation: navigation,
                  onChanged: changed,
                  child: child,
                )
              : DRadioGroup<int>(
                  initialValue: 0,
                  enabled: enabled,
                  navigation: navigation,
                  onChanged: changed,
                  child: child,
                ),
        ),
        DButton(focusNode: after, onPressed: () {}, label: const Text('After')),
      ],
    );
  }
}
