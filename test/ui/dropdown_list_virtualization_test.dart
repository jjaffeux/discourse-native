import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() => dropdownListVirtualizationTests();

void dropdownListVirtualizationTests() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('long dropdown mounts a bounded window at $platform $scale', (
        tester,
      ) async {
        var activated = -1;
        await _pumpDropdown(
          tester,
          platform: platform,
          scale: scale,
          children: [
            for (var index = 0; index < 200; index++)
              DDropdownMenuItem(
                key: ValueKey(index),
                onPressed: index == 198 ? null : () => activated = index,
                child: Text(index == 199 ? 'Zulu' : 'Command $index'),
              ),
          ],
        );
        final mounted = find
            .byType(DDropdownMenuItem, skipOffstage: false)
            .evaluate()
            .length;
        debugPrint(
          'DROPDOWN_MOUNTED platform=$platform scale=$scale rows=$mounted',
        );
        expect(mounted, lessThan(40));
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Dropdown item Zulu',
        );
        expect(find.text('Zulu').hitTestable(), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Dropdown item Command 197',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Dropdown item Command 0',
        );
        expect(find.text('Zulu', skipOffstage: false), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Dropdown item Zulu',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(activated, 199);
        expect(find.byType(DDropdownMenuContent), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'typeahead reveals a rich far checkbox and preserves its action',
    (tester) async {
      var checked = false;
      await _pumpDropdown(
        tester,
        scale: 2,
        children: [
          const DDropdownMenuLabel(child: Text('Commands')),
          for (var index = 0; index < 199; index++)
            DDropdownMenuItem(onPressed: () {}, child: Text('Alpha $index')),
          const DDropdownMenuSeparator(),
          DDropdownMenuCheckboxItem(
            checked: false,
            onChanged: (value) => checked = value,
            semanticLabel: 'Zulu target',
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rich target'),
                Text('A second line'),
                Text('And another line'),
              ],
            ),
          ),
        ],
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Dropdown item Zulu target',
      );
      expect(find.text('Rich target').hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(checked, isTrue);
      expect(find.byType(DDropdownMenuContent), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manual scrolling preserves logical keyboard focus', (
    tester,
  ) async {
    await _pumpDropdown(tester, children: _commands());
    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(DDropdownMenuContent),
        matching: find.byType(Scrollable),
      ),
    );
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Command 199').hitTestable(), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Dropdown item Command 0',
    );
    expect(
      find.byType(DDropdownMenuItem, skipOffstage: false).evaluate().length,
      lessThan(40),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Dropdown item Command 1',
    );
    expect(find.text('Command 1').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-count reorder follows current row order', (tester) async {
    final order = ValueNotifier(List<int>.generate(200, (index) => index));
    addTearDown(order.dispose);
    await _pumpDropdown(tester, order: order, children: const []);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    order.value = order.value.reversed.toList();
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Dropdown item Command 199',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Dropdown item Command 198',
    );
    expect(find.text('Command 198').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'replacing rows cancels stale reveals and keeps keyboard navigation',
    (tester) async {
      final order = ValueNotifier(List<int>.generate(200, (index) => index));
      addTearDown(order.dispose);
      await _pumpDropdown(tester, order: order, children: const []);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      order.value = List<int>.generate(100, (index) => index + 1000);
      await tester.pumpAndSettle();
      expect(find.text('Command 199', skipOffstage: false), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(find.text('Command 1000').hitTestable(), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Dropdown item Command 1000',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('initial autofocus finds an offscreen first enabled row', (
    tester,
  ) async {
    await _pumpDropdown(
      tester,
      children: [
        for (var index = 0; index < 200; index++)
          DDropdownMenuItem(
            onPressed: index < 190 ? null : () {},
            child: Text('Command $index'),
          ),
      ],
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Dropdown item Command 190',
    );
    expect(find.text('Command 190').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('newer navigation and closure cancel deferred reveals', (
    tester,
  ) async {
    final borrowed = FocusNode();
    addTearDown(borrowed.dispose);
    await _pumpDropdown(
      tester,
      children: [
        ..._commands().take(199),
        DDropdownMenuItem(
          focusNode: borrowed,
          onPressed: () {},
          child: const Text('Borrowed'),
        ),
      ],
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Dropdown item Command 0',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(DDropdownMenuContent), findsNothing);
    void listener() {}
    borrowed.addListener(listener);
    borrowed.removeListener(listener);
    borrowed.requestFocus();
    expect(tester.takeException(), isNull);
  });

  testWidgets('far submenu opens and restores its owning row', (tester) async {
    var activated = false;
    await _pumpDropdown(
      tester,
      children: [
        ..._commands(),
        DDropdownMenuSub(
          trigger: const Text('More commands'),
          children: [
            DDropdownMenuItem(
              onPressed: () => activated = true,
              child: const Text('Nested action'),
            ),
          ],
        ),
      ],
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Nested action').hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Dropdown item More commands',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nested action'));
    await tester.pumpAndSettle();
    expect(activated, isTrue);
    expect(find.byType(DDropdownMenuContent), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('structural group fallback keeps its semantics and far actions', (
    tester,
  ) async {
    var activated = -1;
    final semantics = tester.ensureSemantics();
    await _pumpDropdown(
      tester,
      children: [
        ..._commands().take(70),
        DDropdownMenuGroup(
          semanticLabel: 'Grouped choices',
          showGuide: true,
          children: [
            for (var index = 70; index < 200; index++)
              DDropdownMenuItem(
                onPressed: () => activated = index,
                child: Text('Grouped $index'),
              ),
          ],
        ),
      ],
    );
    expect(
      find.byType(DDropdownMenuItem, skipOffstage: false),
      findsNWidgets(200),
    );
    expect(
      tester
          .widget<DDropdownMenuGroup>(find.byType(DDropdownMenuGroup))
          .semanticLabel,
      'Grouped choices',
    );
    expect(find.bySemanticsLabel('Grouped choices'), findsOneWidget);
    semantics.dispose();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(activated, 199);
    expect(tester.takeException(), isNull);
  });
}

List<Widget> _commands() => [
  for (var index = 0; index < 200; index++)
    DDropdownMenuItem(
      key: ValueKey(index),
      onPressed: () {},
      child: Text('Command $index'),
    ),
];

Future<void> _pumpDropdown(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.macOS,
  double scale = 1,
  required List<Widget> children,
  ValueNotifier<List<int>>? order,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final values = order ?? ValueNotifier<List<int>>(const []);
  if (order == null) addTearDown(values.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 50),
            child: ValueListenableBuilder<List<int>>(
              valueListenable: values,
              builder: (context, values, _) => DDropdownMenu(
                content: DDropdownMenuContent(
                  width: 250,
                  constraints: const BoxConstraints(maxHeight: 280),
                  children: order == null
                      ? children
                      : [
                          for (final index in values)
                            DDropdownMenuItem(
                              key: ValueKey(index),
                              onPressed: () {},
                              child: Text('Command $index'),
                            ),
                        ],
                ),
                child: DDropdownMenuTrigger.button(label: const Text('Open')),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
