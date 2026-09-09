import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpMenu(
    WidgetTester tester, {
    Widget? child,
    TextDirection direction = TextDirection.ltr,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Directionality(
            textDirection: direction,
            child: Center(child: child ?? const _MenuHarness()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'pointer opens, focuses first enabled item, selects and restores',
    (tester) async {
      await pumpMenu(tester);
      await open(tester);
      expect(find.text('Disabled API'), findsOneWidget);
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        contains('Profile'),
      );

      await tester.tap(find.text('Billing'));
      await tester.pumpAndSettle();
      expect(find.text('Billing selected'), findsOneWidget);
      expect(find.text('Disabled API'), findsNothing);
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        contains('trigger'),
      );
    },
  );

  testWidgets('Return opens and arrows/Home/End skip disabled rows', (
    tester,
  ) async {
    await pumpMenu(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('Profile'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('Billing'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('Support'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('Profile'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('Support'),
    );
  });

  testWidgets('Space opens and focuses the first enabled row', (tester) async {
    await pumpMenu(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Disabled API'), findsOneWidget);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('Profile'),
    );
  });

  testWidgets('typeahead wraps from the active row', (tester) async {
    await pumpMenu(tester);
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('Settings'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      contains('Support'),
    );
  });

  testWidgets('Space activates and disabled item cannot be activated', (
    tester,
  ) async {
    await pumpMenu(tester);
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Profile selected'), findsOneWidget);

    await open(tester);
    await tester.tap(find.text('Disabled API'));
    await tester.pump();
    expect(find.text('Disabled API'), findsOneWidget);
    expect(find.text('Profile selected'), findsOneWidget);
  });

  testWidgets('checkboxes and radio values are controlled and remain open', (
    tester,
  ) async {
    await pumpMenu(tester, child: const _ChoiceHarness());
    await open(tester);
    await tester.tap(find.text('Panel'));
    await tester.pump();
    expect(find.text('Panel: true'), findsOneWidget);
    expect(find.text('Top'), findsOneWidget);

    await tester.tap(find.text('Top'));
    await tester.pump();
    expect(find.text('Position: top'), findsOneWidget);
    expect(find.text('Bottom'), findsOneWidget);
  });

  testWidgets(
    'nested submenu opens directionally and deepest Escape closes first',
    (tester) async {
      await pumpMenu(tester, child: const _SubmenuHarness());
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        contains('Invite users'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Email'), findsOneWidget);
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        contains('Email'),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Email'), findsNothing);
      expect(find.text('Invite users'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Invite users'), findsNothing);
    },
  );

  testWidgets('nested Escape wins over an ancestor shortcut', (tester) async {
    var ancestorEscapes = 0;
    await pumpMenu(
      tester,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            ancestorEscapes += 1;
          },
        },
        child: const _SubmenuHarness(),
      ),
    );
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsNothing);
    expect(find.text('Invite users'), findsOneWidget);
    expect(ancestorEscapes, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Invite users'), findsNothing);
    expect(ancestorEscapes, 0);
  });

  testWidgets('RTL mirrors submenu directional navigation', (tester) async {
    await pumpMenu(
      tester,
      direction: TextDirection.rtl,
      child: const _SubmenuHarness(),
    );
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsNothing);
  });

  testWidgets('opening a sibling submenu closes the previous overlay', (
    tester,
  ) async {
    await pumpMenu(tester, child: const _SiblingSubmenuHarness());
    await open(tester);
    await tester.tap(find.text('Invite users'));
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsOneWidget);
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsNothing);
    expect(find.text('PDF'), findsOneWidget);
  });

  testWidgets('outside pointer dismisses without stealing outside focus', (
    tester,
  ) async {
    final outside = FocusNode(debugLabel: 'Outside');
    addTearDown(outside.dispose);
    await pumpMenu(
      tester,
      child: Stack(
        children: [
          const Center(child: _MenuHarness()),
          Align(
            alignment: Alignment.topLeft,
            child: Listener(
              onPointerDown: (_) => outside.requestFocus(),
              child: TextButton(
                focusNode: outside,
                onPressed: () {},
                child: const Text('Outside'),
              ),
            ),
          ),
        ],
      ),
    );
    await open(tester);
    await tester.tap(find.text('Outside'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Disabled API'), findsNothing);
    expect(outside.hasFocus, isTrue);
  });

  testWidgets('controlled state requests changes without mutating itself', (
    tester,
  ) async {
    final changes = <bool>[];
    await pumpMenu(
      tester,
      child: DDropdownMenu(
        open: false,
        onOpenChange: (open, _) => changes.add(open),
        content: const DDropdownMenuContent(
          children: [DDropdownMenuItem(onPressed: null, child: Text('Item'))],
        ),
        child: DDropdownMenuTrigger(
          builder: (context, state) => DButton(
            label: const Text('Open'),
            onPressed: state.toggle,
            focusNode: state.focusNode,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(changes, [true]);
    expect(find.text('Item'), findsNothing);
  });

  testWidgets('lifecycle suspension dismisses an uncontrolled menu', (
    tester,
  ) async {
    await pumpMenu(tester);
    await open(tester);
    expect(find.text('Disabled API'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Disabled API'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Disabled API'), findsNothing);
  });

  testWidgets('live theme and text scaling preserve open choice state', (
    tester,
  ) async {
    await tester.pumpWidget(const _LiveEnvironment());
    await tester.pump();
    await open(tester);
    await tester.tap(find.text('Panel'));
    await tester.pump();
    await tester.tap(find.text('Theme'));
    await tester.pump();
    expect(find.text('Panel: true'), findsOneWidget);
    expect(find.text('Panel'), findsOneWidget);
    await tester.tap(find.text('Scale'));
    await tester.pump();
    expect(find.text('Panel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop row geometry stays compact', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pumpMenu(tester);
      await open(tester);
      expect(
        tester.getSize(find.text('Profile').first).height,
        closeTo(20, 0.1),
      );
      final profile = tester.getRect(find.text('Profile').first);
      final billing = tester.getRect(find.text('Billing').first);
      expect(billing.top - profile.top, closeTo(28, 0.1));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iOS rows expose 48px touch bounds without changing typography', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpMenu(tester);
      await open(tester);
      final profile = tester.getRect(find.text('Profile').first);
      final billing = tester.getRect(find.text('Billing').first);
      expect(billing.top - profile.top, closeTo(48, 0.1));
      expect(profile.height, closeTo(20, 0.1));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('semantics expose popup, enabled, checked, and radio state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpMenu(tester, child: const _ChoiceHarness());
    await open(tester);
    expect(
      tester.getSemantics(find.text('Panel')),
      matchesSemantics(
        label: 'Panel',
        hasEnabledState: true,
        isEnabled: true,
        hasCheckedState: true,
        isChecked: false,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('Bottom')),
      matchesSemantics(
        label: 'Bottom',
        hasEnabledState: true,
        isEnabled: true,
        hasCheckedState: true,
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });
}

class _MenuHarness extends StatefulWidget {
  const _MenuHarness();

  @override
  State<_MenuHarness> createState() => _MenuHarnessState();
}

class _MenuHarnessState extends State<_MenuHarness> {
  String _status = 'None';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DDropdownMenu(
        content: DDropdownMenuContent(
          children: [
            for (final label in ['Profile', 'Billing', 'Settings', 'Support'])
              DDropdownMenuItem(
                onPressed: () => setState(() => _status = '$label selected'),
                child: Text(label),
              ),
            const DDropdownMenuItem(
              onPressed: null,
              child: Text('Disabled API'),
            ),
          ],
        ),
        child: DDropdownMenuTrigger(
          builder: (context, state) => DButton(
            label: const Text('Open'),
            variant: DButtonVariant.outline,
            hasPopup: true,
            expanded: state.open,
            focusNode: state.focusNode,
            onPressed: state.toggle,
          ),
        ),
      ),
      Text(_status),
    ],
  );
}

class _ChoiceHarness extends StatefulWidget {
  const _ChoiceHarness();

  @override
  State<_ChoiceHarness> createState() => _ChoiceHarnessState();
}

class _ChoiceHarnessState extends State<_ChoiceHarness> {
  bool _panel = false;
  String _position = 'bottom';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DDropdownMenu(
        content: DDropdownMenuContent(
          children: [
            DDropdownMenuCheckboxItem(
              checked: _panel,
              onChanged: (value) => setState(() => _panel = value),
              child: const Text('Panel'),
            ),
            DDropdownMenuRadioGroup<String>(
              value: _position,
              onChanged: (value) => setState(() => _position = value),
              children: const [
                DDropdownMenuRadioItem(value: 'top', child: Text('Top')),
                DDropdownMenuRadioItem(value: 'bottom', child: Text('Bottom')),
              ],
            ),
          ],
        ),
        child: DDropdownMenuTrigger(
          builder: (context, state) => DButton(
            label: const Text('Open'),
            onPressed: state.toggle,
            focusNode: state.focusNode,
          ),
        ),
      ),
      Text('Panel: $_panel'),
      Text('Position: $_position'),
    ],
  );
}

class _SubmenuHarness extends StatelessWidget {
  const _SubmenuHarness();

  @override
  Widget build(BuildContext context) => DDropdownMenu(
    content: const DDropdownMenuContent(
      children: [
        DDropdownMenuItem(onPressed: _noop, child: Text('Team')),
        DDropdownMenuSub(
          trigger: Text('Invite users'),
          children: [
            DDropdownMenuItem(onPressed: _noop, child: Text('Email')),
            DDropdownMenuItem(onPressed: _noop, child: Text('Message')),
          ],
        ),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, state) => DButton(
        label: const Text('Open'),
        onPressed: state.toggle,
        focusNode: state.focusNode,
      ),
    ),
  );
}

class _SiblingSubmenuHarness extends StatelessWidget {
  const _SiblingSubmenuHarness();

  @override
  Widget build(BuildContext context) => DDropdownMenu(
    content: const DDropdownMenuContent(
      children: [
        DDropdownMenuSub(
          trigger: Text('Invite users'),
          children: [DDropdownMenuItem(onPressed: _noop, child: Text('Email'))],
        ),
        DDropdownMenuSub(
          trigger: Text('Export'),
          children: [DDropdownMenuItem(onPressed: _noop, child: Text('PDF'))],
        ),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, state) => DButton(
        label: const Text('Open'),
        onPressed: state.toggle,
        focusNode: state.focusNode,
      ),
    ),
  );
}

void _noop() {}

class _LiveEnvironment extends StatefulWidget {
  const _LiveEnvironment();

  @override
  State<_LiveEnvironment> createState() => _LiveEnvironmentState();
}

class _LiveEnvironmentState extends State<_LiveEnvironment> {
  bool _dark = false;
  bool _large = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: _dark ? ThemeData.dark() : ThemeData.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(_large ? 2 : 1)),
      child: child!,
    ),
    home: Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () => setState(() => _dark = !_dark),
            child: const Text('Theme'),
          ),
          TextButton(
            onPressed: () => setState(() => _large = !_large),
            child: const Text('Scale'),
          ),
          const _ChoiceHarness(),
        ],
      ),
    ),
  );
}
