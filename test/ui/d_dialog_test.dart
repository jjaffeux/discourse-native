import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  Widget child, {
  ThemeData? theme,
  Size size = const Size(800, 600),
}) {
  return MaterialApp(
    theme: theme,
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

Widget _dialog<T>({
  DDialogController<T>? controller,
  bool? open,
  ValueChanged<DDialogChangeDetails<T>>? onOpenChanged,
  bool dismissOnBarrier = true,
  bool dismissOnEscape = true,
  FocusNode? initialFocusNode,
  FocusNode? finalFocusNode,
  List<Widget>? body,
}) => DDialog<T>(
  controller: controller,
  open: open,
  onOpenChanged: onOpenChanged,
  dismissOnBarrier: dismissOnBarrier,
  dismissOnEscape: dismissOnEscape,
  initialFocusNode: initialFocusNode,
  finalFocusNode: finalFocusNode,
  trigger: DDialogTrigger(
    builder: (context, show) => DButton(
      onPressed: show,
      variant: DButtonVariant.outline,
      label: const Text('Open'),
    ),
  ),
  content: DDialogContent(
    semanticLabel: 'Example dialog',
    children: [
      const DDialogHeader(
        children: [
          DDialogTitle(child: Text('Example dialog')),
          DDialogDescription(child: Text('A useful description.')),
        ],
      ),
      ...?body,
      DDialogFooter(
        children: [
          DDialogClose<T>(
            builder: (context, close) => DButton(
              onPressed: close,
              variant: DButtonVariant.outline,
              label: const Text('Cancel'),
            ),
          ),
        ],
      ),
    ],
  ),
);

void main() {
  testWidgets('uncontrolled trigger and close report state and restore focus', (
    tester,
  ) async {
    final changes = <DDialogChangeDetails<String>>[];
    final triggerFocus = FocusNode();
    addTearDown(triggerFocus.dispose);
    await tester.pumpWidget(
      _host(
        DDialog<String>(
          onOpenChanged: changes.add,
          trigger: DDialogTrigger(
            builder: (context, show) => DButton(
              focusNode: triggerFocus,
              onPressed: show,
              label: const Text('Open'),
            ),
          ),
          content: DDialogContent(
            semanticLabel: 'Choose value',
            children: [
              const DDialogTitle(child: Text('Choose value')),
              DDialogClose<String>(
                result: 'chosen',
                builder: (context, close) =>
                    DButton(onPressed: close, label: const Text('Choose')),
              ),
            ],
          ),
        ),
      ),
    );
    triggerFocus.requestFocus();
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Choose value'), findsOneWidget);
    expect(changes.single.reason, DDialogChangeReason.trigger);
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Choose value'), findsNothing);
    expect(changes.last.result, 'chosen');
    expect(changes.last.reason, DDialogChangeReason.close);
    expect(triggerFocus.hasFocus, isTrue);
  });

  testWidgets('controlled barrier request waits for caller state update', (
    tester,
  ) async {
    bool open = true;
    DDialogChangeDetails<void>? request;
    late StateSetter update;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return _dialog<void>(
              open: open,
              onOpenChanged: (details) => request = details,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(request?.reason, DDialogChangeReason.barrier);
    expect(find.text('Example dialog'), findsOneWidget);
    update(() => open = false);
    await tester.pumpAndSettle();
    expect(find.text('Example dialog'), findsNothing);
  });

  testWidgets('disabled Escape and barrier keep the route open', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_dialog<void>(dismissOnBarrier: false, dismissOnEscape: false)),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Example dialog'), findsOneWidget);
  });

  testWidgets('Escape requests close and reports its reason', (tester) async {
    final changes = <DDialogChangeDetails<void>>[];
    await tester.pumpWidget(_host(_dialog<void>(onOpenChanged: changes.add)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Example dialog'), findsNothing);
    expect(changes.last.reason, DDialogChangeReason.escape);
  });

  testWidgets('custom initial and final focus remain caller owned', (
    tester,
  ) async {
    final initial = FocusNode();
    final finalFocus = FocusNode();
    addTearDown(initial.dispose);
    addTearDown(finalFocus.dispose);
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              focusNode: finalFocus,
              onPressed: () {},
              child: const Text('Final'),
            ),
            _dialog<void>(
              initialFocusNode: initial,
              finalFocusNode: finalFocus,
              body: [
                TextField(
                  focusNode: initial,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(initial.hasFocus, isTrue);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(finalFocus.hasFocus, isTrue);
  });

  testWidgets('Tab and Shift-Tab remain inside the modal route', (
    tester,
  ) async {
    final first = FocusNode();
    final last = FocusNode();
    addTearDown(first.dispose);
    addTearDown(last.dispose);
    await tester.pumpWidget(
      _host(
        DDialog<void>(
          initialFocusNode: first,
          trigger: DDialogTrigger(
            builder: (context, open) =>
                TextButton(onPressed: open, child: const Text('Open')),
          ),
          content: DDialogContent(
            showCloseButton: false,
            children: [
              DButton(
                focusNode: first,
                onPressed: () {},
                label: const Text('First'),
              ),
              DButton(
                focusNode: last,
                onPressed: () {},
                label: const Text('Last'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(first.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(last.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(first.hasFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(last.hasFocus, isTrue);
  });

  testWidgets('controller coalesces submit and closes only on success', (
    tester,
  ) async {
    final controller = DDialogController<String>();
    final gate = Completer<String>();
    addTearDown(controller.dispose);
    int calls = 0;
    await tester.pumpWidget(_host(_dialog<String>(controller: controller)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final first = controller.submit(() {
      calls++;
      return gate.future;
    });
    final second = controller.submit(() async {
      calls++;
      return 'wrong';
    });
    expect(identical(first, second), isTrue);
    expect(controller.isBusy, isTrue);
    expect(calls, 1);
    gate.complete('saved');
    await tester.pumpAndSettle();
    expect(await first, 'saved');
    expect(controller.isBusy, isFalse);
    expect(find.text('Example dialog'), findsNothing);
  });

  testWidgets('failed submit resets busy state and leaves content mounted', (
    tester,
  ) async {
    final controller = DDialogController<String>();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(_dialog<String>(controller: controller)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final submission = controller.submit(
      () async => throw StateError('offline'),
    );
    await expectLater(submission, throwsStateError);
    await tester.pump();
    expect(controller.isBusy, isFalse);
    expect(find.text('Example dialog'), findsOneWidget);
  });

  testWidgets('widget removal detaches a borrowed controller and route', (
    tester,
  ) async {
    final controller = DDialogController<void>();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(_dialog<void>(controller: controller)));
    controller.open();
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);
    expect(find.text('Example dialog'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(controller.isOpen, isFalse);
    controller
      ..open()
      ..close();
    expect(tester.takeException(), isNull);
  });

  testWidgets('base-nova popup, header and footer use measured geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        DDialog<void>(
          trigger: DDialogTrigger(
            builder: (context, open) =>
                TextButton(onPressed: open, child: const Text('Open')),
          ),
          content: const DDialogContent(
            children: [
              DDialogHeader(
                children: [
                  SizedBox(key: Key('header-a'), height: 10),
                  SizedBox(key: Key('header-b'), height: 10),
                ],
              ),
              SizedBox(key: Key('body'), height: 10),
              DDialogFooter(
                children: [SizedBox(key: Key('footer-action'), height: 10)],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final popup = tester.getRect(find.byType(DDialogContent));
    final first = tester.getRect(find.byKey(const Key('header-a')));
    final second = tester.getRect(find.byKey(const Key('header-b')));
    final body = tester.getRect(find.byKey(const Key('body')));
    final footer = tester.getRect(find.byType(DDialogFooter));
    expect(popup.width, 384);
    expect(first.left, popup.left + 16);
    expect(first.top, popup.top + 16);
    expect(second.top - first.bottom, 8);
    expect(body.top - second.bottom, 16);
    expect(footer.left, popup.left);
    expect(footer.width, popup.width);
    expect(footer.top - body.bottom, 16);
  });

  testWidgets('title metrics and logical close placement follow direction', (
    tester,
  ) async {
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: Scaffold(body: _dialog<void>()),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final popup = tester.getRect(find.byType(DDialogContent));
      final close = tester.getRect(find.bySemanticsLabel('Close').last);
      if (direction == TextDirection.ltr) {
        expect(close.right, popup.right - 8);
      } else {
        expect(close.left, popup.left + 8);
      }
      final titleContext = tester.element(find.text('Example dialog').first);
      final style = DefaultTextStyle.of(titleContext).style;
      expect(style.fontSize, 16);
      expect(style.height, 1);
      expect(style.fontWeight, FontWeight.w500);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('editable and close semantics retain independent bounds', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _host(
          _dialog<void>(
            body: const [
              TextField(decoration: InputDecoration(labelText: 'Profile name')),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final fieldNode = tester.getSemantics(
        find.bySemanticsLabel('Profile name').last,
      );
      final closeNode = tester.getSemantics(
        find.bySemanticsLabel('Close').last,
      );
      expect(fieldNode.rect.width, greaterThan(250));
      expect(fieldNode.rect.height, lessThan(100));
      expect(closeNode.rect.size, const Size.square(48));
      expect(fieldNode.parent, same(closeNode.parent));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('live palette and direction reach an already open dialog', (
    tester,
  ) async {
    ThemeData theme = ThemeData.light();
    TextDirection direction = TextDirection.ltr;
    late StateSetter update;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return MaterialApp(
            theme: theme,
            home: Directionality(
              textDirection: direction,
              child: Scaffold(body: _dialog<void>()),
            ),
          );
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    update(() {
      theme = ThemeData.dark();
      direction = TextDirection.rtl;
    });
    await tester.pumpAndSettle();
    final titleContext = tester.element(find.text('Example dialog').first);
    expect(Directionality.of(titleContext), TextDirection.rtl);
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(DDialogContent),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, DTokens.fromTheme(theme).surface);
  });

  testWidgets('narrow 200 percent RTL content scrolls without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 480),
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: _dialog<void>(
                body: [
                  DDialogScrollArea(
                    child: Column(
                      children: List.generate(
                        20,
                        (index) => Text('Long row $index wraps safely'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(DDialogContent)).width, 288);
    expect(
      Directionality.of(tester.element(find.text('Example dialog').first)),
      TextDirection.rtl,
    );
  });

  testWidgets('showDDialog uses nearest Navigator and returns typed result', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => DButton(
            onPressed: () async {
              result = await showDDialog<String>(
                context: context,
                builder: (_, controller) => DDialogContent(
                  children: [
                    DDialogClose<String>(
                      result: 'done',
                      builder: (context, close) =>
                          DButton(onPressed: close, label: const Text('Done')),
                    ),
                  ],
                ),
              );
            },
            label: const Text('Helper'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Helper'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(result, 'done');
  });
}
