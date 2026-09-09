import 'dart:ui' show SemanticsAction, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/toggle_group_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    ThemeData? theme,
    double scale = 1,
    bool reduced = false,
    TextDirection direction = TextDirection.ltr,
    double width = 320,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Center(
                child: SizedBox(width: width, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder toggle(String label) => find.bySemanticsLabel(label);
  Tristate toggled(WidgetTester tester, String label) => tester
      .getSemantics(toggle(label))
      .getSemanticsData()
      .flagsCollection
      .isToggled;

  testWidgets('single selection is controlled, ordered and clearable', (
    tester,
  ) async {
    var values = const ['a'];
    final changes = <List<String>>[];
    await mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) => DToggleGroup<String>(
          values: values,
          onChanged: (next) => setState(() {
            values = next;
            changes.add(next);
          }),
          items: const [
            DToggleGroupItem(
              value: 'a',
              semanticLabel: 'Alpha',
              child: Text('A'),
            ),
            DToggleGroupItem(
              value: 'b',
              semanticLabel: 'Beta',
              child: Text('B'),
            ),
            DToggleGroupItem(
              value: 'c',
              semanticLabel: 'Gamma',
              child: Text('C'),
            ),
          ],
        ),
      ),
    );

    expect(toggled(tester, 'Alpha'), Tristate.isTrue);
    await tester.tap(toggle('Beta'));
    await tester.pumpAndSettle();
    expect(changes, [
      ['b'],
    ]);
    expect(toggled(tester, 'Alpha'), Tristate.isFalse);
    expect(toggled(tester, 'Beta'), Tristate.isTrue);

    await tester.tap(toggle('Beta'));
    await tester.pumpAndSettle();
    expect(changes.last, isEmpty);
    expect(toggled(tester, 'Beta'), Tristate.isFalse);
  });

  testWidgets(
    'multiple uncontrolled selection toggles pointer keyboard and semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final changes = <List<String>>[];
      await mount(
        tester,
        DToggleGroup<String>(
          multiple: true,
          initialValues: const ['bold'],
          onChanged: changes.add,
          items: const [
            DToggleGroupItem(
              value: 'bold',
              semanticLabel: 'Bold',
              child: Text('Bold'),
            ),
            DToggleGroupItem(
              value: 'italic',
              semanticLabel: 'Italic',
              child: Text('Italic'),
            ),
            DToggleGroupItem(
              value: 'underline',
              semanticLabel: 'Underline',
              child: Text('Underline'),
            ),
          ],
        ),
      );

      await tester.tap(toggle('Italic'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      final underline = tester.getSemantics(toggle('Underline'));
      underline.owner!.performAction(underline.id, SemanticsAction.tap);
      await tester.pumpAndSettle();

      expect(changes, [
        ['bold', 'italic'],
        ['bold'],
        ['bold', 'underline'],
      ]);
      expect(toggled(tester, 'Bold'), Tristate.isTrue);
      expect(toggled(tester, 'Italic'), Tristate.isFalse);
      expect(toggled(tester, 'Underline'), Tristate.isTrue);
      semantics.dispose();
    },
  );

  testWidgets(
    'controller, disabled state and required selection preserve ownership',
    (tester) async {
      final controller = DToggleGroupController<String>(values: const ['list']);
      addTearDown(controller.dispose);
      final changes = <List<String>>[];
      await mount(
        tester,
        DToggleGroup<String>(
          controller: controller,
          onChanged: changes.add,
          allowEmptySelection: false,
          items: const [
            DToggleGroupItem(
              value: 'list',
              semanticLabel: 'List',
              child: Text('List'),
            ),
            DToggleGroupItem(
              value: 'grid',
              semanticLabel: 'Grid',
              enabled: false,
              child: Text('Grid'),
            ),
            DToggleGroupItem(
              value: 'cards',
              semanticLabel: 'Cards',
              child: Text('Cards'),
            ),
          ],
        ),
      );

      await tester.tap(toggle('List'));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      expect(controller.values, ['list']);

      controller.setValues(const ['cards']);
      await tester.pumpAndSettle();
      expect(toggled(tester, 'Cards'), Tristate.isTrue);

      await tester.tap(toggle('Grid'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(controller.values, ['cards']);
    },
  );

  testWidgets('arrow roving skips disabled items, loops and follows RTL', (
    tester,
  ) async {
    final first = FocusNode();
    final second = FocusNode();
    final third = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(third.dispose);
    await mount(
      tester,
      DToggleGroup<String>(
        initialValues: const ['a'],
        items: [
          DToggleGroupItem(
            value: 'a',
            semanticLabel: 'Alpha',
            focusNode: first,
            child: const Text('A'),
          ),
          DToggleGroupItem(
            value: 'b',
            semanticLabel: 'Beta',
            enabled: false,
            focusNode: second,
            child: const Text('B'),
          ),
          DToggleGroupItem(
            value: 'c',
            semanticLabel: 'Gamma',
            focusNode: third,
            child: const Text('C'),
          ),
        ],
      ),
      direction: TextDirection.rtl,
    );

    first.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(third.hasFocus, isTrue);
    expect(second.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(first.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(third.hasFocus, isTrue);
  });

  testWidgets(
    'dynamic items preserve the logical roving item and borrowed focus state',
    (tester) async {
      final alpha = FocusNode(skipTraversal: true);
      final beta = FocusNode();
      final gamma = FocusNode(skipTraversal: true);
      addTearDown(alpha.dispose);
      addTearDown(beta.dispose);
      addTearDown(gamma.dispose);
      late StateSetter rebuild;
      var values = const ['a', 'b', 'c'];

      await mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            final nodes = {'a': alpha, 'b': beta, 'c': gamma};
            return DToggleGroup<String>(
              items: [
                for (final value in values)
                  DToggleGroupItem(
                    value: value,
                    semanticLabel: value,
                    focusNode: nodes[value],
                    child: Text(value),
                  ),
              ],
            );
          },
        ),
      );

      beta.requestFocus();
      await tester.pump();
      expect(beta.skipTraversal, isFalse);

      rebuild(() => values = const ['c', 'b']);
      await tester.pump();
      expect(beta.hasFocus, isTrue);
      expect(beta.skipTraversal, isFalse);
      expect(gamma.skipTraversal, isTrue);
      expect(alpha.skipTraversal, isTrue);

      rebuild(() => values = const ['c']);
      await tester.pump();
      expect(beta.skipTraversal, isFalse);
      expect(gamma.skipTraversal, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(gamma.skipTraversal, isTrue);
    },
  );

  testWidgets(
    'connected outline geometry keeps outer logical radii and one shared seam',
    (tester) async {
      await mount(
        tester,
        const UnconstrainedBox(
          child: DToggleGroup<String>(
            initialValues: ['a'],
            variant: DToggleVariant.outline,
            spacing: 0,
            items: [
              DToggleGroupItem(
                value: 'a',
                semanticLabel: 'Alpha',
                child: Text('A'),
              ),
              DToggleGroupItem(
                value: 'b',
                semanticLabel: 'Beta',
                child: Text('B'),
              ),
              DToggleGroupItem(
                value: 'c',
                semanticLabel: 'Gamma',
                child: Text('C'),
              ),
            ],
          ),
        ),
      );

      final decorations = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((container) => container.decoration! as BoxDecoration)
          .toList();
      expect(decorations, hasLength(3));
      expect(decorations[0].borderRadius, isA<BorderRadius>());
      expect(decorations[1].borderRadius, BorderRadius.zero);
      expect((decorations[1].border! as Border).left, BorderSide.none);
      expect((decorations[2].border! as Border).left, BorderSide.none);
    },
  );

  testWidgets(
    'styleguide examples survive narrow RTL large text live palettes and reduced motion',
    (tester) async {
      expect(componentExamples['toggle-group'], same(toggleGroupExamples));
      expect(toggleGroupExamples.examples.map((example) => example.title), [
        'Default and composition',
        'Outline',
        'Size',
        'Spacing',
        'Vertical',
        'Disabled',
        'Custom font weight',
        'RTL',
        'Ownership and dynamic items',
      ]);
      for (final example in toggleGroupExamples.examples) {
        for (final theme in [
          AppTheme.light,
          AppTheme.dark,
          StyleguideTheme.forest.resolve(AppTheme.light),
        ]) {
          await mount(
            tester,
            SingleChildScrollView(child: Builder(builder: example.builder)),
            theme: theme.copyWith(platform: TargetPlatform.macOS),
            scale: 2,
            reduced: true,
            direction: TextDirection.rtl,
            width: 216,
          );
          await tester.pump();
          expect(tester.takeException(), isNull, reason: example.title);
          expect(
            tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer).first)
                .duration,
            Duration.zero,
            reason: example.title,
          );
        }
      }
    },
  );
}
