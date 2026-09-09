import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {Size size = const Size(800, 600)}) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.macOS),
  home: MediaQuery(
    data: MediaQueryData(size: size),
    child: Scaffold(body: Center(child: child)),
  ),
);

Widget _alert<T>({
  DDialogController<T>? controller,
  DAlertDialogSize size = DAlertDialogSize.regular,
  ValueChanged<DDialogChangeDetails<T>>? onOpenChanged,
  bool dismissOnEscape = true,
  Widget? media,
  List<Widget>? extra,
  T? cancelResult,
  T? actionResult,
}) => DAlertDialog<T>(
  controller: controller,
  onOpenChanged: onOpenChanged,
  dismissOnEscape: dismissOnEscape,
  trigger: DAlertDialogTrigger(
    builder: (context, open) => DButton(
      onPressed: open,
      variant: DButtonVariant.outline,
      label: const Text('Open alert'),
      hasPopup: true,
    ),
  ),
  content: DAlertDialogContent(
    size: size,
    semanticLabel: 'Confirm change',
    children: [
      DAlertDialogHeader(
        media: media,
        title: const Text('Confirm change?'),
        description: const Text('This action cannot be undone.'),
      ),
      ...?extra,
      DAlertDialogFooter(
        children: [
          DAlertDialogCancel<T>(
            label: const Text('Cancel'),
            result: cancelResult,
          ),
          DAlertDialogAction<T>(
            label: const Text('Continue'),
            result: actionResult,
          ),
        ],
      ),
    ],
  ),
);

