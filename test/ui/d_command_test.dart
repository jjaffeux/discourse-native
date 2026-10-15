import 'dart:ui' show CheckedState;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Center(child: SizedBox(width: 384, child: child)),
        ),
      ),
    );

Widget _command({
  DCommandController<String>? controller,
  String? query,
  String? value,
  ValueChanged<String>? onQueryChanged,
  ValueChanged<String?>? onValueChanged,
  ValueChanged<String>? onSelected,
  bool shouldFilter = true,
  bool loop = false,
  bool loading = false,
  TextEditingController? editingController,
  FocusNode? inputFocus,
  VoidCallback? onEmptyBackspace,
  ScrollController? scrollController,
}) => DCommand<String>(
  controller: controller,
  query: query,
  value: value,
  onQueryChanged: onQueryChanged,
  onValueChanged: onValueChanged,
  onSelected: onSelected,

  shouldFilter: shouldFilter,
  loop: loop,
  loading: loading,

  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DCommandInput<String>(
        controller: editingController,
        focusNode: inputFocus,
        onEmptyBackspace: onEmptyBackspace,
      ),
      const DCommandList<String>(
        children: [
          DCommandLoading(child: Text('Loading results…')),
          DCommandEmpty(child: Text('No results found.')),
          DCommandGroup<String>(
            heading: Text('Suggestions'),
            items: [
              DCommandItem(
                value: 'Calendar',
                keywords: ['date', 'schedule'],
                child: Text('Calendar'),
              ),
              DCommandItem(
                value: 'Search Emoji',
                keywords: ['smile'],
                child: Text('Search Emoji'),
              ),
              DCommandItem(
                value: 'Calculator',
                enabled: false,
                child: Text('Calculator'),
              ),
            ],
          ),
          DCommandSeparator<String>(),
          DCommandGroup<String>(
            heading: Text('Settings'),
            items: [
              DCommandItem(value: 'Profile', child: Text('Profile')),
              DCommandItem(value: 'Billing', child: Text('Billing')),
              DCommandItem(value: 'Settings', child: Text('Settings')),
            ],
          ),
        ],
      ),
    ],
  ),
);

