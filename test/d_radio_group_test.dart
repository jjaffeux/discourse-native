import 'dart:io';
import 'dart:ui' show SemanticsAction, SemanticsActionEvent, PointerDeviceKind;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/keyboard_navigation.dart';
import 'package:discourse_native/src/styleguide/examples/radio_group_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  Widget child, {
  TextDirection direction = TextDirection.ltr,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: Directionality(textDirection: direction, child: child),
  ),
);
const choices = Column(
  children: [
    DRadioGroupItem(value: 'a', label: Text('Alpha')),
    DRadioGroupItem(value: 'b', label: Text('Beta'), enabled: false),
    DRadioGroupItem(value: 'c', label: Text('Charlie')),
  ],
);

List<SemanticsData> radioSemantics(WidgetTester tester) {
  final radios = <SemanticsData>[];
  void visit(SemanticsNode node) {
    if (!node.isMergedIntoParent &&
        node.getSemanticsData().flagsCollection.isInMutuallyExclusiveGroup) {
      radios.add(node.getSemanticsData());
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(find.byType(DRadioGroup<String>)));
  return radios;
}

void main() {
  test('all snippets are runnable and match their actual example source', () {
    final source = File(
      'lib/src/styleguide/examples/radio_group_examples.dart',
    ).readAsStringSync();
    final reference = source.indexOf('class _Reference extends');
    final form = source.indexOf('class _FormPreview extends');
    final readOnly = source.indexOf('class _ReadOnlyPreview extends');
    for (final example in radioGroupExamples.examples) {
      final implementation = switch (example.title) {
        'Read-only and required' => source.substring(readOnly),
        'Controlled form and dynamic options' => source.substring(
          form,
          readOnly,
        ),
        _ => source.substring(reference, form),
      };
      expect(example.code, contains('void main() => runApp('));
      expect(example.code, endsWith(implementation), reason: example.title);
    }
  });

  for (final controlled in [false, true]) {
    testWidgets(
      'mounted reset baseline and synchronous Form values (controlled: $controlled)',
      (tester) async {
        final form = GlobalKey<FormState>();
        final field = GlobalKey<FormFieldState<String>>();
        final requests = <String?>[];
        final observed = <String?>[];
        var initial = 'a';
        String? accepted = 'a';
        String? saved;
        late StateSetter update;
        void observe() {
          form.currentState!.save();
          observed.add(saved);
          expect(form.currentState!.validate(), isTrue);
        }

        await tester.pumpWidget(
          host(
            StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                void changed(String? value) {
                  requests.add(value);
                  observe();
                }

                String? validate(String? value) =>
                    controlled && value != accepted
                    ? 'Unaccepted proposal'
                    : null;
                return Form(
                  key: form,
                  onChanged: observe,
                  child: controlled
                      ? DRadioGroup<String>.controlled(
                          key: field,
                          initialValue: initial,
                          groupValue: accepted,
                          onChanged: changed,
                          onSaved: (value) => saved = value,
                          validator: validate,
                          child: choices,
                        )
                      : DRadioGroup<String>(
                          key: field,
                          initialValue: initial,
                          onChanged: changed,
                          onSaved: (value) => saved = value,
                          validator: validate,
                          child: choices,
                        ),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('Charlie'));
        await tester.pump();
        expect(requests, ['c']);
        expect(observed, everyElement(controlled ? 'a' : 'c'));
        expect(field.currentState!.hasInteractedByUser, isTrue);

        update(() {
          initial = 'b';
          accepted = 'c';
        });
        await tester.pump();
        observed.clear();
        form.currentState!.reset();
        expect(requests, ['c', 'a']);
        expect(observed, everyElement(controlled ? 'c' : 'a'));
        expect(field.currentState!.hasInteractedByUser, isFalse);
        expect(field.currentState!.hasError, isFalse);
        await tester.pump();
        form.currentState!.save();
        expect(saved, controlled ? 'c' : 'a');
      },
    );
  }

  testWidgets('Form error is associated with each radio and clears live', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(
      host(
        Form(
          key: form,
          child: DRadioGroup<String>(
            required: true,
            validator: (value) => value == null ? 'Choose one' : null,
            child: choices,
          ),
        ),
      ),
    );
    final radio = find.byType(RawRadio<String>).first;
    final focus = tester.widget<RawRadio<String>>(radio).focusNode;
    final state = tester.state(find.byType(DRadioGroupItem<String>).first);
    focus.requestFocus();
    await tester.pump();
    expect(form.currentState!.validate(), isFalse);
    await tester.pumpAndSettle();
    expect(
      tester.state(find.byType(DRadioGroupItem<String>).first),
      same(state),
    );
    expect(focus.hasFocus, isTrue);
    var node = radioSemantics(
      tester,
    ).singleWhere((node) => node.label == 'Alpha');
    expect(node.label, 'Alpha');
    expect(node.hint, contains('Choose one'));
    expect(node.validationResult, SemanticsValidationResult.invalid);
    await tester.tap(find.text('Alpha'));
    await tester.pump();
    expect(form.currentState!.validate(), isTrue);
    await tester.pumpAndSettle();
    expect(
      tester.state(find.byType(DRadioGroupItem<String>).first),
      same(state),
    );
    expect(focus.hasFocus, isTrue);
    node = radioSemantics(tester).singleWhere((node) => node.label == 'Alpha');
    expect(node.hint, isNot(contains('Choose one')));
    expect(node.validationResult, SemanticsValidationResult.none);
    semantics.dispose();
  });

  testWidgets(
    'desktop rows follow content height and preserve eight-pixel gaps',
    (tester) async {
      for (final title in ['Default', 'Description', 'Fieldset']) {
        await tester.pumpWidget(
          host(
            Builder(
              builder: radioGroupExamples.examples
                  .singleWhere((e) => e.title == title)
                  .builder,
            ),
            theme: ThemeData(platform: TargetPlatform.macOS),
          ),
        );
        final rows = title == 'Default'
            ? find.byType(RawRadio<String>)
            : find.byType(DField);
        expect(rows, findsNWidgets(3));
        final bounds = [
          for (final e in rows.evaluate())
            tester.getRect(find.byWidget(e.widget)),
        ];
        for (var i = 1; i < bounds.length; i++) {
          expect(
            bounds[i].top - bounds[i - 1].bottom,
            closeTo(8, 0.001),
            reason: '$title row $i: $bounds',
          );
        }
        if (title == 'Default') {
          expect(bounds.first.height, 16);
          expect(bounds.last.bottom - bounds.first.top, 64);
        } else {
          final content = tester.getSize(find.byType(DFieldLabel).first);
          if (title == 'Fieldset') {
            expect(bounds.first.height, content.height);
          }
          if (title == 'Description') {
            expect(bounds.first.height, greaterThan(content.height));
          }
        }
      }
    },
  );
  testWidgets('composition labels activate the radio Form owner exactly once', (
    tester,
  ) async {
    for (final (title, label) in [
      ('Description', 'Compact'),
      ('Choice Card', 'Pro'),
    ]) {
      var changes = 0;
      await tester.pumpWidget(
        host(
          Form(
            key: ValueKey(title),
            onChanged: () => changes++,
            child: Builder(
              builder: radioGroupExamples.examples
                  .singleWhere((example) => example.title == title)
                  .builder,
            ),
          ),
        ),
      );
      await tester.tap(find.text(label));
      await tester.pump();
      expect(changes, 1, reason: title);
      await tester.tap(find.text(label));
      await tester.pump();
      expect(changes, 1, reason: '$title selecting the active item is a no-op');
    }
  });

  testWidgets(
    'frozen examples use final Label and Field compositions with one radio owner',
    (tester) async {
      Future<void> show(String title) async {
        final example = radioGroupExamples.examples.singleWhere(
          (example) => example.title == title,
        );
        await tester.pumpWidget(
          host(
            Builder(builder: example.builder),
            theme: ThemeData(platform: TargetPlatform.macOS),
          ),
        );
        await tester.pump();
        expect(find.byType(RawRadio<String>), findsNWidgets(3), reason: title);
      }

      await show('Default');
      expect(
        tester
            .widgetList<DRadioGroupItem<String>>(
              find.byType(DRadioGroupItem<String>),
            )
            .every((item) => item.label is DLabel),
        true,
      );

      for (final title in [
        'Description',
        'Choice Card',
        'Fieldset',
        'Disabled',
        'Invalid',
        'RTL',
      ]) {
        await show(title);
        expect(find.byType(DField), findsNWidgets(3), reason: title);
        expect(find.byType(DFieldControl), findsNWidgets(3), reason: title);
        expect(
          tester
              .widgetList<DRadioGroupItem<String>>(
                find.byType(DRadioGroupItem<String>),
              )
              .every((item) => item.label == null && !item.card),
          true,
          reason: '$title keeps the radio as the sole interaction owner',
        );
      }

      await show('Description');
      await tester.tap(find.text('Compact'));
      await tester.pump();
      expect(
        tester
            .widget<DRadioGroup<String>>(find.byType(DRadioGroup<String>))
            .groupValue,
        'compact',
      );

      await show('Choice Card');
      expect(
        tester
            .widgetList<DFieldLabel>(find.byType(DFieldLabel))
            .where((label) => label.choice),
        hasLength(3),
      );
      await tester.tap(find.text('Pro'));
      await tester.pump();
      expect(
        tester
            .widget<DRadioGroup<String>>(find.byType(DRadioGroup<String>))
            .groupValue,
        'pro',
      );

      await show('Fieldset');
      expect(find.byType(DFieldSet), findsOneWidget);
      expect(find.byType(DFieldLegend), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(DFieldDescription)).dy -
            tester.getBottomLeft(find.byType(DFieldLegend)).dy,
        2,
      );
      expect(
        tester.getTopLeft(find.byType(DField).first).dy -
            tester.getBottomLeft(find.byType(DFieldDescription)).dy,
        12,
      );

      await show('Disabled');
      await tester.tap(find.text('Disabled'), warnIfMissed: false);
      await tester.pump();
      expect(
        tester
            .widget<DRadioGroup<String>>(find.byType(DRadioGroup<String>))
            .groupValue,
        'option2',
      );
      await tester.tap(find.text('Option 3'));
      await tester.pump();
      expect(
        tester
            .widget<DRadioGroup<String>>(find.byType(DRadioGroup<String>))
            .groupValue,
        'option3',
      );

      await show('Invalid');
      expect(
        tester
            .widgetList<DField>(find.byType(DField))
            .every((field) => field.invalid),
        true,
      );

      await show('RTL');
      expect(
        Directionality.of(tester.element(find.byType(DField).first)),
        TextDirection.rtl,
      );
    },
  );
  testWidgets(
    'final fields preserve three uniquely named radio semantics owners',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        for (final title in [
          'Description',
          'Choice Card',
          'Fieldset',
          'Disabled',
          'Invalid',
          'RTL',
        ]) {
          await tester.pumpWidget(
            host(
              Builder(
                builder: radioGroupExamples.examples
                    .singleWhere((example) => example.title == title)
                    .builder,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final nodes = radioSemantics(tester);
          final labels = tester
              .widgetList<DFieldControl>(find.byType(DFieldControl))
              .map((field) => field.label)
              .toList();
          expect(nodes, hasLength(3), reason: title);
          expect(
            nodes.map((node) => node.label),
            unorderedEquals(labels),
            reason: title,
          );
          if (title == 'Invalid') {
            expect(
              nodes.map((node) => node.validationResult),
              everyElement(SemanticsValidationResult.invalid),
            );
          }
          if (title == 'Disabled') {
            expect(
              nodes
                  .singleWhere((node) => node.label == 'Disabled')
                  .hasAction(SemanticsAction.tap),
              isFalse,
            );
          }
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'card focus paints outer rings without darkening translucent content',
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        host(
          DRadioGroup<String>(
            initialValue: 'a',
            child: DRadioGroupItem(
              value: 'a',
              label: const Text('Plan'),
              description: const Text('Description'),
              card: true,
              focusNode: node,
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final containers = tester.widgetList<Container>(find.byType(Container));
      final rings = containers
          .where((c) => c.foregroundDecoration is BoxDecoration)
          .toList();
      expect(rings.length, 2);
      for (final ring in rings) {
        final decoration = ring.foregroundDecoration! as BoxDecoration;
        expect(
          decoration.border!.top.strokeAlign,
          BorderSide.strokeAlignOutside,
        );
        expect(decoration.border!.top.width, 3);
        expect((ring.decoration! as BoxDecoration).boxShadow, isNull);
      }
      final card = rings.singleWhere(
        (c) => (c.decoration! as BoxDecoration).shape == BoxShape.rectangle,
      );
      expect(
        (card.decoration! as BoxDecoration).color!.a,
        closeTo(0.05, 0.001),
      );
      final label = tester.element(find.text('Plan'));
      expect(DefaultTextStyle.of(label).style.height, 20 / 14);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'input role and opacity remain distinct from card border in live themes',
    (tester) async {
      final base = ThemeData(platform: TargetPlatform.macOS);
      final colors = base.colorScheme.copyWith(
        outlineVariant: const Color(0x80443322),
        primary: const Color(0x80665544),
      );
      final tokens = DTokens.fromTheme(base).copyWith(
        colors: colors,
        border: const Color(0xff112233),
        muted: const Color(0x80887766),
        radius: 7,
      );
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          host(
            DRadioGroup<String>(
              initialValue: 'a',
              child: const Column(
                children: [
                  DRadioGroupItem(
                    value: 'a',
                    card: true,
                    label: Text('Selected'),
                    description: Text('Description'),
                  ),
                  DRadioGroupItem(value: 'b', label: Text('Unselected')),
                ],
              ),
            ),
            theme: base.copyWith(
              brightness: dark ? Brightness.dark : Brightness.light,
              extensions: [tokens],
            ),
          ),
        );
        await tester.pumpAndSettle();
        final containers = tester.widgetList<Container>(find.byType(Container));
        final circle = containers
            .where(
              (c) =>
                  c.decoration is BoxDecoration &&
                  (c.decoration! as BoxDecoration).shape == BoxShape.circle &&
                  (c.decoration! as BoxDecoration).border?.top.color ==
                      colors.outlineVariant,
            )
            .single;
        final fill = (circle.decoration! as BoxDecoration).color!;
        expect(
          fill.a,
          closeTo(dark ? colors.outlineVariant.a * 0.3 : 0, 0.001),
        );
        final card = containers
            .where(
              (c) =>
                  c.decoration is BoxDecoration &&
                  (c.decoration! as BoxDecoration).borderRadius != null,
            )
            .single;
        final decoration = card.decoration! as BoxDecoration;
        expect(card.padding, const EdgeInsets.all(10));
        expect(decoration.borderRadius, BorderRadius.circular(7));
        expect(
          decoration.border!.top.color.a,
          closeTo(colors.primary.a * (dark ? 0.2 : 0.3), 0.001),
        );
        expect(
          decoration.color!.a,
          closeTo(colors.primary.a * (dark ? 0.1 : 0.05), 0.001),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.text('Selected')));
        await tester.pump();
        final hovered = tester.widget<Container>(
          find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).borderRadius != null,
          ),
        );
        expect(
          (hovered.decoration! as BoxDecoration).color,
          tokens.muted.withValues(alpha: tokens.muted.a * 0.5),
        );
        await mouse.removePointer();
        await tester.pump();
      }
    },
  );

  testWidgets(
    'read-only preserves focus and blocks pointer keyboard and semantics selection',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final first = FocusNode();
      final second = FocusNode();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      var changes = 0;
      await tester.pumpWidget(
        host(
          DRadioGroup<String>(
            initialValue: 'a',
            readOnly: true,
            onChanged: (_) => changes++,
            child: Column(
              children: [
                DRadioGroupItem(
                  value: 'a',
                  label: const Text('Alpha'),
                  focusNode: first,
                  toggleable: true,
                ),
                DRadioGroupItem(
                  value: 'b',
                  label: const Text('Beta'),
                  focusNode: second,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Beta'));
      await tester.pump();
      await tester.tap(find.text('Alpha'));
      await tester.pump();
      first.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(second.hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      final node = tester.getSemantics(find.byType(RawRadio<String>).last);
      expect(
        node,
        isSemantics(isReadOnly: true, isEnabled: true, isFocusable: true),
      );
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          viewId: tester.view.viewId,
          nodeId: node.id,
          type: SemanticsAction.tap,
        ),
      );
      await tester.pump();
      expect(changes, 0);
      expect(
        tester.getSemantics(find.byType(RawRadio<String>).first),
        isSemantics(isChecked: true),
      );
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'item overrides inherit live group props without stale access after removal',
    (tester) async {
      var readOnly = true;
      var showOverride = true;
      String? selected = 'a';
      late StateSetter update;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return DRadioGroup<String>.controlled(
                groupValue: selected,
                readOnly: readOnly,
                onChanged: (value) => setState(() => selected = value),
                child: Column(
                  children: [
                    const DRadioGroupItem(value: 'a', label: Text('Inherited')),
                    if (showOverride)
                      const DRadioGroupItem(
                        value: 'b',
                        label: Text('Editable override'),
                        readOnly: false,
                      ),
                    const DRadioGroupItem(
                      value: 'c',
                      label: Text('Read-only override'),
                      readOnly: true,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selected, 'b');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selected, 'b');
      await tester.tap(find.text('Editable override'));
      await tester.pump();
      expect(selected, 'b');
      await tester.tap(find.text('Inherited'));
      await tester.pump();
      expect(selected, 'b');
      update(() {
        readOnly = false;
        showOverride = false;
      });
      await tester.pump();
      await tester.tap(find.text('Inherited'));
      await tester.pump();
      expect(selected, 'a');
      await tester.tap(find.text('Read-only override'));
      await tester.pump();
      expect(selected, 'a');
      update(() => readOnly = true);
      await tester.pump();
      await tester.tap(find.text('Inherited'));
      await tester.pump();
      expect(selected, 'a');
    },
  );
  testWidgets(
    'read-only controlled Form accepts parent changes reset and required validation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final form = GlobalKey<FormState>();
      String? accepted;
      String? saved;
      String? resetRequest = 'untouched';
      late StateSetter update;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Form(
                key: form,
                child: DRadioGroup<String>.controlled(
                  groupValue: accepted,
                  readOnly: true,
                  required: true,
                  onChanged: (value) => resetRequest = value,
                  onSaved: (value) => saved = value,
                  validator: (value) =>
                      value == null ? 'A choice is required.' : null,
                  child: const Column(
                    children: [
                      DRadioGroupItem(
                        value: 'a',
                        label: Text('Required choice'),
                      ),
                      DRadioGroupItem(
                        value: 'b',
                        label: Text('Optional announcement'),
                        required: false,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      expect(form.currentState!.validate(), false);
      await tester.pump();
      expect(find.text('A choice is required.'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(RawRadio<String>).first),
        isSemantics(isRequired: true, isReadOnly: true),
      );
      expect(
        tester.getSemantics(find.byType(RawRadio<String>).last),
        isSemantics(isRequired: false),
      );
      update(() => accepted = 'b');
      await tester.pump();
      expect(form.currentState!.validate(), true);
      form.currentState!.save();
      expect(saved, 'b');
      form.currentState!.reset();
      await tester.pump();
      expect(resetRequest, isNull);
      form.currentState!.save();
      expect(saved, 'b');
      semantics.dispose();
    },
  );
  testWidgets('read-only controlled value without callback remains focusable', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      host(
        DRadioGroup<String>.controlled(
          groupValue: 'a',
          onChanged: null,
          readOnly: true,
          child: DRadioGroupItem(
            value: 'a',
            label: const Text('Alpha'),
            focusNode: node,
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(node.hasFocus, true);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('label activation updates and reset restores initial selection', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    String? saved;
    await tester.pumpWidget(
      host(
        Form(
          key: form,
          child: DRadioGroup<String>(
            initialValue: 'a',
            onSaved: (v) => saved = v,
            child: choices,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Charlie'));
    await tester.pump();
    form.currentState!.save();
    expect(saved, 'c');
    form.currentState!.reset();
    await tester.pump();
    form.currentState!.save();
    expect(saved, 'a');
  });
  testWidgets('controlled rejection does not change selection or saved value', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    String? request;
    String? saved;
    await tester.pumpWidget(
      host(
        Form(
          key: form,
          child: DRadioGroup<String>.controlled(
            groupValue: 'a',
            onChanged: (v) => request = v,
            onSaved: (v) => saved = v,
            child: choices,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Charlie'));
    await tester.pump();
    form.currentState!.save();
    expect(request, 'c');
    expect(saved, 'a');
  });
  testWidgets(
    'controlled reset preserves accepted value until parent accepts',
    (tester) async {
      final form = GlobalKey<FormState>();
      String? accepted = 'c';
      String? requested;
      String? saved;
      late StateSetter update;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Form(
                key: form,
                child: DRadioGroup<String>.controlled(
                  groupValue: accepted,
                  initialValue: 'a',
                  onChanged: (value) => requested = value,
                  onSaved: (value) => saved = value,
                  validator: (value) => value == accepted ? null : 'Mismatch',
                  child: choices,
                ),
              );
            },
          ),
        ),
      );
      form.currentState!.reset();
      await tester.pump();
      expect(requested, 'a');
      form.currentState!.save();
      expect(saved, 'c');
      expect(form.currentState!.validate(), true);
      update(() => accepted = requested);
      await tester.pump();
      form.currentState!.save();
      expect(saved, 'a');
      expect(form.currentState!.validate(), true);
    },
  );
  for (final direction in TextDirection.values) {
    testWidgets('arrows wrap and skip disabled options in $direction', (
      tester,
    ) async {
      String? selected;
      await tester.pumpWidget(
        host(
          DRadioGroup<String>(
            initialValue: 'a',
            onChanged: (v) => selected = v,
            child: choices,
          ),
          direction: direction,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selected, 'c');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selected, 'a');
      await tester.sendKeyEvent(
        direction == TextDirection.rtl
            ? LogicalKeyboardKey.arrowLeft
            : LogicalKeyboardKey.arrowRight,
      );
      await tester.pump();
      expect(selected, 'c');
    });
  }
  testWidgets(
    'validation error clears after selection and reset notifies owner',
    (tester) async {
      final form = GlobalKey<FormState>();
      String? value;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => Form(
              key: form,
              child: DRadioGroup<String>.controlled(
                groupValue: value,
                onChanged: (v) => setState(() => value = v),
                validator: (v) => v == null ? 'Choose one' : null,
                child: choices,
              ),
            ),
          ),
        ),
      );
      expect(form.currentState!.validate(), false);
      await tester.pump();
      expect(find.text('Choose one'), findsOneWidget);
      await tester.tap(find.text('Alpha'));
      await tester.pump();
      expect(form.currentState!.validate(), true);
      await tester.pump();
      expect(find.text('Choose one'), findsNothing);
      form.currentState!.reset();
      await tester.pump();
      expect(value, isNull);
    },
  );
  testWidgets(
    'disabled group and item reject taps and expose radio semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();

      String? value;
      await tester.pumpWidget(
        host(
          DRadioGroup<String>(
            enabled: false,
            initialValue: 'a',
            onChanged: (v) => value = v,
            child: choices,
          ),
        ),
      );
      await tester.tap(find.text('Charlie'));
      await tester.pump();
      expect(value, isNull);
      expect(
        tester.getSemantics(find.byType(RawRadio<String>).first),
        matchesSemantics(
          hasCheckedState: true,
          isChecked: true,
          hasEnabledState: true,
          isEnabled: false,
          isInMutuallyExclusiveGroup: true,
          label: 'Alpha',
          textDirection: TextDirection.ltr,
        ),
      );
      semantics.dispose();
    },
  );
  testWidgets('live palette keeps selection and exact radio geometry', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    String? saved;
    var theme = ThemeData(
      platform: TargetPlatform.macOS,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
    );
    Widget build() => host(
      Form(
        key: form,
        child: DRadioGroup<String>(
          initialValue: 'a',
          onSaved: (value) => saved = value,
          child: choices,
        ),
      ),
      theme: theme,
    );
    await tester.pumpWidget(build());
    await tester.tap(find.text('Charlie'));
    await tester.pump();
    theme = ThemeData(
      platform: TargetPlatform.macOS,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.purple,
        brightness: Brightness.dark,
      ),
    );
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    form.currentState!.save();
    expect(saved, 'c');
    final circles = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
    );
    expect(circles, findsNWidgets(4));
    expect(
      circles
          .evaluate()
          .map((element) => tester.getSize(find.byWidget(element.widget)))
          .where((size) => size == const Size(16, 16))
          .length,
      3,
    );
    final selected = tester
        .widgetList<Container>(circles)
        .where(
          (widget) =>
              (widget.decoration! as BoxDecoration).color ==
              theme.colorScheme.primary,
        );
    expect(selected.length, 1);
    final dot = circles.evaluate().where(
      (element) =>
          tester.getSize(find.byWidget(element.widget)) == const Size(8, 8),
    );
    expect(dot.length, 1);
  });
  testWidgets(
    'radio focus blocks application reading shortcuts and Tab leaves group',
    (tester) async {
      final node = FocusNode();
      final after = FocusNode();
      addTearDown(node.dispose);
      addTearDown(after.dispose);
      late BuildContext reading;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) {
              reading = context;
              return Column(
                children: [
                  DRadioGroup<String>(
                    child: Column(
                      children: [
                        DRadioGroupItem(
                          value: 'a',
                          label: const Text('Alpha'),
                          focusNode: node,
                        ),
                        const DRadioGroupItem(value: 'b', label: Text('Beta')),
                      ],
                    ),
                  ),
                  TextButton(
                    focusNode: after,
                    onPressed: () {},
                    child: const Text('After'),
                  ),
                ],
              );
            },
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();
      expect(navigationShortcutsAllowed(reading), false);
      expect(navigationShortcutsAllowed(reading, activation: true), false);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(after.hasFocus, true);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('borrowed focus survives replacement and disposal', (
    tester,
  ) async {
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget build(FocusNode node) => host(
      DRadioGroup<String>(
        child: DRadioGroupItem(
          value: 'a',
          label: const Text('Alpha'),
          focusNode: node,
        ),
      ),
    );
    await tester.pumpWidget(build(first));
    await tester.pumpWidget(build(second));
    second.requestFocus();
    await tester.pump();
    expect(second.hasFocus, true);
    await tester.pumpWidget(const SizedBox());
    first.addListener(() {});
    second.addListener(() {});
  });
  testWidgets('all real examples fit narrow large-text RTL and touch bounds', (
    tester,
  ) async {
    for (final example in radioGroupExamples.examples) {
      await tester.pumpWidget(
        host(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SingleChildScrollView(
              child: SizedBox(
                width: 260,
                child: Builder(builder: example.builder),
              ),
            ),
          ),
          direction: TextDirection.rtl,
          theme: ThemeData(platform: TargetPlatform.iOS),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: example.title);
      for (final element in find.byType(RawRadio<String>).evaluate()) {
        expect(
          tester.getSize(find.byWidget(element.widget)).height,
          greaterThanOrEqualTo(48),
        );
      }
      await tester.pumpWidget(const SizedBox());
    }
  });
}
