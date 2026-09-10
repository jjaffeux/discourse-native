import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reparented custom anchor re-registers without closing', (
    tester,
  ) async {
    final moved = ValueNotifier(false);
    addTearDown(moved.dispose);
    final anchor = DPopoverAnchor(
      key: GlobalKey(),
      child: const Text('Anchor'),
    );
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<bool>(
          valueListenable: moved,
          builder: (context, right, child) => DPopover(
            defaultOpen: true,
            content: const DPopoverContent(child: Text('Reparented content')),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 120, child: right ? null : anchor),
                SizedBox(width: 120, child: right ? anchor : null),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getRect(find.byType(DPopoverContent));
    moved.value = true;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Reparented content'), findsOneWidget);
    final after = tester.getRect(find.byType(DPopoverContent));
    expect(after.left, greaterThan(before.left + 100));
  });

  testWidgets('removing an open custom anchor avoids inactive layout reads', (
    tester,
  ) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, show, child) => DPopover(
            defaultOpen: true,
            content: const DPopoverContent(child: Text('Anchored content')),
            child: show
                ? const DPopoverAnchor(child: Text('Anchor'))
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Anchored content'), findsOneWidget);
    visible.value = false;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Anchored content'), findsNothing);
  });

  testWidgets('pressing inside a custom anchor does not dismiss its popover', (
    tester,
  ) async {
    final reasons = <DPopoverChangeReason>[];
    var presses = 0;
    await tester.pumpWidget(
      _app(
        DPopover(
          defaultOpen: true,
          onOpenChange: (_, reason) => reasons.add(reason),
          content: const DPopoverContent(child: Text('Anchored content')),
          child: DPopoverAnchor(
            child: DButton(
              label: const Text('Anchor action'),
              onPressed: () => presses += 1,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Anchor action'));
    await tester.pumpAndSettle();

    expect(presses, 1);
    expect(find.text('Anchored content'), findsOneWidget);
    expect(reasons, isNot(contains(DPopoverChangeReason.outsidePress)));
  });

  testWidgets(
    'uncontrolled trigger opens, focuses content, and Escape restores',
    (tester) async {
      await tester.pumpWidget(_app(const _TestPopover()));

      final trigger = tester.widget<DButton>(
        find.widgetWithText(DButton, 'Open'),
      );
      trigger.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Popover title'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Popover title'), findsNothing);
      expect(trigger.focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets('topmost popover owns Escape ahead of ancestor shortcuts', (
    tester,
  ) async {
    var ancestorEscapes = 0;
    await tester.pumpWidget(
      _app(
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              ancestorEscapes += 1;
            },
          },
          child: const _TestPopover(),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Popover title'), findsNothing);
    expect(ancestorEscapes, 0);
  });

  testWidgets('touch opening does not summon the nested text editor', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _TestPopover()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Popover title'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );
  });

  testWidgets('outside press and close composition report distinct reasons', (
    tester,
  ) async {
    final reasons = <DPopoverChangeReason>[];
    await tester.pumpWidget(_app(_TestPopover(onReason: reasons.add)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(reasons.last, DPopoverChangeReason.outsidePress);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(reasons.last, DPopoverChangeReason.closePress);
  });

  testWidgets('nested popover owns Escape and pointer interaction first', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _NestedPopoverTest()));
    await tester.tap(find.text('Open parent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open child'));
    await tester.pumpAndSettle();

    expect(find.text('Parent content'), findsOneWidget);
    expect(find.text('Child content'), findsOneWidget);
    await tester.tap(find.text('Use child'));
    await tester.pumpAndSettle();
    expect(find.text('Parent content'), findsOneWidget);
    expect(find.text('Child content'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Child content'), findsNothing);
    expect(find.text('Parent content'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Parent content'), findsNothing);
  });

  testWidgets('nested MenuAnchor dismisses before its parent popover', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _MenuPopoverTest()));
    await tester.tap(find.text('Open parent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();
    expect(find.text('Menu choice'), findsOneWidget);
    expect(find.text('Parent content'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Menu choice'), findsNothing);
    expect(find.text('Parent content'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);

    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();
    final parentRect = tester.getRect(find.byType(DPopoverContent));
    final secondChoiceRect = tester.getRect(find.text('Second choice'));
    expect(parentRect.overlaps(secondChoiceRect), isFalse);
    await tester.tap(find.text('Second choice'));
    await tester.pumpAndSettle();
    expect(find.text('Parent content'), findsOneWidget);
    expect(find.text('Selected: second'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Parent content'), findsNothing);
  });

  testWidgets('nested Select owns choices and Escape before parent', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _SelectPopoverTest()));
    await tester.tap(find.text('Open parent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('First choice'));
    await tester.pumpAndSettle();

    final parentRect = tester.getRect(find.byType(DPopoverContent).first);
    final outsideChoiceRect = tester.getRect(find.text('Outside choice'));
    expect(parentRect.overlaps(outsideChoiceRect), isFalse);

    await tester.tap(find.text('Outside choice'));
    await tester.pumpAndSettle();
    expect(find.text('Parent content'), findsOneWidget);
    expect(find.text('Outside choice'), findsOneWidget);

    await tester.tap(find.text('Outside choice'));
    await tester.pumpAndSettle();
    expect(find.text('First choice'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('First choice'), findsNothing);
    expect(find.text('Parent content'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Parent content'), findsNothing);
  });

  testWidgets('outside field keeps focus after pointer dismissal', (
    tester,
  ) async {
    final outsideFocus = FocusNode();
    addTearDown(outsideFocus.dispose);
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 700,
          height: 500,
          child: Stack(
            children: [
              const Align(
                alignment: Alignment.bottomCenter,
                child: _TestPopover(),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 260,
                  child: TextField(
                    focusNode: outsideFocus,
                    decoration: const InputDecoration(
                      labelText: 'Outside field',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextField, 'Outside field'));
    await tester.pumpAndSettle();

    expect(find.text('Popover title'), findsNothing);
    expect(outsideFocus.hasFocus, isTrue);
  });

  testWidgets('controlled state only changes when its owner accepts request', (
    tester,
  ) async {
    final open = ValueNotifier(false);
    final accept = ValueNotifier(false);
    addTearDown(open.dispose);
    addTearDown(accept.dispose);
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<bool>(
          valueListenable: accept,
          builder: (context, accepts, child) => ValueListenableBuilder<bool>(
            valueListenable: open,
            builder: (context, value, child) => _TestPopover(
              open: value,
              onOpen: (requested, reason) {
                if (accepts) open.value = requested;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Popover title'), findsNothing);

    accept.value = true;
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Popover title'), findsOneWidget);
  });

  testWidgets('controlled lifecycle dismissal reports and resynchronizes', (
    tester,
  ) async {
    final reasons = <DPopoverChangeReason>[];
    final controller = DPopoverController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        _TestPopover(open: true, controller: controller, onReason: reasons.add),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(controller.isOpen, isFalse);
    expect(reasons, contains(DPopoverChangeReason.lifecycle));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);
    expect(find.text('Popover title'), findsOneWidget);
  });

  testWidgets('controller is borrowed and ignores calls after detaching', (
    tester,
  ) async {
    final controller = DPopoverController();
    final mounted = ValueNotifier(true);
    addTearDown(() {
      mounted.dispose();
      controller.dispose();
    });
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<bool>(
          valueListenable: mounted,
          builder: (context, value, child) => value
              ? _TestPopover(controller: controller)
              : const Text('Removed'),
        ),
      ),
    );
    controller.open();
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);

    mounted.value = false;
    await tester.pumpAndSettle();
    controller.open();
    expect(controller.isOpen, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom start geometry uses 4px gap and logical RTL alignment', (
    tester,
  ) async {
    Future<void> verify(TextDirection direction) async {
      await tester.pumpWidget(
        _app(
          Directionality(
            key: ValueKey(direction),
            textDirection: direction,
            child: const Align(
              alignment: Alignment.center,
              child: _TestPopover(align: DPopoverAlign.start),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final trigger = tester.getRect(find.widgetWithText(DButton, 'Open'));
      final popup = tester.getRect(find.byType(DPopoverContent));
      expect(popup.top, closeTo(trigger.bottom + 4, 0.1));
      if (direction == TextDirection.ltr) {
        expect(popup.left, closeTo(trigger.left, 0.1));
      } else {
        expect(popup.right, closeTo(trigger.right, 0.1));
      }
    }

    await verify(TextDirection.ltr);
    await verify(TextDirection.rtl);
  });

  testWidgets('collision flips at an edge and constrains a narrow viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const SizedBox(
          width: 220,
          height: 180,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: _TestPopover(
              width: 288,
              collisionBoundary: Rect.fromLTWH(290, 210, 220, 180),
            ),
          ),
        ),
        size: const Size(220, 180),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final trigger = tester.getRect(find.widgetWithText(DButton, 'Open'));
    final popup = tester.getRect(find.byType(DPopoverContent));
    expect(popup.bottom, lessThanOrEqualTo(trigger.top - 4 + 0.1));
    expect(popup.left, greaterThanOrEqualTo(295));
    expect(popup.right, lessThanOrEqualTo(505));
  });

  testWidgets('custom placement receives geometry and remains collision-safe', (
    tester,
  ) async {
    DPopoverPlacement? placement;
    await tester.pumpWidget(
      _app(
        _TestPopover(
          placementResolver: (value) {
            placement = value;
            return const Offset(-1000, -1000);
          },
        ),
        size: const Size(320, 240),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(placement, isNotNull);
    expect(placement!.target, isNot(Rect.zero));
    expect(placement!.contentSize, isNot(Size.zero));
    expect(placement!.defaultOffset, isNot(const Offset(-1000, -1000)));
    expect(placement!.direction, TextDirection.ltr);
    final popup = tester.getRect(find.byType(DPopoverContent));
    expect(popup.left, greaterThanOrEqualTo(placement!.boundary.left));
    expect(popup.top, greaterThanOrEqualTo(placement!.boundary.top));
  });

  testWidgets('custom anchor moves while the open overlay tracks it', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _MovingAnchorTest()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final state = tester.state<_MovingAnchorTestState>(
      find.byType(_MovingAnchorTest),
    );
    expect(state._controller.isOpen, isTrue);
    expect(tester.takeException(), isNull);
    expect(find.byType(DPopoverContent, skipOffstage: false), findsOneWidget);
    final before = tester.getRect(find.byType(DPopoverContent));
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    final after = tester.getRect(find.byType(DPopoverContent));
    expect(after.left, greaterThan(before.left + 100));
  });

  testWidgets('surface keeps independent semantics and reads live theme', (
    tester,
  ) async {
    final dark = ValueNotifier(false);
    addTearDown(dark.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: dark,
        builder: (context, value, child) => MaterialApp(
          theme: value ? AppTheme.dark : AppTheme.light,
          home: const Scaffold(body: Center(child: _TestPopover())),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final semantics = tester.getSemantics(find.byType(DPopoverContent));
    expect(semantics.label, contains('Test popover'));
    expect(find.byType(TextField), findsOneWidget);
    final light = _surfaceDecoration(tester).color;

    dark.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Popover title'), findsOneWidget);
    expect(_surfaceDecoration(tester).color, isNot(light));
  });

  testWidgets('large text and reduced motion remain bounded', (tester) async {
    await tester.pumpWidget(
      _app(
        const MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: _TestPopover(width: 210),
        ),
        size: const Size(240, 400),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(find.text('Popover title'), findsOneWidget);
    expect(
      tester.getSize(find.byType(DPopoverContent)).width,
      lessThanOrEqualTo(230),
    );
    expect(tester.takeException(), isNull);
  });
}

BoxDecoration _surfaceDecoration(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(DPopoverContent),
        matching: find.byType(DecoratedBox),
      ),
    )
    .map((widget) => widget.decoration)
    .whereType<BoxDecoration>()
    .firstWhere((decoration) => decoration.boxShadow?.isNotEmpty == true);

Widget _app(Widget child, {Size size = const Size(800, 600)}) => MaterialApp(
  theme: AppTheme.light,
  home: MediaQuery(
    data: MediaQueryData(size: size),
    child: Scaffold(body: Center(child: child)),
  ),
);

class _TestPopover extends StatelessWidget {
  const _TestPopover({
    this.open,
    this.onOpen,
    this.onReason,
    this.controller,
    this.align = DPopoverAlign.center,
    this.width = 220,
    this.collisionBoundary,
    this.placementResolver,
  });

  final bool? open;
  final DPopoverOpenChange? onOpen;
  final ValueChanged<DPopoverChangeReason>? onReason;
  final DPopoverController? controller;
  final DPopoverAlign align;
  final double width;
  final Rect? collisionBoundary;
  final DPopoverPlacementResolver? placementResolver;

  @override
  Widget build(BuildContext context) => DPopover(
    open: open,
    controller: controller,
    onOpenChange: (value, reason) {
      onReason?.call(reason);
      onOpen?.call(value, reason);
    },
    content: DPopoverContent(
      width: width,
      align: align,
      collisionBoundary: collisionBoundary,
      placementResolver: placementResolver,
      semanticLabel: 'Test popover',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DPopoverHeader(
            children: [
              DPopoverTitle(child: Text('Popover title')),
              DPopoverDescription(child: Text('Description')),
            ],
          ),
          const TextField(decoration: InputDecoration(labelText: 'Width')),
          DPopoverClose(
            builder: (context, close) =>
                DButton(label: const Text('Close'), onPressed: close),
          ),
        ],
      ),
    ),
    child: DPopoverTrigger(
      builder: (context, trigger) => DButton(
        label: const Text('Open'),
        variant: DButtonVariant.outline,
        hasPopup: true,
        expanded: trigger.open,
        focusNode: trigger.focusNode,
        onPressed: trigger.toggle,
      ),
    ),
  );
}

class _NestedPopoverTest extends StatelessWidget {
  const _NestedPopoverTest();

  @override
  Widget build(BuildContext context) => DPopover(
    content: DPopoverContent(
      width: 240,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Parent content'),
          DPopover(
            content: DPopoverContent(
              width: 160,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Child content'),
                  DButton(label: const Text('Use child'), onPressed: () {}),
                ],
              ),
            ),
            child: DPopoverTrigger(
              builder: (context, trigger) => DButton(
                label: const Text('Open child'),
                focusNode: trigger.focusNode,
                hasPopup: true,
                expanded: trigger.open,
                onPressed: trigger.toggle,
              ),
            ),
          ),
        ],
      ),
    ),
    child: DPopoverTrigger(
      builder: (context, trigger) => DButton(
        label: const Text('Open parent'),
        focusNode: trigger.focusNode,
        hasPopup: true,
        expanded: trigger.open,
        onPressed: trigger.toggle,
      ),
    ),
  );
}

class _MenuPopoverTest extends StatefulWidget {
  const _MenuPopoverTest();

  @override
  State<_MenuPopoverTest> createState() => _MenuPopoverTestState();
}

class _MenuPopoverTestState extends State<_MenuPopoverTest> {
  String _selected = 'none';

  @override
  Widget build(BuildContext context) => DPopover(
    content: DPopoverContent(
      width: 220,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Parent content'),
          MenuAnchor(
            alignmentOffset: const Offset(180, 0),
            menuChildren: [
              MenuItemButton(
                onPressed: () => setState(() => _selected = 'first'),
                child: const Text('Menu choice'),
              ),
              MenuItemButton(
                onPressed: () => setState(() => _selected = 'second'),
                child: const Text('Second choice'),
              ),
            ],
            builder: (context, controller, child) => DButton(
              label: const Text('Open menu'),
              hasPopup: true,
              onPressed: controller.open,
            ),
          ),
          Text('Selected: $_selected'),
        ],
      ),
    ),
    child: DPopoverTrigger(
      builder: (context, trigger) => DButton(
        label: const Text('Open parent'),
        focusNode: trigger.focusNode,
        hasPopup: true,
        expanded: trigger.open,
        onPressed: trigger.toggle,
      ),
    ),
  );
}

class _SelectPopoverTest extends StatefulWidget {
  const _SelectPopoverTest();

  @override
  State<_SelectPopoverTest> createState() => _SelectPopoverTestState();
}

class _SelectPopoverTestState extends State<_SelectPopoverTest> {
  String _selected = 'first';

  @override
  Widget build(BuildContext context) => DPopover(
    content: DPopoverContent(
      width: 220,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Parent content'),
          DSelect<String>.controlled(
            value: _selected,
            entries: const [
              DSelectOption(
                value: null,
                label: 'Select an option',
                child: Text('Select an option'),
              ),
              DSelectOption(
                value: 'first',
                label: 'First choice',
                child: Text('First choice'),
              ),
              DSelectOption(
                value: 'outside',
                label: 'Outside choice',
                child: Text('Outside choice'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _selected = value);
            },
          ),
        ],
      ),
    ),
    child: DPopoverTrigger(
      builder: (context, trigger) => DButton(
        label: const Text('Open parent'),
        focusNode: trigger.focusNode,
        hasPopup: true,
        expanded: trigger.open,
        onPressed: trigger.toggle,
      ),
    ),
  );
}

class _MovingAnchorTest extends StatefulWidget {
  const _MovingAnchorTest();

  @override
  State<_MovingAnchorTest> createState() => _MovingAnchorTestState();
}

class _MovingAnchorTestState extends State<_MovingAnchorTest> {
  bool _right = false;
  final _controller = DPopoverController();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 600,
    height: 180,
    child: DPopover(
      controller: _controller,
      content: DPopoverContent(
        width: 140,
        side: DPopoverSide.bottom,
        align: DPopoverAlign.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Moving content'),
            DButton(
              label: const Text('Move'),
              onPressed: () => setState(() => _right = true),
            ),
          ],
        ),
      ),
      child: Stack(
        children: [
          Align(
            alignment: _right ? Alignment.topRight : Alignment.topLeft,
            child: const DPopoverAnchor(child: SizedBox.square(dimension: 20)),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: DPopoverTrigger(
              builder: (context, trigger) => DButton(
                label: const Text('Open'),
                focusNode: trigger.focusNode,
                onPressed: trigger.toggle,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