void main() {
  testWidgets('highlight work stays bounded in long command lists', (
    tester,
  ) async {
    final controller = DCommandController<String>();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        DCommand<String>(
          controller: controller,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DCommandInput<String>(),
              DCommandList<String>(
                children: [
                  for (var i = 0; i < 500; i++)
                    DCommandItem<String>(
                      value: 'Row $i',
                      child: Text('Row $i'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    var builds = 0;
    var listBuilds = 0;
    var inputBuilds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      builds++;
      if (element.widget is DCommandList<String>) listBuilds++;
      if (element.widget is DCommandInput<String>) inputBuilds++;
    };
    try {
      for (final value in ['Row 1', 'Row 2', 'Row 3']) {
        builds = 0;
        controller.highlight(value);
        await tester.pump();
        expect(controller.value, value);
        expect(
          builds,
          lessThan(200),
          reason: 'Only the old and new highlight should rebuild.',
        );
      }
      expect(listBuilds, 0);
      expect(inputBuilds, 0);
      expect(tester.takeException(), isNull);
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }
  });
  testWidgets(
    'inline command input leaves focus idle and retains IME and selection',
    (tester) async {
      final focus = FocusNode();
      final editing = TextEditingController();
      final command = DCommandController<String>();
      addTearDown(focus.dispose);
      addTearDown(editing.dispose);
      addTearDown(command.dispose);
      String? selected;
      await tester.pumpWidget(
        _host(
          DCommand<String>(
            controller: command,
            onSelected: (value) => selected = value,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DCommandInput<String>(
                  borderless: true,
                  autofocus: false,
                  focusNode: focus,
                  controller: editing,
                ),
                const DCommandList<String>(
                  children: [
                    DCommandItem(value: 'Calendar', child: Text('Calendar')),
                    DCommandItem(value: 'Profile', child: Text('Profile')),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      final input = tester.widget<DInput>(find.byType(DInput));
      expect(input.borderless, isTrue);
      expect(input.suffix, isNull);
      await tester.enterText(find.byType(EditableText), 'Cal');
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsNothing);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Cal',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 3),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(selected, isNull);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Cal',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(selected, 'Calendar');
    },
  );
  testWidgets(
    'empty Backspace leaves query state and focus with the caller',
    (tester) async {
      final editing = TextEditingController();
      final focus = FocusNode();
      final queries = <String>[];
      var deletes = 0;
      addTearDown(editing.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _host(
          _command(
            editingController: editing,
            inputFocus: focus,
            onQueryChanged: queries.add,
            onEmptyBackspace: () => deletes++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(editing.text, isEmpty);
      expect(queries, isEmpty);
      expect(focus.hasFocus, isTrue);

      final mobile =
          Theme.of(tester.element(find.byType(DInput))).platform !=
          TargetPlatform.macOS;
      // A soft keyboard deletes DInput's empty boundary through text input.
      if (mobile) {
        tester.testTextInput.updateEditingValue(TextEditingValue.empty);
        await tester.pumpAndSettle();
        expect(deletes, 2);
        expect(editing.text, isEmpty);
        expect(queries, isEmpty);
        expect(focus.hasFocus, isTrue);
      }

      final emptyDeletes = deletes;
      await tester.enterText(find.byType(EditableText), 'x');
      await tester.pumpAndSettle();
      if (mobile) {
        tester.testTextInput.updateEditingValue(TextEditingValue.empty);
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      }
      await tester.pumpAndSettle();
      expect(editing.text, isEmpty);
      expect(queries, ['x', '']);
      expect(deletes, emptyDeletes);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'external editor key routing retains focus and respects IME and detach',
    (tester) async {
      final controller = DCommandController<String>();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      String? selected;
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              TextField(focusNode: focus),
              _command(
                controller: controller,
                onSelected: (value) => selected = value,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      focus.requestFocus();
      await tester.pump();
      const down = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowDown,
        logicalKey: LogicalKeyboardKey.arrowDown,
        timeStamp: Duration.zero,
      );
      final initial = controller.value;
      expect(
        controller.handleKeyEvent(down, isComposing: true),
        KeyEventResult.ignored,
      );
      expect(controller.value, initial);
      expect(controller.handleKeyEvent(down), KeyEventResult.handled);
      expect(controller.value, isNot(initial));
      expect(focus.hasFocus, isTrue);
      controller.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.enter,
          logicalKey: LogicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
      );
      expect(selected, controller.value);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.handleKeyEvent(down), KeyEventResult.ignored);
    },
  );

  test(
    'detached controller retains imperative query and highlight updates',
    () {
      final controller = DCommandController<String>();
      addTearDown(controller.dispose);

      controller.updateQuery('profile');
      controller.highlight('Profile');

      expect(controller.query, 'profile');
      expect(controller.value, 'Profile');
    },
  );

  testWidgets('filters by values and keyword aliases and exposes empty state', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_command()));
    await tester.pump();
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('No results found.'), findsNothing);

    await tester.enterText(find.byType(TextField), 'schedule');
    await tester.pump();
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Search Emoji'), findsNothing);

    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump();
    expect(find.text('Calendar'), findsNothing);
    expect(find.text('No results found.'), findsOneWidget);
    expect(find.text('Suggestions'), findsNothing);
  });

  testWidgets(
    'IME composition suppresses command keys until native editing commits',
    (tester) async {
      final controller = DCommandController<String>();
      final focus = FocusNode();
      final editing = TextEditingController();
      final selected = <String>[];
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      addTearDown(editing.dispose);
      await tester.pumpWidget(
        _host(
          _command(
            controller: controller,
            loop: true,
            inputFocus: focus,
            editingController: editing,
            onSelected: selected.add,
          ),
        ),
      );
      await tester.pump();
      focus.requestFocus();
      editing.value = const TextEditingValue(
        text: 'e',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      );
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      final initialHighlight = controller.value;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(editing.value.composing, const TextRange(start: 0, end: 1));
      expect(controller.value, initialHighlight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, isEmpty);

      editing.value = editing.value.copyWith(composing: TextRange.empty);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.value, isNot(initialHighlight));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, hasLength(1));
      expect(find.text(selected.single), findsOneWidget);
    },
  );

  testWidgets(
    'selection and composing-only edits do not report query changes',
    (tester) async {
      final editing = TextEditingController();
      final queries = <String>[];
      addTearDown(editing.dispose);
      await tester.pumpWidget(
        _host(
          _command(editingController: editing, onQueryChanged: queries.add),
        ),
      );
      await tester.pump();
      editing.text = 'calendar';
      await tester.pump();
      queries.clear();

      editing.selection = const TextSelection.collapsed(offset: 2);
      editing.value = editing.value.copyWith(
        composing: const TextRange(start: 0, end: 2),
      );
      await tester.pump();

      expect(queries, isEmpty);
    },
  );

  testWidgets('Ctrl bindings skip disabled rows without moving editor focus', (
    tester,
  ) async {
    final controller = DCommandController<String>();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _host(_command(controller: controller, inputFocus: focus, loop: true)),
    );
    await tester.pump();
    focus.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(controller.value, 'Search Emoji');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    expect(controller.value, 'Profile');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(controller.value, 'Search Emoji');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.value, 'Calendar');
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('Home, End, Meta-arrow, and Alt-arrow navigate like cmdk', (
    tester,
  ) async {
    final controller = DCommandController<String>();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _host(_command(controller: controller, inputFocus: focus)),
    );
    await tester.pump();
    focus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(controller.value, 'Settings');
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(controller.value, 'Calendar');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(controller.value, 'Settings');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(controller.value, 'Calendar');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(controller.value, 'Profile');
  });

  testWidgets('a fixed height holds while results change and centres states', (
    tester,
  ) async {
    final controller = DCommandController<String>();
    final editing = TextEditingController();
    var loading = false;
    late StateSetter setLoading;
    addTearDown(controller.dispose);
    addTearDown(editing.dispose);
    final list = find.byKey(const ValueKey('fixed-list'));
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            setLoading = setState;
            return DCommand<String>(
              controller: controller,
              loading: loading,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DCommandInput<String>(controller: editing),
                  DCommandList<String>(
                    key: const ValueKey('fixed-list'),
                    height: 200,
                    children: [
                      const DCommandLoading(child: Text('Loading results…')),
                      const DCommandEmpty(child: Text('No results found.')),
                      DCommandGroup<String>(
                        items: [
                          for (final value in ['Calendar', 'Calculator'])
                            DCommandItem(value: value, child: Text(value)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    final bounds = tester.getRect(list);
    expect(bounds.height, 200);
    expect(
      tester.getTopLeft(find.text('Calendar')).dy - bounds.top,
      lessThan(bounds.height / 4),
    );

    for (final query in ['Calen', 'zzz']) {
      await tester.enterText(find.byType(EditableText), query);
      await tester.pump();
      expect(tester.getRect(list), bounds, reason: query);
    }
    expect(
      tester.getCenter(find.text('No results found.')).dy,
      moreOrLessEquals(bounds.center.dy, epsilon: 1),
    );

    setLoading(() => loading = true);
    await tester.pump();
    expect(tester.getRect(list), bounds);
    expect(
      tester.getCenter(find.text('Loading results…')).dy,
      moreOrLessEquals(bounds.center.dy, epsilon: 1),
    );
  });

  testWidgets('disabled rows are skipped by keyboard and cannot be tapped', (
    tester,
  ) async {
    final controller = DCommandController<String>(initialValue: 'Search Emoji');
    final selected = <String>[];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(_command(controller: controller, onSelected: selected.add)),
    );
    await tester.pump();
    controller.activate('Calculator');
    expect(selected, isEmpty);
    await tester.tap(find.text('Calculator'));
    await tester.pump();
    expect(selected, isEmpty);
  });

  testWidgets('dynamic results retire disabled and removed highlights', (
    tester,
  ) async {
    final controller = DCommandController<String>(initialValue: 'Calendar');
    var calendarEnabled = true;
    var showProfile = true;
    late StateSetter rebuild;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return DCommand<String>(
              controller: controller,
              child: DCommandList<String>(
                children: [
                  DCommandItem(
                    value: 'Calendar',
                    enabled: calendarEnabled,
                    child: const Text('Calendar'),
                  ),
                  if (showProfile)
                    const DCommandItem(
                      value: 'Profile',
                      child: Text('Profile'),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(controller.value, 'Calendar');

    rebuild(() => calendarEnabled = false);
    await tester.pump();
    await tester.pump();
    expect(controller.value, 'Profile');

    rebuild(() => showProfile = false);
    await tester.pump();
    await tester.pump();
    expect(controller.value, isNull);
  });

  testWidgets('input and custom item labels reach semantics', (tester) async {
    await tester.pumpWidget(
      _host(
        const DCommand<String>(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DCommandInput<String>(semanticLabel: 'Find an action'),
              DCommandList<String>(
                children: [
                  DCommandItem(
                    value: 'Profile',
                    semanticLabel: 'Open your profile',
                    child: Text('Profile'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final inputSemantics = find.ancestor(
      of: find.byType(TextField),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Find an action',
      ),
    );
    expect(inputSemantics, findsOneWidget);
    final inputData = tester.getSemantics(inputSemantics).getSemanticsData();
    expect(inputData.flagsCollection.isTextField, isTrue);
    expect(find.bySemanticsLabel('Open your profile'), findsOneWidget);
  });

  testWidgets('disabled rows use one half-opacity treatment', (tester) async {
    await tester.pumpWidget(_host(_command()));
    await tester.pump();

    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Calculator'),
    );
    final opacities = tester
        .widgetList<Opacity>(
          find.ancestor(
            of: find.text('Calculator'),
            matching: find.byType(Opacity),
          ),
        )
        .map((widget) => widget.opacity);
    expect(paragraph.text.style?.color?.a, 1);
    expect(opacities, contains(.5));
  });

  testWidgets('selected shortcuts use foreground color', (tester) async {
    final controller = DCommandController<String>(initialValue: 'Profile');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        DCommand<String>(
          controller: controller,
          child: const DCommandList<String>(
            children: [
              DCommandItem(
                value: 'Profile',
                trailing: DCommandShortcut(Text('⌘P')),
                child: Text('Profile'),
              ),
              DCommandItem(
                value: 'Billing',
                trailing: DCommandShortcut(Text('⌘B')),
                child: Text('Billing'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final tokens = DTokens.of(tester.element(find.byType(DCommand<String>)));

    expect(
      DefaultTextStyle.of(tester.element(find.text('⌘P'))).style.color,
      tokens.foreground,
    );
    expect(
      DefaultTextStyle.of(tester.element(find.text('⌘B'))).style.color,
      tokens.mutedForeground,
    );
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets('keyboard selection holds until the pointer moves again', (
    tester,
  ) async {
    final controller = DCommandController<String>();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(_command(controller: controller)));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Profile')));
    await tester.pumpAndSettle();
    expect(controller.value, 'Profile');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.value, 'Billing');
    await mouse.moveTo(
      tester.getCenter(find.text('Profile')) + const Offset(1, 0),
    );
    await tester.pumpAndSettle();
    expect(controller.value, 'Profile');
    await mouse.removePointer();
  });

  testWidgets('checked state is semantic and touch rows are 48 pixels', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Theme(
          data: ThemeData(platform: TargetPlatform.iOS),
          child: const DCommand<String>(
            child: DCommandList<String>(
              children: [
                DCommandItem(
                  value: 'Settings',
                  checked: true,
                  child: Text('Settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final checkedSemantics = find.ancestor(
      of: find.text('Settings'),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.checked == true,
      ),
    );
    expect(checkedSemantics, findsOneWidget);
    final data = tester.getSemantics(checkedSemantics).getSemanticsData();
    expect(data.flagsCollection.isChecked, CheckedState.isTrue);
    expect(tester.getSize(checkedSemantics).height, 32);
  });

  testWidgets('Return activates an individually focused row', (tester) async {
    final controller = DCommandController<String>(initialValue: 'Calendar');
    final selected = <String>[];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        DCommand<String>(
          controller: controller,
          onSelected: selected.add,
          child: const DCommandList<String>(
            children: [
              DCommandItem(value: 'Calendar', child: Text('Calendar')),
              DCommandItem(value: 'Profile', child: Text('Profile')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    Focus.of(tester.element(find.text('Profile'))).requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(selected, ['Profile']);
  });

  testWidgets(
    'controlled query and value report changes without losing state',
    (tester) async {
      final queries = <String>[];
      final values = <String?>[];
      await tester.pumpWidget(
        _host(
          _command(
            query: '',
            value: 'Calendar',
            onQueryChanged: queries.add,
            onValueChanged: values.add,
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'profile');
      await tester.pump();
      expect(queries.last, 'profile');
      expect(find.text('Profile'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(values, isNotEmpty);
    },
  );

  testWidgets('loading, scrolling, borrowed resources and RTL remain live', (
    tester,
  ) async {
    final command = DCommandController<String>();
    final editing = TextEditingController();
    final focus = FocusNode();
    final scroll = ScrollController();
    await tester.pumpWidget(
      _host(
        _command(
          controller: command,
          editingController: editing,
          inputFocus: focus,
          scrollController: scroll,
          loading: true,
        ),
        direction: TextDirection.rtl,
      ),
    );
    await tester.pump();
    expect(find.text('Loading results…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(() => command.updateQuery('safe'), returnsNormally);
    expect(() => editing.text = 'safe', returnsNormally);
    expect(() => focus.requestFocus(), returnsNormally);
    expect(scroll.hasClients, isFalse);
    command.dispose();
    editing.dispose();
    focus.dispose();
    scroll.dispose();
  });

  testWidgets(
    'dialog selection returns result and Escape restores trigger focus',
    (tester) async {
      final trigger = FocusNode();
      final dialog = DDialogController<String>();
      addTearDown(trigger.dispose);
      addTearDown(dialog.dispose);
      await tester.pumpWidget(
        _host(
          DCommandDialog<String>(
            controller: dialog,
            finalFocusNode: trigger,
            trigger: DDialogTrigger(
              builder: (context, open) => DButton(
                focusNode: trigger,
                onPressed: open,
                label: const Text('Open Menu'),
              ),
            ),
            command: DCommand<String>(
              onSelected: dialog.close,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DCommandInput<String>(),
                  DCommandList<String>(
                    children: [
                      DCommandGroup<String>(
                        items: [
                          DCommandItem(
                            value: 'Profile',
                            child: Text('Profile'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, isNot(trigger));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsNothing);
      expect(trigger.hasFocus, isTrue);
    },
  );
}
