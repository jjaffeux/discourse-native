import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
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
  DCommandFilter? filter,
  bool shouldFilter = true,
  bool loop = false,
  bool loading = false,
  TextEditingController? editingController,
  FocusNode? inputFocus,
  ScrollController? scrollController,
}) => DCommand<String>(
  controller: controller,
  query: query,
  value: value,
  onQueryChanged: onQueryChanged,
  onValueChanged: onValueChanged,
  onSelected: onSelected,
  filter: filter,
  shouldFilter: shouldFilter,
  loop: loop,
  loading: loading,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DCommandInput<String>(
        controller: editingController,
        focusNode: inputFocus,
      ),
      DCommandList<String>(
        controller: scrollController,
        children: const [
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
    'arrow navigation preserves native editor focus and Return selects',
    (tester) async {
      final focus = FocusNode();
      final editing = TextEditingController();
      final selected = <String>[];
      addTearDown(focus.dispose);
      addTearDown(editing.dispose);
      await tester.pumpWidget(
        _host(
          _command(
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

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(editing.value.composing, const TextRange(start: 0, end: 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, hasLength(1));
      expect(find.text(selected.single), findsOneWidget);
    },
  );

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
    controller.highlight('Calculator');
    await tester.pump();
    controller.activate();
    expect(selected, isEmpty);
    await tester.tap(find.text('Calculator'));
    await tester.pump();
    expect(selected, isEmpty);
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

  testWidgets('custom scores sort matches and filtering can be disabled', (
    tester,
  ) async {
    double reverseScore(String value, String query, List<String> keywords) =>
        value == 'Settings'
        ? 1
        : value.toLowerCase().contains(query)
        ? .5
        : 0;
    await tester.pumpWidget(_host(_command(filter: reverseScore)));
    await tester.enterText(find.byType(TextField), 'i');
    await tester.pump();
    final settingsY = tester.getTopLeft(find.text('Settings').last).dy;
    final billingY = tester.getTopLeft(find.text('Billing')).dy;
    expect(settingsY, lessThan(billingY));

    await tester.pumpWidget(
      _host(_command(query: 'missing', shouldFilter: false)),
    );
    await tester.pump();
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('No results found.'), findsNothing);
  });

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