void main() {
  testWidgets(
    'requires explicit response to outside press and Escape cancels',
    (tester) async {
      final changes = <DDialogChangeDetails<bool>>[];
      await tester.pumpWidget(
        _host(_alert<bool>(onOpenChanged: changes.add, cancelResult: false)),
      );
      await tester.tap(find.text('Open alert'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Confirm change?'), findsOneWidget);
      expect(changes.where((change) => !change.open), isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Confirm change?'), findsNothing);
      expect(changes.last.reason, DDialogChangeReason.escape);
    },
  );

  testWidgets('typed cancel and action results use explicit close controls', (
    tester,
  ) async {
    final changes = <DDialogChangeDetails<String>>[];
    await tester.pumpWidget(
      _host(
        _alert<String>(
          onOpenChanged: changes.add,
          cancelResult: 'cancelled',
          actionResult: 'accepted',
        ),
      ),
    );
    await tester.tap(find.text('Open alert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(changes.last.result, 'accepted');

    await tester.tap(find.text('Open alert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(changes.last.result, 'cancelled');
  });

  testWidgets(
    'regular and small surfaces follow frozen width and footer rules',
    (tester) async {
      for (final entry in [
        (DAlertDialogSize.regular, 384.0),
        (DAlertDialogSize.small, 320.0),
      ]) {
        await tester.pumpWidget(_host(_alert<void>(size: entry.$1)));
        await tester.tap(find.text('Open alert'));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byType(DAlertDialogContent)).width,
          entry.$2,
        );
        final footer = tester.getRect(find.byType(DAlertDialogFooter));
        final popup = tester.getRect(find.byType(DAlertDialogContent));
        expect(footer.left, popup.left);
        expect(footer.right, popup.right);
        if (entry.$1 == DAlertDialogSize.small) {
          final buttons = find.descendant(
            of: find.byType(DAlertDialogFooter),
            matching: find.byType(FilledButton),
          );
          final cancel = tester.getRect(buttons.at(0));
          final action = tester.getRect(buttons.at(1));
          expect(cancel.top, action.top);
          expect(cancel.width, closeTo(action.width, 1));
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('small footer keeps a two-column grid for extra actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        DAlertDialog<void>(
          trigger: DAlertDialogTrigger(
            builder: (_, open) =>
                TextButton(onPressed: open, child: const Text('Open alert')),
          ),
          content: const DAlertDialogContent(
            size: DAlertDialogSize.small,
            children: [
              DAlertDialogHeader(
                title: Text('Choose an action'),
                description: Text('Three actions exercise the reference grid.'),
              ),
              DAlertDialogFooter(
                children: [
                  DAlertDialogAction<void>(label: Text('First')),
                  DAlertDialogAction<void>(label: Text('Second')),
                  DAlertDialogAction<void>(label: Text('Third')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open alert'));
    await tester.pumpAndSettle();

    Finder button(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(DButton));
    final first = tester.getRect(button('First'));
    final second = tester.getRect(button('Second'));
    final third = tester.getRect(button('Third'));
    expect(first.top, second.top);
    expect(third.top, greaterThan(first.bottom));
    expect(first.width, closeTo(third.width, 1));
    expect(first.left, closeTo(third.left, 1));
  });

  testWidgets(
    'narrow regular footer reverses visually but cancel focuses first',
    (tester) async {
      await tester.pumpWidget(
        _host(_alert<void>(), size: const Size(360, 600)),
      );
      await tester.tap(find.text('Open alert'));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.text('Continue')).top,
        lessThan(tester.getRect(find.text('Cancel')).top),
      );
      final focusContext = FocusManager.instance.primaryFocus?.context;
      expect(focusContext, isNotNull);
      expect(
        find.ancestor(
          of: find.byElementPredicate((element) => element == focusContext),
          matching: find.byType(DAlertDialogCancel<void>),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('media geometry adapts between centered and start-side layouts', (
    tester,
  ) async {
    const media = DAlertDialogMedia(child: Icon(Icons.bluetooth));
    for (final size in [const Size(360, 600), const Size(800, 600)]) {
      await tester.pumpWidget(_host(_alert<void>(media: media), size: size));
      await tester.tap(find.text('Open alert'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(DAlertDialogMedia)),
        const Size(40, 40),
      );
      final mediaRect = tester.getRect(find.byType(DAlertDialogMedia));
      final titleRect = tester.getRect(find.text('Confirm change?'));
      if (size.width < 640) {
        expect(mediaRect.bottom, lessThan(titleRect.top));
      } else {
        expect(mediaRect.left, lessThan(titleRect.left));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'async action coalesces, exposes loading, and stays open on error',
    (tester) async {
      final controller = DDialogController<bool>();
      final gate = Completer<bool>();
      Object? error;
      var calls = 0;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          DAlertDialog<bool>(
            controller: controller,
            trigger: DAlertDialogTrigger(
              builder: (context, open) =>
                  TextButton(onPressed: open, child: const Text('Open alert')),
            ),
            content: DAlertDialogContent(
              children: [
                const DAlertDialogHeader(
                  title: Text('Delete?'),
                  description: Text('This cannot be undone.'),
                ),
                DAlertDialogFooter(
                  children: [
                    const DAlertDialogCancel<bool>(label: Text('Cancel')),
                    DAlertDialogAction<bool>(
                      controller: controller,
                      onSubmit: () {
                        calls++;
                        return gate.future;
                      },
                      onError: (value, _) => error = value,
                      closeOnPressed: false,
                      variant: DButtonVariant.destructive,
                      label: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open alert'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.tap(find.text('Delete'), warnIfMissed: false);
      await tester.pump();
      expect(calls, 1);
      expect(controller.isBusy, isTrue);
      expect(tester.widget<DButton>(find.byType(DButton).last).loading, isTrue);

      gate.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(error, isA<StateError>());
      expect(controller.isBusy, isFalse);
      expect(find.text('Delete?'), findsOneWidget);
    },
  );

  testWidgets(
    'disabled controls, visible error, RTL, scaling and reduced motion fit',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 700),
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: DAlertDialog<void>(
                  initiallyOpen: true,
                  trigger: DAlertDialogTrigger(
                    builder: (_, open) => const SizedBox(),
                  ),
                  content: const DAlertDialogContent(
                    size: DAlertDialogSize.small,
                    children: [
                      DAlertDialogHeader(
                        media: DAlertDialogMedia(child: Icon(Icons.bluetooth)),
                        title: Text('السماح للملحق بالاتصال؟'),
                        description: Text(
                          'هل تريد السماح لملحق USB بالاتصال بهذا الجهاز؟',
                        ),
                      ),
                      DAlertDialogError(message: 'تعذر إكمال العملية.'),
                      DAlertDialogFooter(
                        children: [
                          DAlertDialogCancel<void>(label: Text('عدم السماح')),
                          DAlertDialogAction<void>(
                            label: Text('السماح'),
                            enabled: false,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('تعذر إكمال العملية.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final action = tester.widget<DButton>(find.byType(DButton).last);
      expect(action.onPressed, isNull);
    },
  );
}
