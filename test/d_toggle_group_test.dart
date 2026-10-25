import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/toggle_group_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets(
      'wrapped menu choices retain bounds and keyboard order in $direction',
      (tester) async {
        final changes = <List<String>>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: Directionality(textDirection: direction, child: child!),
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 220,
                  child: DToggleGroup<String>(
                    wrap: true,
                    density: DToggleDensity.menuFilter,
                    spacing: 1,
                    allowEmptySelection: false,
                    onChanged: changes.add,
                    items: const [
                      DToggleGroupItem(value: 'any', child: Text('Any')),
                      DToggleGroupItem(value: 'all', child: Text('All')),
                      DToggleGroupItem(value: 'none', child: Text('None')),
                      DToggleGroupItem(value: 'notAll', child: Text('Not all')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final group = find.byType(DToggleGroup<String>);
        final bounds = tester.getRect(group);
        final toggles = find.descendant(
          of: group,
          matching: find.byType(DToggle),
        );
        final rects = [
          for (var i = 0; i < 4; i++) tester.getRect(toggles.at(i)),
        ];
        expect(rects.map((rect) => rect.top).toSet().length, greaterThan(1));
        for (final rect in rects) {
          expect(rect.left, greaterThanOrEqualTo(bounds.left));
          expect(rect.right, lessThanOrEqualTo(bounds.right));
        }
        await tester.tap(find.text('Any'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pumpAndSettle();
        expect(
          tester.widget<DToggle>(toggles.last).focusNode!.hasFocus,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(changes.last, ['notAll']);
        expect(tester.widget<DToggle>(toggles.last).pressed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('compact inset keeps mockup artwork and mobile tap targets', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: const Scaffold(
          body: Center(
            child: DToggleGroup<bool>(
              inset: true,
              density: DToggleDensity.compactInset,

              allowEmptySelection: false,
              items: [
                DToggleGroupItem.iconOnly(
                  value: false,
                  semanticLabel: 'Comfortable',
                  icon: Icon(Icons.grid_view),
                ),
                DToggleGroupItem.iconOnly(
                  value: true,
                  semanticLabel: 'Compact',
                  icon: Icon(Icons.list),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final group = find.byType(DToggleGroup<bool>);
    final frame = find.byKey(const ValueKey('toggle-group-compact-frame'));
    final toggles = find.byType(DToggle);
    expect(tester.getSize(frame), const Size(68, 32));
    expect(tester.getSize(group), const Size(68, 32));
    for (final toggle in toggles.evaluate()) {
      expect(tester.getSize(find.byWidget(toggle.widget)), const Size(30, 26));
    }
    for (final artwork
        in find
            .descendant(of: group, matching: find.byType(AnimatedContainer))
            .evaluate()) {
      expect(tester.getSize(find.byWidget(artwork.widget)), const Size(30, 26));
    }

    await tester.tap(find.bySemanticsLabel('Comfortable'));
    await tester.pump();
    expect(tester.widget<DToggle>(toggles.first).pressed, isTrue);
    expect(tester.widget<DToggle>(toggles.last).pressed, isFalse);
  });

  testWidgets('expanded tiles fill their slots and retain keyboard selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: DToggleGroup<String>(
                density: DToggleDensity.tile,
                expanded: true,
                inset: true,
                allowEmptySelection: false,

                items: [
                  DToggleGroupItem(
                    value: 'None',
                    icon: Icon(Icons.crop_square),
                    child: Text('None'),
                  ),
                  DToggleGroupItem(
                    value: 'Paper',
                    icon: Icon(Icons.grain),
                    child: Text('Paper'),
                  ),
                  DToggleGroupItem(
                    value: 'Lava lamp',
                    icon: Icon(Icons.apps),
                    child: Text('Lava lamp'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final toggles = find.byType(DToggle);
    for (var i = 0; i < 3; i++) {
      final artwork = find.descendant(
        of: toggles.at(i),
        matching: find.byType(AnimatedContainer),
      );
      expect(
        tester.getSize(artwork).width,
        tester.getSize(toggles.at(i)).width,
      );
      expect(tester.getSize(artwork).height, greaterThanOrEqualTo(54));
    }
    final frame = find
        .descendant(
          of: find.byType(DToggleGroup<String>),
          matching: find.byType(DecoratedBox),
        )
        .first;
    final selectedArtwork = find.descendant(
      of: toggles.first,
      matching: find.byType(AnimatedContainer),
    );
    expect(
      tester.getSize(frame).height -
          tester.getSize(selectedArtwork.first).height,
      6,
    );
    await tester.tap(find.text('None'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(tester.widget<DToggle>(toggles.at(1)).pressed, isTrue);
    expect(tester.widget<DToggle>(toggles.at(0)).pressed, isFalse);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('multiple selection accepts taps before the scheduled rebuild', (
    tester,
  ) async {
    final changes = <List<String>>[];
    await mount(
      tester,
      DToggleGroup<String>(
        multiple: true,
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
        ],
      ),
    );

    await tester.tap(toggle('Bold'));
    await tester.tap(toggle('Italic'));
    await tester.tap(toggle('Bold'));
    await tester.pumpAndSettle();

    expect(changes, [
      ['bold'],
      ['bold', 'italic'],
      ['italic'],
    ]);
    expect(toggled(tester, 'Bold'), Tristate.isFalse);
    expect(toggled(tester, 'Italic'), Tristate.isTrue);
  });

  testWidgets(
    'connected outline geometry keeps outer logical radii and one shared seam',
    (tester) async {
      for (final direction in TextDirection.values) {
        await mount(
          tester,
          const UnconstrainedBox(
            child: DToggleGroup<String>(
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
          direction: direction,
        );

        final decorations = tester
            .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
            .map((container) => container.decoration! as BoxDecoration)
            .toList();
        final ltr = direction == TextDirection.ltr;
        const outer = Radius.circular(DRadius.control);
        BorderSide start(int index) {
          final border = decorations[index].border! as Border;
          return ltr ? border.left : border.right;
        }

        expect(decorations, hasLength(3));
        expect(
          decorations[0].borderRadius,
          ltr
              ? const BorderRadius.horizontal(left: outer)
              : const BorderRadius.horizontal(right: outer),
          reason: '$direction',
        );
        expect(decorations[1].borderRadius, BorderRadius.zero);
        expect(
          decorations[2].borderRadius,
          ltr
              ? const BorderRadius.horizontal(right: outer)
              : const BorderRadius.horizontal(left: outer),
          reason: '$direction',
        );
        expect(start(0), isNot(BorderSide.none), reason: '$direction');
        expect(start(1), BorderSide.none, reason: '$direction');
        expect(start(2), BorderSide.none, reason: '$direction');
      }
    },
  );

  testWidgets(
    'styleguide examples survive narrow RTL large text live palettes and reduced motion',
    (tester) async {
      expect(componentExamples['toggle-group'], same(toggleGroupExamples));
      expect(toggleGroupExamples.examples.map((example) => example.title), [
        'Wrapping menu choices',
        'Header menu filters',
        'Compact inset icon choices',
        'Appearance mode segments',
        'Texture tiles',
        'Inset layout selector',
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
      final custom = toggleGroupExamples.examples.singleWhere(
        (example) => example.title == 'Custom font weight',
      );
      await mount(tester, Builder(builder: custom.builder));
      expect(find.byType(DField), findsOneWidget);
      expect(find.byType(DFieldLabel), findsOneWidget);
      expect(find.byType(DFieldDescription), findsOneWidget);
      expect(find.byType(DFieldControl), findsNothing);
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
