import 'dart:ui' show ImageByteFormat, PointerDeviceKind, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    TargetPlatform platform = TargetPlatform.macOS,
    double width = 420,
    double scale = 1,
    bool rtl = false,
    bool reducedMotion = false,
    ThemeData? theme,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: (theme ?? AppTheme.light).copyWith(platform: platform),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(scale),
          disableAnimations: reducedMotion,
        ),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      ),
    ),
  );

  Widget tabs({
    String? initialValue = 'one',
    bool selectFirst = true,
    bool activateOnFocus = false,
    bool loopFocus = true,
    Axis orientation = Axis.horizontal,
    bool secondEnabled = true,
    ValueChanged<String?>? onChanged,
    ValueChanged<DTabChange<String>>? onSelectionChanged,
  }) => DTabs<String>(
    initialValue: initialValue,
    selectFirstOnMount: selectFirst,
    orientation: orientation,
    onChanged: onChanged,
    onSelectionChanged: onSelectionChanged,
    children: [
      DTabList<String>(
        activateOnFocus: activateOnFocus,
        loopFocus: loopFocus,
        children: [
          const DTabTrigger(value: 'one', child: Text('One')),
          DTabTrigger(
            value: 'two',
            enabled: secondEnabled,
            child: const Text('Two'),
          ),
          const DTabTrigger(value: 'three', child: Text('Three')),
        ],
      ),
      const DTabPanel(value: 'one', child: Text('Panel one')),
      const DTabPanel(value: 'two', child: Text('Panel two')),
      const DTabPanel(value: 'three', child: Text('Panel three')),
    ],
  );

  testWidgets(
    'matches compact default and line geometry on pointer platforms',
    (tester) async {
      await mount(tester, tabs());
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(DTabList<String>)).height, 32);
      expect(tester.getSize(find.byType(DTabTrigger<String>).first).height, 25);

      await mount(
        tester,
        const DTabs<String>(
          initialValue: 'one',
          children: [
            DTabList<String>(
              variant: DTabListVariant.line,
              children: [
                DTabTrigger(value: 'one', child: Text('One')),
                DTabTrigger(value: 'two', child: Text('Two')),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final first = tester.getRect(find.byType(DTabTrigger<String>).first);
      final second = tester.getRect(find.byType(DTabTrigger<String>).last);
      expect(second.left - first.right, 4);
    },
  );

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'keeps the underline visible while scrolling on ${platform.name} at ${scale}x text',
        (tester) async {
          final boundaryKey = GlobalKey();
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          await mount(
            tester,
            RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                height: 100,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: DTabs<String>(
                    initialValue: 'three',
                    children: [
                      DTabList<String>(
                        variant: DTabListVariant.line,
                        scrollController: scroll,
                        children: const [
                          DTabTrigger(value: 'one', child: Text('One')),
                          DTabTrigger(value: 'two', child: Text('Two')),
                          DTabTrigger(value: 'three', child: Text('Three')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            width: 150,
            scale: scale,
            platform: platform,
          );
          await tester.pumpAndSettle();
          scroll.jumpTo(scroll.position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(scroll.offset, greaterThan(0));

          final text = find.text('Three');
          final bounds = tester
              .getRect(text)
              .shift(-tester.getTopLeft(find.byKey(boundaryKey)));
          final foreground = DTokens.of(tester.element(text)).foreground;
          final visible = await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            try {
              final bytes = (await image.toByteData(
                format: ImageByteFormat.rawRgba,
              ))!;
              final x = bounds.center.dx.floor();
              for (
                var y = bounds.bottom.ceil() + 3;
                y < bounds.bottom.ceil() + 12;
                y++
              ) {
                final offset = (y * image.width + x) * 4;
                final pixel = Color.fromARGB(
                  bytes.getUint8(offset + 3),
                  bytes.getUint8(offset),
                  bytes.getUint8(offset + 1),
                  bytes.getUint8(offset + 2),
                );
                if (pixel == foreground) return true;
              }
              return false;
            } finally {
              image.dispose();
            }
          });
          expect(
            visible,
            isTrue,
            reason: 'The active underline must survive viewport clipping.',
          );
        },
      );
    }
  }

  testWidgets('uncontrolled pointer and semantics activation switch panels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final values = <String?>[];
    await mount(tester, tabs(onChanged: values.add));
    await tester.pumpAndSettle();
    expect(find.text('Panel one'), findsOneWidget);
    expect(find.text('Panel two'), findsNothing);

    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(values, ['two']);
    expect(find.text('Panel one'), findsNothing);
    expect(find.text('Panel two'), findsOneWidget);
    final data = tester
        .getSemantics(find.byType(DTabTrigger<String>).at(1))
        .getSemanticsData();
    expect(data.flagsCollection.isSelected, Tristate.isTrue);
    semantics.dispose();
  });

  testWidgets('disabled opacity applies to the complete trigger artwork', (
    tester,
  ) async {
    await mount(
      tester,
      const DTabs<String>.controlled(
        value: 'two',
        children: [
          DTabList<String>(
            children: [
              DTabTrigger(value: 'one', child: Text('One')),
              DTabTrigger(value: 'two', enabled: false, child: Text('Two')),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final disabled = find.byType(DTabTrigger<String>).last;
    final opacity = find.descendant(
      of: disabled,
      matching: find.byType(Opacity),
    );
    expect(opacity, findsOneWidget);
    expect(tester.widget<Opacity>(opacity).opacity, .5);
    final decoration =
        tester
                .widget<AnimatedContainer>(
                  find.descendant(
                    of: disabled,
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, isNot(Colors.transparent));
  });

  testWidgets('controlled selection waits for its parent', (tester) async {
    var value = 'one';
    var calls = 0;
    late StateSetter update;
    await mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return DTabs<String>.controlled(
            value: value,
            onChanged: (_) => calls++,
            children: const [
              DTabList<String>(
                children: [
                  DTabTrigger(value: 'one', child: Text('One')),
                  DTabTrigger(value: 'two', child: Text('Two')),
                ],
              ),
              DTabPanel(value: 'one', child: Text('Panel one')),
              DTabPanel(value: 'two', child: Text('Panel two')),
            ],
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Panel one'), findsOneWidget);
    update(() => value = 'two');
    await tester.pump();
    expect(find.text('Panel two'), findsOneWidget);
  });

  for (final variant in DTabListVariant.values) {
    for (final pointer in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
      testWidgets(
        '${variant.name} tabs show focus rings for keyboard input after $pointer clicks',
        (tester) async {
          final first = FocusNode();
          final second = FocusNode();
          final outside = FocusNode();
          addTearDown(first.dispose);
          addTearDown(second.dispose);
          addTearDown(outside.dispose);
          final boundaryKey = GlobalKey();
          await mount(
            tester,
            Column(
              children: [
                RepaintBoundary(
                  key: boundaryKey,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: DTabs<String>(
                      initialValue: 'one',
                      children: [
                        DTabList<String>(
                          variant: variant,
                          children: [
                            DTabTrigger(
                              value: 'one',
                              focusNode: first,
                              child: const Text('One'),
                            ),
                            DTabTrigger(
                              value: 'two',
                              focusNode: second,
                              child: const Text('Two'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                DButton(
                  focusNode: outside,
                  label: const Text('Outside'),
                  onPressed: () {},
                ),
              ],
            ),
            platform: pointer == PointerDeviceKind.mouse
                ? TargetPlatform.macOS
                : TargetPlatform.iOS,
          );
          await tester.pumpAndSettle();
          final ringColor = DTokens.of(
            tester.element(find.text('One')),
          ).focusRing.toARGB32();
          Future<bool> hasRing() async {
            await tester.pumpAndSettle();
            return (await tester.runAsync(() async {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              try {
                final bytes = (await image.toByteData(
                  format: ImageByteFormat.rawRgba,
                ))!;
                for (
                  var offset = 0;
                  offset < bytes.lengthInBytes;
                  offset += 4
                ) {
                  final pixel = Color.fromARGB(
                    bytes.getUint8(offset + 3),
                    bytes.getUint8(offset),
                    bytes.getUint8(offset + 1),
                    bytes.getUint8(offset + 2),
                  );
                  if (pixel.toARGB32() == ringColor) return true;
                }
                return false;
              } finally {
                image.dispose();
              }
            }))!;
          }

          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          expect(await hasRing(), isTrue);
          expect(first.hasPrimaryFocus, isTrue);

          await tester.tap(find.text('One'), kind: pointer);
          expect(await hasRing(), isFalse);
          expect(first.hasPrimaryFocus, isTrue);

          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          expect(await hasRing(), isTrue);
          expect(first.hasPrimaryFocus, isTrue);

          await tester.tap(find.text('Two'), kind: pointer);
          expect(await hasRing(), isFalse);
          expect(second.hasPrimaryFocus, isTrue);

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          expect(await hasRing(), isTrue);
          expect(first.hasPrimaryFocus, isTrue);

          await tester.tap(find.text('One'), kind: pointer);
          expect(await hasRing(), isFalse);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(outside.hasPrimaryFocus, isTrue);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          expect(await hasRing(), isTrue);
          expect(first.hasPrimaryFocus, isTrue);
        },
      );
    }
  }

  testWidgets('manual roving focus skips disabled and activates with Space', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await mount(
      tester,
      DTabs<String>(
        initialValue: 'one',
        children: [
          DTabList<String>(
            children: [
              DTabTrigger(
                value: 'one',
                focusNode: focus,
                child: const Text('One'),
              ),
              const DTabTrigger(
                value: 'two',
                enabled: false,
                child: Text('Two'),
              ),
              const DTabTrigger(value: 'three', child: Text('Three')),
            ],
          ),
          const DTabPanel(value: 'one', child: Text('Panel one')),
          const DTabPanel(value: 'three', child: Text('Panel three')),
        ],
      ),
    );
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Panel one'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Panel three'), findsOneWidget);
  });

  testWidgets(
    'Tab enters the selected trigger once and restores borrowed flags',
    (tester) async {
      final first = FocusNode();
      final second = FocusNode(skipTraversal: true);
      final outside = FocusNode();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      addTearDown(outside.dispose);
      await mount(
        tester,
        Column(
          children: [
            DTabs<String>(
              initialValue: 'one',
              children: [
                DTabList<String>(
                  children: [
                    DTabTrigger(
                      value: 'one',
                      focusNode: first,
                      child: const Text('One'),
                    ),
                    DTabTrigger(
                      value: 'two',
                      focusNode: second,
                      child: const Text('Two'),
                    ),
                  ],
                ),
              ],
            ),
            TextButton(
              focusNode: outside,
              onPressed: () {},
              child: const Text('Outside'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(first.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(outside.hasFocus, isTrue);
      await mount(tester, const SizedBox());
      expect(first.skipTraversal, isFalse);
      expect(second.skipTraversal, isTrue);
    },
  );

  testWidgets(
    'Tab enters an enabled trigger when controlled selection is unavailable',
    (tester) async {
      for (final value in <String?>[null, 'missing', 'two']) {
        final first = FocusNode();
        addTearDown(first.dispose);
        await mount(
          tester,
          DTabs<String>.controlled(
            value: value,
            children: [
              DTabList<String>(
                children: [
                  DTabTrigger(
                    value: 'one',
                    focusNode: first,
                    child: const Text('One'),
                  ),
                  const DTabTrigger(
                    value: 'two',
                    enabled: false,
                    child: Text('Two'),
                  ),
                  const DTabTrigger(value: 'three', child: Text('Three')),
                ],
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(first.hasFocus, isTrue, reason: 'controlled value $value');
        await mount(tester, const SizedBox());
      }
    },
  );

  testWidgets('manual roving focus remains the next Tab entry point', (
    tester,
  ) async {
    final first = FocusNode();
    final third = FocusNode();
    final outside = FocusNode();
    addTearDown(first.dispose);
    addTearDown(third.dispose);
    addTearDown(outside.dispose);
    late StateSetter rebuild;
    await mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return Column(
            children: [
              DTabs<String>(
                initialValue: 'one',
                children: [
                  DTabList<String>(
                    children: [
                      DTabTrigger(
                        value: 'one',
                        focusNode: first,
                        child: const Text('One'),
                      ),
                      const DTabTrigger(
                        value: 'two',
                        enabled: false,
                        child: Text('Two'),
                      ),
                      DTabTrigger(
                        value: 'three',
                        focusNode: third,
                        child: const Text('Three'),
                      ),
                    ],
                  ),
                ],
              ),
              TextButton(
                focusNode: outside,
                onPressed: () {},
                child: const Text('Outside'),
              ),
            ],
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    first.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(third.hasFocus, isTrue);
    expect(find.text('Panel three'), findsNothing);
    rebuild(() {});
    await tester.pumpAndSettle();

    outside.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(third.hasFocus, isTrue);
  });

  testWidgets('automatic focus activates, loops, and follows RTL', (
    tester,
  ) async {
    final first = FocusNode();
    addTearDown(first.dispose);
    await mount(
      tester,
      DTabs<String>(
        initialValue: 'one',
        children: [
          DTabList<String>(
            activateOnFocus: true,
            children: [
              DTabTrigger(
                value: 'one',
                focusNode: first,
                child: const Text('One'),
              ),
              const DTabTrigger(value: 'two', child: Text('Two')),
              const DTabTrigger(value: 'three', child: Text('Three')),
            ],
          ),
          const DTabPanel(value: 'one', child: Text('Panel one')),
          const DTabPanel(value: 'two', child: Text('Panel two')),
          const DTabPanel(value: 'three', child: Text('Panel three')),
        ],
      ),
      rtl: true,
    );
    await tester.pumpAndSettle();
    first.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Panel two'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(find.text('Panel three'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Panel one'), findsOneWidget);
  });

  testWidgets('vertical tabs use up and down but ignore horizontal arrows', (
    tester,
  ) async {
    await mount(
      tester,
      tabs(orientation: Axis.vertical, activateOnFocus: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('One'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Panel one'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('Panel two'), findsOneWidget);
  });

  testWidgets(
    'dynamic removal and disabling select the first enabled trigger',
    (tester) async {
      var includeTwo = true;
      var disableTwo = false;
      final changes = <DTabChange<String>>[];
      late StateSetter update;
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return DTabs<String>(
              initialValue: 'two',
              onSelectionChanged: changes.add,
              children: [
                DTabList<String>(
                  children: [
                    const DTabTrigger(value: 'one', child: Text('One')),
                    if (includeTwo)
                      DTabTrigger(
                        value: 'two',
                        enabled: !disableTwo,
                        child: const Text('Two'),
                      ),
                    const DTabTrigger(value: 'three', child: Text('Three')),
                  ],
                ),
                const DTabPanel(value: 'one', child: Text('Panel one')),
                const DTabPanel(value: 'two', child: Text('Panel two')),
              ],
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      update(() => disableTwo = true);
      await tester.pumpAndSettle();
      expect(changes.last.reason, DTabChangeReason.disabled);
      expect(changes.last.value, 'one');

      update(() {
        includeTwo = false;
        disableTwo = false;
      });
      await tester.pumpAndSettle();
      expect(find.text('Panel one'), findsOneWidget);
    },
  );

  testWidgets('missing dynamic selection reports missing fallback', (
    tester,
  ) async {
    var includeTwo = true;
    final changes = <DTabChange<String>>[];
    late StateSetter update;
    await mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return DTabs<String>(
            initialValue: 'two',
            onSelectionChanged: changes.add,
            children: [
              DTabList<String>(
                children: [
                  const DTabTrigger(value: 'one', child: Text('One')),
                  if (includeTwo)
                    const DTabTrigger(value: 'two', child: Text('Two')),
                ],
              ),
              const DTabPanel(value: 'one', child: Text('Panel one')),
              const DTabPanel(value: 'two', child: Text('Panel two')),
            ],
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    update(() => includeTwo = false);
    await tester.pumpAndSettle();
    expect(
      changes.last,
      const DTabChange(value: 'one', reason: DTabChangeReason.missing),
    );
  });

  testWidgets('maintainState retains editing while default panels unmount', (
    tester,
  ) async {
    await mount(
      tester,
      DTabs<String>(
        initialValue: 'one',
        children: [
          const DTabList<String>(
            children: [
              DTabTrigger(value: 'one', child: Text('One')),
              DTabTrigger(value: 'two', child: Text('Two')),
            ],
          ),
          DTabPanel(
            value: 'one',
            maintainState: true,
            child: DInput(key: const ValueKey('kept'), initialValue: 'draft'),
          ),
          DTabPanel(
            value: 'two',
            child: DInput(
              key: const ValueKey('dropped'),
              initialValue: 'fresh',
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('kept')),
        matching: find.byType(EditableText),
      ),
      'edited',
    );
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('kept')), findsNothing);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('dropped')),
        matching: find.byType(EditableText),
      ),
      'changed',
    );
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    expect(find.text('edited'), findsOneWidget);
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(find.text('fresh'), findsOneWidget);
  });

  testWidgets('focus in a hidden panel returns to its trigger', (tester) async {
    final fieldFocus = FocusNode();
    final firstTrigger = FocusNode();
    addTearDown(fieldFocus.dispose);
    addTearDown(firstTrigger.dispose);
    final controller = DTabController<String>('one');
    addTearDown(controller.dispose);
    await mount(
      tester,
      DTabs<String>(
        controller: controller,
        children: [
          DTabList<String>(
            children: [
              DTabTrigger(
                value: 'one',
                focusNode: firstTrigger,
                child: const Text('One'),
              ),
              const DTabTrigger(value: 'two', child: Text('Two')),
            ],
          ),
          DTabPanel(
            value: 'one',
            child: TextField(focusNode: fieldFocus),
          ),
          const DTabPanel(value: 'two', child: Text('Panel two')),
        ],
      ),
    );
    await tester.pumpAndSettle();
    fieldFocus.requestFocus();
    await tester.pump();
    controller.value = 'two';
    await tester.pumpAndSettle();
    expect(firstTrigger.hasFocus, isTrue);
  });

  testWidgets(
    'borrowed controller survives disposal without duplicate callbacks',
    (tester) async {
      final controller = DTabController<String>('one');
      addTearDown(controller.dispose);
      final changes = <DTabChange<String>>[];
      await mount(
        tester,
        DTabs<String>(
          controller: controller,
          onSelectionChanged: changes.add,
          children: const [
            DTabList<String>(
              children: [
                DTabTrigger(value: 'one', child: Text('One')),
                DTabTrigger(value: 'two', child: Text('Two')),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      expect(changes, [
        const DTabChange(value: 'two', reason: DTabChangeReason.user),
      ]);
      await mount(tester, const SizedBox());
      controller.value = 'one';
      expect(controller.value, 'one');
    },
  );

  testWidgets('borrowed controller clear stays empty until user selection', (
    tester,
  ) async {
    final controller = DTabController<String>('one');
    addTearDown(controller.dispose);
    await mount(
      tester,
      DTabs<String>(
        initialValue: 'ignored-while-controller-is-present',
        controller: controller,
        children: const [
          DTabList<String>(
            children: [
              DTabTrigger(value: 'one', child: Text('One')),
              DTabTrigger(value: 'two', child: Text('Two')),
            ],
          ),
          DTabPanel(value: 'one', child: Text('Panel one')),
          DTabPanel(value: 'two', child: Text('Panel two')),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Panel one'), findsOneWidget);

    controller.clear();
    await tester.pumpAndSettle();
    expect(controller.value, isNull);
    expect(find.text('Panel one'), findsNothing);
    expect(find.text('Panel two'), findsNothing);

    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(controller.value, 'two');
    expect(find.text('Panel two'), findsOneWidget);
  });

  testWidgets('narrow large-text lists scroll and touch targets are 48px', (
    tester,
  ) async {
    await mount(
      tester,
      tabs(),
      width: 120,
      scale: 2,
      reducedMotion: true,
      platform: TargetPlatform.iOS,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(DTabList<String>)).height,
      greaterThanOrEqualTo(48),
    );
    final triggerSize = tester.getSize(find.byType(DTabTrigger<String>).first);
    expect(triggerSize.width, greaterThanOrEqualTo(48));
    expect(triggerSize.height, greaterThanOrEqualTo(48));
    await tester.scrollUntilVisible(
      find.text('Three'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Three'));
    await tester.pumpAndSettle();
    expect(find.text('Panel three'), findsOneWidget);

    await mount(
      tester,
      tabs(orientation: Axis.vertical),
      width: 260,
      platform: TargetPlatform.iOS,
    );
    await tester.pumpAndSettle();
    for (final trigger in find.byType(DTabTrigger<String>).evaluate()) {
      final size = tester.getSize(find.byElementPredicate((e) => e == trigger));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('live tokens update active surface and radius', (tester) async {
    ThemeData theme = AppTheme.light;
    late StateSetter update;
    await mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return Theme(data: theme, child: tabs());
        },
      ),
    );
    await tester.pumpAndSettle();
    BoxDecoration decoration() =>
        (tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer).first)
                .decoration
            as BoxDecoration);
    final light = decoration();
    update(() => theme = AppTheme.dark);
    await tester.pumpAndSettle();
    final dark = decoration();
    expect(dark.color, isNot(light.color));
    expect(dark.borderRadius, light.borderRadius);
  });
}
