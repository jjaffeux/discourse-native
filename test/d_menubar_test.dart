import 'dart:ui' show CheckedState, PointerDeviceKind, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('matches compact root geometry and opens a command menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _TestApp(platform: TargetPlatform.macOS, child: _BasicMenubar()),
    );

    expect(tester.getSize(find.byType(DMenubar)).height, 34);
    expect(find.text('New Tab'), findsNothing);

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    expect(find.text('New Tab'), findsOneWidget);
    expect(find.text('New Window'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byType(DMenubarTrigger).first)
          .flagsCollection
          .isExpanded,
      Tristate.isTrue,
    );
  });

  testWidgets('retains accessible touch trigger bounds on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(const _TestApp(child: _BasicMenubar()));

      final triggerSize = tester.getSize(find.byType(DMenubarTrigger).first);
      expect(triggerSize.width, greaterThanOrEqualTo(DSpacing.touchTarget));
      expect(triggerSize.height, greaterThanOrEqualTo(DSpacing.touchTarget));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('arrows rove triggers and switch an open menu', (tester) async {
    await tester.pumpWidget(const _TestApp(child: _BasicMenubar()));

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('New Tab'), findsNothing);
    expect(
      tester
          .getSemantics(find.byType(DMenubarTrigger).at(1))
          .flagsCollection
          .isExpanded,
      Tristate.isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('New Tab'), findsOneWidget);
  });

  testWidgets('pointer hover switches the active top-level menu', (
    tester,
  ) async {
    await tester.pumpWidget(const _TestApp(child: _BasicMenubar()));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.text('File')));
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    await mouse.moveTo(tester.getCenter(find.text('Edit')));
    await tester.pumpAndSettle();

    expect(find.text('New Tab'), findsNothing);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('triggers and menu rows use the visible menu hover surface', (
    tester,
  ) async {
    const menuHover = Color(0xFF444444);
    final tokens = _tokens(
      const Color(0xFF313131),
    ).copyWith(hover: const Color(0xFF313131));
    await tester.pumpWidget(
      _TestApp(
        tokens: tokens,
        hoverColor: menuHover,
        child: const DMenubar(
          children: [
            DMenubarMenu(
              trigger: DMenubarTrigger(child: Text('File')),
              content: DMenubarContent(
                children: [
                  DMenubarItem(onPressed: _noop, child: Text('New Tab')),
                  DMenubarItem(onPressed: _noop, child: Text('New Window')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.text('New Window')));
    await tester.pump();

    final trigger = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(DMenubarTrigger).first,
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect((trigger.decoration as BoxDecoration).color, menuHover);
    final rowColors = tester
        .widgetList<Container>(
          find.ancestor(
            of: find.text('New Window'),
            matching: find.byType(Container),
          ),
        )
        .map((widget) => (widget.decoration as BoxDecoration?)?.color);
    expect(rowColors, contains(menuHover));
  });

  testWidgets('Home End and RTL use logical top-level navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _TestApp(textDirection: TextDirection.rtl, child: _BasicMenubar()),
    );

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('Andy'), findsOneWidget);
  });

  testWidgets('Home and End stay within an open command menu', (tester) async {
    await tester.pumpWidget(const _TestApp(child: _BasicMenubar()));

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('Print'));
    expect(find.text('New Tab'), findsOneWidget);
    expect(find.text('Andy'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('New Tab'));
  });

  testWidgets('vertical open menus retain command arrow navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _TestApp(
        child: DMenubar(
          orientation: Axis.vertical,
          children: [
            DMenubarMenu(
              trigger: DMenubarTrigger(child: Text('File')),
              content: DMenubarContent(
                children: [
                  DMenubarItem(onPressed: _noop, child: Text('New')),
                  DMenubarItem(onPressed: _noop, child: Text('Open')),
                ],
              ),
            ),
            DMenubarMenu(
              trigger: DMenubarTrigger(child: Text('Edit')),
              content: DMenubarContent(
                children: [DMenubarItem(child: Text('Undo'))],
              ),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('Open'));
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('checkbox and radio state remain open and update', (
    tester,
  ) async {
    await tester.pumpWidget(const _TestApp(child: _StatefulMenubar()));

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bookmarks Bar'));
    await tester.pumpAndSettle();
    expect(find.text('Bookmarks Bar'), findsOneWidget);
    expect(find.text('bookmarks:on'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profiles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Andy'));
    await tester.pumpAndSettle();
    expect(find.text('Andy'), findsOneWidget);
    expect(find.text('profile:andy'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Andy')).flagsCollection.isChecked,
      CheckedState.isTrue,
    );
  });

  testWidgets('submenu opens and deepest Escape restores its trigger', (
    tester,
  ) async {
    await tester.pumpWidget(const _TestApp(child: _BasicMenubar()));

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(find.text('Email link'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Email link'), findsNothing);
    expect(find.text('New Tab'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('New Tab'), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Menubar trigger');
  });

  testWidgets('typeahead skips disabled items and actions close the chain', (
    tester,
  ) async {
    var selected = '';
    await tester.pumpWidget(
      _TestApp(child: _BasicMenubar(onSelected: (value) => selected = value)),
    );

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected, 'Print');
    expect(find.text('New Tab'), findsNothing);
  });

  testWidgets('disabled roots do not open and expose disabled semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _TestApp(
        child: DMenubar(
          disabled: true,
          children: [
            DMenubarMenu(
              trigger: DMenubarTrigger(child: Text('File')),
              content: DMenubarContent(
                children: [DMenubarItem(child: Text('New Tab'))],
              ),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(find.text('New Tab'), findsNothing);
    expect(
      tester
          .getSemantics(find.byType(DMenubarTrigger))
          .flagsCollection
          .isEnabled,
      Tristate.isFalse,
    );
  });

  testWidgets('re-enabled roots restore a keyboard entry point', (
    tester,
  ) async {
    const menu = DMenubar(
      disabled: true,
      children: [
        DMenubarMenu(
          trigger: DMenubarTrigger(child: Text('File')),
          content: DMenubarContent(
            children: [DMenubarItem(child: Text('New Tab'))],
          ),
        ),
      ],
    );
    await tester.pumpWidget(const _TestApp(child: menu));
    await tester.pumpWidget(
      const _TestApp(
        child: DMenubar(
          children: [
            DMenubarMenu(
              trigger: DMenubarTrigger(child: Text('File')),
              content: DMenubarContent(
                children: [DMenubarItem(child: Text('New Tab'))],
              ),
            ),
          ],
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Menubar trigger');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(find.text('New Tab'), findsOneWidget);
  });

  testWidgets('a newly enabled menu becomes the roving focus entry point', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _TestApp(
        child: DMenubar(
          children: [
            DMenubarMenu(
              enabled: false,
              trigger: DMenubarTrigger(child: Text('File')),
              content: DMenubarContent(
                children: [DMenubarItem(child: Text('New Tab'))],
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      const _TestApp(
        child: DMenubar(
          children: [
            DMenubarMenu(
              trigger: DMenubarTrigger(child: Text('File')),
              content: DMenubarContent(
                children: [DMenubarItem(child: Text('New Tab'))],
              ),
            ),
          ],
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Menubar trigger');
  });

  testWidgets(
    'default-open and borrowed controllers coordinate sibling menus',
    (tester) async {
      final controller = DMenubarMenuController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _TestApp(
          child: DMenubar(
            children: [
              const DMenubarMenu(
                defaultOpen: true,
                trigger: DMenubarTrigger(child: Text('File')),
                content: DMenubarContent(
                  children: [DMenubarItem(child: Text('New Tab'))],
                ),
              ),
              DMenubarMenu(
                controller: controller,
                trigger: const DMenubarTrigger(child: Text('Edit')),
                content: const DMenubarContent(
                  children: [DMenubarItem(child: Text('Undo'))],
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('New Tab'), findsOneWidget);

      controller.open();
      await tester.pumpAndSettle();
      expect(find.text('New Tab'), findsNothing);
      expect(find.text('Undo'), findsOneWidget);
    },
  );

  testWidgets('controlled open state coordinates through the parent', (
    tester,
  ) async {
    final key = GlobalKey<_ControlledMenubarState>();
    await tester.pumpWidget(_TestApp(child: _ControlledMenubar(key: key)));

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(find.text('New Tab'), findsOneWidget);

    key.currentState!.open('edit');
    await tester.pumpAndSettle();
    expect(find.text('New Tab'), findsNothing);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('borrowed controller remains usable after menu disposal', (
    tester,
  ) async {
    final controller = DMenubarMenuController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _TestApp(
        child: DMenubar(
          children: [
            DMenubarMenu(
              controller: controller,
              trigger: const DMenubarTrigger(child: Text('File')),
              content: const DMenubarContent(
                children: [DMenubarItem(child: Text('New Tab'))],
              ),
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(const _TestApp(child: SizedBox.shrink()));
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.open();
    expect(notifications, 0);
  });

  testWidgets('open overlays follow live tokens and tolerate 200% narrow RTL', (
    tester,
  ) async {
    final tokens = ValueNotifier(_tokens(Colors.red));
    addTearDown(tokens.dispose);
    await tester.binding.setSurfaceSize(const Size(260, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ValueListenableBuilder<DTokens>(
        valueListenable: tokens,
        builder: (_, value, _) => _TestApp(
          tokens: value,
          textDirection: TextDirection.rtl,
          textScaler: const TextScaler.linear(2),
          disableAnimations: true,
          child: const _BasicMenubar(),
        ),
      ),
    );

    await tester.tap(find.text('File'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color == Colors.red,
      ),
      findsOneWidget,
    );

    tokens.value = _tokens(Colors.blue);
    await tester.pumpAndSettle();
    expect(find.text('New Tab'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color == Colors.blue,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.child,
    this.tokens,
    this.platform,
    this.hoverColor,
    this.textDirection = TextDirection.ltr,
    this.textScaler = TextScaler.noScaling,
    this.disableAnimations = false,
  });

  final Widget child;
  final DTokens? tokens;
  final TargetPlatform? platform;
  final Color? hoverColor;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData.light().copyWith(
      platform: platform,
      hoverColor: hoverColor,
      extensions: [tokens ?? _tokens(Colors.white)],
    ),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(800, 600),
        textScaler: textScaler,
        disableAnimations: disableAnimations,
      ),
      child: Directionality(
        textDirection: textDirection,
        child: Scaffold(
          body: Align(alignment: Alignment.topCenter, child: child),
        ),
      ),
    ),
  );
}

DTokens _tokens(Color surface) => DTokens(
  colors: ColorScheme.fromSeed(seedColor: Colors.indigo),
  background: Colors.white,
  surface: surface,
  muted: Colors.grey.shade100,
  border: Colors.grey.shade300,
  hover: Colors.grey.shade200,
  selected: Colors.grey.shade300,
  selectedForeground: Colors.black,
  radius: 10,
);

class _BasicMenubar extends StatelessWidget {
  const _BasicMenubar({this.onSelected});
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) => DMenubar(
    children: [
      DMenubarMenu(
        trigger: const DMenubarTrigger(child: Text('File')),
        content: DMenubarContent(
          children: [
            DMenubarGroup(
              children: [
                DMenubarItem(
                  onPressed: onSelected == null
                      ? () {}
                      : () => onSelected!('New'),
                  trailing: const DMenubarShortcut('⌘T'),
                  child: const Text('New Tab'),
                ),
                const DMenubarItem(child: Text('New Window')),
                const DMenubarItem(child: Text('New Incognito Window')),
              ],
            ),
            const DMenubarSeparator(),
            const DMenubarSub(
              trigger: DMenubarSubTrigger(child: Text('Share')),
              content: DMenubarSubContent(
                children: [
                  DMenubarItem(child: Text('Email link')),
                  DMenubarItem(child: Text('Messages')),
                ],
              ),
            ),
            const DMenubarSeparator(),
            DMenubarItem(
              onPressed: onSelected == null
                  ? () {}
                  : () => onSelected!('Print'),
              trailing: const DMenubarShortcut('⌘P'),
              child: const Text('Print...'),
            ),
          ],
        ),
      ),
      const DMenubarMenu(
        trigger: DMenubarTrigger(child: Text('Edit')),
        content: DMenubarContent(
          children: [
            DMenubarItem(child: Text('Undo')),
            DMenubarItem(child: Text('Redo')),
          ],
        ),
      ),
      const DMenubarMenu(
        trigger: DMenubarTrigger(child: Text('Profiles')),
        content: DMenubarContent(
          children: [
            DMenubarItem(child: Text('Andy')),
            DMenubarItem(child: Text('Benoit')),
          ],
        ),
      ),
    ],
  );
}

class _StatefulMenubar extends StatefulWidget {
  const _StatefulMenubar();

  @override
  State<_StatefulMenubar> createState() => _StatefulMenubarState();
}

class _ControlledMenubar extends StatefulWidget {
  const _ControlledMenubar({super.key});

  @override
  State<_ControlledMenubar> createState() => _ControlledMenubarState();
}

class _ControlledMenubarState extends State<_ControlledMenubar> {
  String? openMenu;

  void open(String menu) => setState(() => openMenu = menu);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      DMenubar(
        children: [
          DMenubarMenu(
            open: openMenu == 'file',
            onOpenChange: (open, _) =>
                setState(() => openMenu = open ? 'file' : null),
            trigger: const DMenubarTrigger(child: Text('File')),
            content: const DMenubarContent(
              children: [DMenubarItem(child: Text('New Tab'))],
            ),
          ),
          DMenubarMenu(
            open: openMenu == 'edit',
            onOpenChange: (open, _) =>
                setState(() => openMenu = open ? 'edit' : null),
            trigger: const DMenubarTrigger(child: Text('Edit')),
            content: const DMenubarContent(
              children: [DMenubarItem(child: Text('Undo'))],
            ),
          ),
        ],
      ),
    ],
  );
}

class _StatefulMenubarState extends State<_StatefulMenubar> {
  bool bookmarks = false;
  String profile = 'benoit';

  @override
  Widget build(BuildContext context) => Column(
    children: [
      DMenubar(
        children: [
          DMenubarMenu(
            trigger: const DMenubarTrigger(child: Text('View')),
            content: DMenubarContent(
              children: [
                DMenubarCheckboxItem(
                  checked: bookmarks,
                  onChanged: (value) => setState(() => bookmarks = value),
                  child: const Text('Bookmarks Bar'),
                ),
              ],
            ),
          ),
          DMenubarMenu(
            trigger: const DMenubarTrigger(child: Text('Profiles')),
            content: DMenubarContent(
              children: [
                DMenubarRadioGroup<String>(
                  value: profile,
                  onChanged: (value) => setState(() => profile = value),
                  children: const [
                    DMenubarRadioItem(value: 'andy', child: Text('Andy')),
                    DMenubarRadioItem(value: 'benoit', child: Text('Benoit')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      Text('bookmarks:${bookmarks ? 'on' : 'off'}'),
      Text('profile:$profile'),
    ],
  );
}
