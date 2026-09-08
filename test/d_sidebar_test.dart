import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget fixture({
  double width = 1000,
  DSidebarCollapsible mode = DSidebarCollapsible.icon,
  DSidebarSide side = DSidebarSide.left,
  bool? open,
  ValueChanged<bool>? onChange,
  FocusNode? focus,
  ThemeData? theme,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        height: 450,
        child: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 450),
            textScaler: TextScaler.linear(scale),
          ),
          child: Directionality(
            textDirection: direction,
            child: DSidebarProvider(
              open: open,
              onOpenChange: onChange,
              child: Row(
                textDirection: side == DSidebarSide.left
                    ? TextDirection.ltr
                    : TextDirection.rtl,
                children: [
                  DSidebar(
                    side: side,
                    collapsible: mode,
                    header: const DSidebarHeader(child: Text('Header')),
                    footer: const DSidebarFooter(child: Text('Footer')),
                    child: DSidebarContent(
                      children: [
                        DSidebarGroup(
                          label: const DSidebarGroupLabel(
                            child: Text('Application'),
                          ),
                          child: DSidebarMenu(
                            children: [
                              DSidebarMenuButton(
                                icon: const Icon(Icons.home),
                                tooltip: 'Home',
                                isActive: true,
                                onPressed: () {},
                                child: const Text('Home'),
                              ),
                              const DSidebarMenuButton(child: Text('Disabled')),
                              for (var i = 0; i < 30; i++)
                                DSidebarMenuButton(
                                  onPressed: () {},
                                  child: Text('Destination $i'),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        DSidebarTrigger(focusNode: focus),
                        const Text('Main'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'open mobile panel receives live themes and survives parent rebuild',
    (tester) async {
      await tester.pumpWidget(fixture(width: 360));
      await tester.tap(find.byType(DSidebarTrigger));
      await tester.pumpAndSettle();
      final original = tester.element(find.text('Header'));
      final theme = ThemeData.dark().copyWith(
        extensions: [
          DTokens.fromTheme(
            ThemeData.dark(),
          ).copyWith(surface: Colors.green, radius: 12),
        ],
      );
      await tester.pumpWidget(fixture(width: 360, theme: theme));
      await tester.pumpAndSettle();
      expect(tester.element(find.text('Header')), same(original));
      expect(
        Theme.of(tester.element(find.text('Header'))).brightness,
        Brightness.dark,
      );
      expect(
        DTokens.of(tester.element(find.text('Header'))).surface,
        Colors.green,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('desktop offcanvas hides focus and static ignores toggle', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(fixture(mode: DSidebarCollapsible.offcanvas));
    await tester.tap(find.byType(DSidebarTrigger));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSidebar)).width, 0);
    await tester.pumpWidget(fixture(mode: DSidebarCollapsible.none));
    await tester.tap(find.byType(DSidebarTrigger));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSidebar)).width, 256);
  });

  testWidgets('desktop collapse, shortcut and controlled state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(fixture(focus: focus));
    expect(tester.getSize(find.byType(DSidebar)).width, 256);
    await tester.tap(find.byType(DSidebarTrigger));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSidebar)).width, 48);
    expect(find.text('Application'), findsNothing);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSidebar)).width, 256);
    bool? requested;
    await tester.pumpWidget(
      fixture(open: true, onChange: (v) => requested = v),
    );
    await tester.tap(find.byType(DSidebarTrigger));
    await tester.pumpAndSettle();
    expect(requested, false);
    expect(tester.getSize(find.byType(DSidebar)).width, 256);
  });
  testWidgets('content scroll leaves header and footer fixed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(fixture());
    final header = tester.getTopLeft(find.text('Header'));
    final footer = tester.getTopLeft(find.text('Footer'));
    await tester.drag(find.byType(DSidebarContent), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Header')), header);
    expect(tester.getTopLeft(find.text('Footer')), footer);
    expect(
      tester.getTopLeft(find.text('Destination 0')).dy,
      lessThan(header.dy),
    );
  });
  testWidgets('mobile opens physical right, Escape restores focus and state', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      fixture(width: 360, side: DSidebarSide.right, focus: focus),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Header'), findsOneWidget);
    expect(tester.getTopRight(find.text('Header')).dx, greaterThan(400));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Header'), findsNothing);
    expect(focus.hasFocus, true);
    await tester.tap(find.byType(DSidebarTrigger));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 300));
    await tester.pumpAndSettle();
    expect(find.text('Header'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('static large text RTL remains inline with neutral selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      fixture(
        width: 360,
        mode: DSidebarCollapsible.none,
        scale: 2,
        direction: TextDirection.rtl,
      ),
    );
    expect(find.text('Header'), findsOneWidget);
    expect(tester.getSize(find.byType(DSidebar)).width, 256);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'rows activate through keyboard and expose selected disabled semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();

      final focus = FocusNode();
      addTearDown(focus.dispose);
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: Column(
                children: [
                  DSidebarMenuButton(
                    focusNode: focus,
                    isActive: true,
                    height: 30,
                    onPressed: () => calls++,
                    child: const Text('Selected'),
                  ),
                  const DSidebarMenuButton(child: Text('Disabled')),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(DSidebarMenuButton).first).height, 30);
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(calls, 1);
      expect(
        tester.getSemantics(find.byType(DSidebarMenuButton).first),
        matchesSemantics(
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          isSelected: true,
          hasSelectedState: true,
          isFocusable: true,
          isFocused: true,
          hasFocusAction: true,
          hasTapAction: true,
          label: 'Selected',
        ),
      );
      semantics.dispose();
    },
  );
}
