import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manager upserts ids, enforces limits, and reports close reasons', () {
    final reasons = <DToastCloseReason>[];
    final controller = DToastController(limit: 2);
    addTearDown(controller.dispose);

    expect(
      controller.add(
        DToastOptions(
          description: 'First',
          duration: null,
          onClose: reasons.add,
        ),
      ),
      1,
    );
    controller.add(
      DToastOptions(
        description: 'Second',
        duration: null,
        onClose: reasons.add,
      ),
      id: 'stable',
    );
    controller.add(
      const DToastOptions(description: 'Updated', duration: null),
      id: 'stable',
    );

    expect(reasons, [DToastCloseReason.replacement]);
    expect(controller.toasts.map((toast) => toast.options.description), [
      'First',
      'Updated',
    ]);
    expect(controller.toasts.last.revision, 1);

    controller.add(const DToastOptions(description: 'Third', duration: null));
    expect(reasons, [DToastCloseReason.replacement, DToastCloseReason.limit]);
    expect(controller.toasts, hasLength(2));
  });

  test('promise updates only its still-current toast revision', () async {
    final controller = DToastController();
    addTearDown(controller.dispose);
    final first = Completer<String>();
    controller.promise(
      first.future,
      id: 'job',
      loading: const DToastOptions(description: 'Loading'),
      success: (value) => DToastOptions(description: value),
      error: (error) => DToastOptions(description: '$error'),
    );
    expect(controller.toasts.single.options.type, DToastType.loading);

    controller.add(
      const DToastOptions(description: 'Replacement', duration: null),
      id: 'job',
    );
    first.complete('Stale success');
    await Future<void>.delayed(Duration.zero);
    expect(controller.toasts.single.options.description, 'Replacement');

    final second = Completer<String>();
    controller.promise(
      second.future,
      id: 'job',
      loading: const DToastOptions(description: 'Loading again'),
      success: (value) => DToastOptions(description: value),
      error: (error) => DToastOptions(description: 'Failed: $error'),
    );
    second.completeError(StateError('offline'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.toasts.single.options.type, DToastType.error);
    expect(controller.toasts.single.options.description, contains('offline'));
  });

  testWidgets('renders types, action, close, and live theme changes', (
    tester,
  ) async {
    final controller = DToastController();
    addTearDown(controller.dispose);
    var dark = false;
    var actions = 0;
    late StateSetter setHostState;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setHostState = setState;
          return MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: DToaster(
              controller: controller,
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => DToast.show(
                    context,
                    'Event created.',
                    title: 'Success',
                    type: DToastType.success,
                    duration: null,
                    action: DToastAction(
                      label: 'Undo',
                      dismissOnPressed: true,
                      onPressed: () => actions++,
                    ),
                  ),
                  child: const Text('Show'),
                ),
              ),
            ),
          );
        },
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(find.text('Success'), findsOneWidget);
    expect(find.text('Event created.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'Success[\s\S]*Event created')),
      findsOneWidget,
    );
    final dismissible = tester.widget<Dismissible>(find.byType(Dismissible));
    expect(dismissible.movementDuration, const Duration(milliseconds: 500));
    expect(dismissible.resizeDuration, const Duration(milliseconds: 500));

    setHostState(() => dark = true);
    await tester.pump();
    expect(find.text('Event created.'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(actions, 1);
    expect(find.text('Event created.'), findsNothing);

    controller.add(
      const DToastOptions(description: 'Closable', duration: null),
    );
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Close notification'));
    await tester.pump();
    expect(find.text('Closable'), findsNothing);
  });

  testWidgets('F6 focuses the viewport, Escape dismisses, and hover pauses', (
    tester,
  ) async {
    final controller = DToastController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: DToaster(
          controller: controller,
          child: const Focus(autofocus: true, child: Text('Content')),
        ),
      ),
    );
    controller.add(
      const DToastOptions(description: 'Timed', duration: Duration(seconds: 2)),
    );
    await tester.pump();
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.text('Timed')));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Timed'), findsOneWidget);
    await gesture.removePointer();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Timed'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Timed'), findsNothing);

    controller.add(
      const DToastOptions(description: 'Keyboard', duration: null),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.pump();
    expect(primaryFocus?.debugLabel, 'Toast viewport');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Keyboard'), findsNothing);
  });

  testWidgets('owned controller ignores a late promise after scope disposal', (
    tester,
  ) async {
    final future = Completer<String>();
    await tester.pumpWidget(
      MaterialApp(
        home: DToaster(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => DToast.of(context).promise(
                future.future,
                loading: const DToastOptions(description: 'Loading'),
                success: (value) => DToastOptions(description: value),
                error: (error) => DToastOptions(description: '$error'),
              ),
              child: const Text('Run'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Run'));
    await tester.pump();
    expect(find.text('Loading'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    future.complete('Late');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a large-text stack scrolls within a narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = DToastController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: DToaster(controller: controller, child: const SizedBox.expand()),
      ),
    );
    for (var index = 1; index <= 3; index++) {
      controller.add(
        DToastOptions(
          description: 'Notice $index; only the newest three remain.',
          duration: null,
        ),
      );
    }
    await tester.pump();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.textContaining('Notice 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
