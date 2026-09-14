import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  Widget child, {
  Size size = const Size(800, 600),
  TextDirection direction = TextDirection.ltr,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
  EdgeInsets viewInsets = EdgeInsets.zero,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme,
  home: MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: textScaler,
      disableAnimations: disableAnimations,
      viewInsets: viewInsets,
    ),
    child: Directionality(
      textDirection: direction,
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

Widget _sheet<T>({
  DSheetSide side = DSheetSide.right,
  DSheetController<T>? controller,
  bool? open,
  ValueChanged<DSheetChangeDetails<T>>? onOpenChanged,
  bool dismissOnBarrier = true,
  bool dismissOnEscape = true,
  FocusNode? initialFocusNode,
  FocusNode? finalFocusNode,
  bool showCloseButton = true,
}) => DSheet<T>(
  controller: controller,
  open: open,
  onOpenChanged: onOpenChanged,
  dismissOnBarrier: dismissOnBarrier,
  dismissOnEscape: dismissOnEscape,
  initialFocusNode: initialFocusNode,
  finalFocusNode: finalFocusNode,
  trigger: DSheetTrigger(
    builder: (context, show) => DButton(
      onPressed: show,
      variant: DButtonVariant.outline,
      label: const Text('Open'),
    ),
  ),
  content: DSheetContent(
    side: side,
    showCloseButton: showCloseButton,
    semanticLabel: 'Example sheet',
    children: [
      const DSheetHeader(
        children: [
          DSheetTitle(child: Text('Example sheet')),
          DSheetDescription(child: Text('Useful complementary content.')),
        ],
      ),
      const DSheetBody(child: Text('Body')),
      DSheetFooter(
        children: [
          DSheetClose<T>(
            result: null,
            builder: (context, close) => DButton(
              onPressed: close,
              variant: DButtonVariant.outline,
              label: const Text('Done'),
            ),
          ),
        ],
      ),
    ],
  ),
);

void main() {
  for (final imperative in [false, true]) {
    testWidgets(
      'non-modal ${imperative ? 'helper' : 'sheet'} allows background clicks, input and scrolling',
      (tester) async {
        final controller = DSheetController<String>();
        final backgroundFocus = FocusNode();
        final triggerFocus = FocusNode();
        final scroll = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(backgroundFocus.dispose);
        addTearDown(triggerFocus.dispose);
        addTearDown(scroll.dispose);
        var clicks = 0;
        String? result;
        VoidCallback? closeSheet;
        DSheetContent content() => DSheetContent(
          children: [
            const DSheetHeader(
              children: [DSheetTitle(child: Text('Non-modal sheet'))],
            ),
            DSheetBody(child: DInput(semanticLabel: 'Sheet input')),
            DSheetFooter(
              children: [
                DSheetClose<String>(
                  result: 'done',
                  builder: (_, close) =>
                      DButton(onPressed: close, label: const Text('Done')),
                ),
              ],
            ),
          ],
        );
        Widget background(BuildContext context, VoidCallback open) => Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: Column(
              children: [
                DButton(
                  focusNode: triggerFocus,
                  onPressed: open,
                  label: const Text('Open'),
                ),
                DButton(
                  onPressed: () => clicks++,
                  label: const Text('Background action'),
                ),
                DInput(
                  focusNode: backgroundFocus,
                  semanticLabel: 'Background input',
                ),
                Expanded(
                  child: ListView(
                    controller: scroll,
                    children: List.generate(
                      50,
                      (i) => SizedBox(height: 50, child: Text('Row $i')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        await tester.pumpWidget(
          _host(
            imperative
                ? Builder(
                    builder: (context) => background(context, () async {
                      result = await showDSheet<String>(
                        context: context,
                        modal: false,
                        builder: (_, helperController) {
                          closeSheet = () => helperController.close('done');
                          return content();
                        },
                      );
                    }),
                  )
                : DSheet<String>(
                    controller: controller,
                    modal: false,
                    onOpenChanged: (details) => result = details.result,
                    trigger: DSheetTrigger(builder: background),
                    content: content(),
                  ),
          ),
        );
        triggerFocus.requestFocus();
        await tester.pump();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
        final sheetEditor = find.descendant(
          of: find.byType(DSheetContent),
          matching: find.byType(EditableText),
        );
        await tester.enterText(sheetEditor, 'Retained draft');
        await tester.tap(find.text('Background action'));
        await tester.pumpAndSettle();
        expect(clicks, 1);
        expect(find.byType(DSheetContent), findsOneWidget);
        final backgroundEditor = find.byWidgetPredicate(
          (w) => w is EditableText && w.focusNode == backgroundFocus,
        );
        await tester.tap(backgroundEditor);
        await tester.pumpAndSettle();
        expect(backgroundFocus.hasFocus, isTrue);
        await tester.enterText(backgroundEditor, 'Background still editable');
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(0));
        expect(find.text('Retained draft'), findsOneWidget);

        // Closing from application state must preserve background focus.
        if (imperative) {
          closeSheet!();
        } else {
          controller.close('done');
        }
        await tester.pumpAndSettle();
        expect(result, 'done');
        expect(find.byType(DSheetContent), findsNothing);
        expect(backgroundFocus.hasFocus, isTrue);

        triggerFocus.requestFocus();
        await tester.pump();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(triggerFocus.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'modal dialogs above non-modal sheets still block the background',
    (tester) async {
      var clicks = 0;
      await tester.pumpWidget(
        _host(
          DSheet<void>(
            modal: false,
            initiallyOpen: true,
            trigger: DSheetTrigger(
              builder: (_, _) => Align(
                alignment: Alignment.topLeft,
                child: DButton(
                  onPressed: () => clicks++,
                  label: const Text('Background action'),
                ),
              ),
            ),
            content: DSheetContent(
              children: [
                DSheetHeader(
                  children: [
                    DDialog<void>(
                      dismissOnBarrier: false,
                      trigger: DDialogTrigger(
                        builder: (_, open) => DButton(
                          onPressed: open,
                          label: const Text('Open dialog'),
                        ),
                      ),
                      content: const DDialogContent(
                        children: [DDialogTitle(child: Text('Modal dialog'))],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.text('Background action')));
      await tester.pumpAndSettle();
      expect(clicks, 0);
      expect(find.byType(BackdropFilter), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Modal dialog'), findsNothing);
      expect(find.byType(DSheetContent), findsOneWidget);
      await tester.tap(find.text('Background action'));
      await tester.pumpAndSettle();
      expect(clicks, 1);
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DSheetContent), findsNothing);
    },
  );

  testWidgets(
    'modality changes update an open sheet without losing its input',
    (tester) async {
      final modal = ValueNotifier(true);
      addTearDown(modal.dispose);
      var clicks = 0;
      await tester.pumpWidget(
        _host(
          ValueListenableBuilder<bool>(
            valueListenable: modal,
            builder: (_, value, _) => DSheet<void>(
              modal: value,
              initiallyOpen: true,
              dismissOnBarrier: false,
              trigger: DSheetTrigger(
                builder: (_, _) => Align(
                  alignment: Alignment.topLeft,
                  child: DButton(
                    onPressed: () => clicks++,
                    label: const Text('Background action'),
                  ),
                ),
              ),
              content: DSheetContent(children: [DSheetBody(child: DInput())]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'Retained draft');
      final editor = tester.state(find.byType(EditableText));
      final point = tester.getCenter(find.text('Background action'));
      for (final value in [true, false, true]) {
        modal.value = value;
        await tester.pumpAndSettle();
        final previousClicks = clicks;
        await tester.tapAt(point);
        await tester.pumpAndSettle();
        expect(clicks, value ? previousClicks : previousClicks + 1);
        expect(
          find.byType(BackdropFilter),
          value ? findsOneWidget : findsNothing,
        );
        expect(tester.state(find.byType(EditableText)), same(editor));
        expect(find.text('Retained draft'), findsOneWidget);
      }
    },
  );

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'inset sheet animates width and retains its editor (reduced motion: $reducedMotion)',
      (tester) async {
        tester.view.physicalSize = const Size(900, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final width = ValueNotifier<double>(400);
        addTearDown(width.dispose);
        await tester.pumpWidget(
          _host(
            ValueListenableBuilder<double>(
              valueListenable: width,
              builder: (context, value, _) => DSheet<void>(
                initiallyOpen: true,
                trigger: DSheetTrigger(
                  builder: (_, _) => const SizedBox.shrink(),
                ),
                content: DSheetContent(
                  key: const ValueKey('inset-sheet'),
                  inset: true,
                  animateSize: true,
                  sidePanelWidth: value,
                  sidePanelMaxWidth: 900,
                  children: [
                    DSheetHeader(
                      children: [DInput(semanticLabel: 'Retained input')],
                    ),
                  ],
                ),
              ),
            ),
            size: const Size(900, 700),
            disableAnimations: reducedMotion,
          ),
        );
        await tester.pumpAndSettle();
        final sheet = find.byKey(const ValueKey('inset-sheet'));
        final original = tester.getRect(sheet);
        expect(original, const Rect.fromLTWH(488, 12, 400, 676));
        await tester.enterText(
          find.byType(EditableText),
          'Retained through resizing',
        );
        final editor = tester.state(find.byType(EditableText));
        width.value = 700;
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final intermediate = tester.getSize(sheet).width;
        if (reducedMotion) {
          expect(intermediate, 700);
        } else {
          expect(intermediate, greaterThan(400));
          expect(intermediate, lessThan(700));
        }
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet), const Rect.fromLTWH(188, 12, 700, 676));
        expect(tester.state(find.byType(EditableText)), same(editor));
        expect(find.text('Retained through resizing'), findsOneWidget);
        width.value = 1200;
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet), const Rect.fromLTWH(12, 12, 876, 676));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('uncontrolled trigger and typed close restore focus', (
    tester,
  ) async {
    final triggerFocus = FocusNode();
    addTearDown(triggerFocus.dispose);
    final changes = <DSheetChangeDetails<String>>[];
    await tester.pumpWidget(
      _host(
        DSheet<String>(
          onOpenChanged: changes.add,
          trigger: DSheetTrigger(
            builder: (context, open) => DButton(
              focusNode: triggerFocus,
              onPressed: open,
              label: const Text('Open'),
            ),
          ),
          content: DSheetContent(
            semanticLabel: 'Typed sheet',
            children: [
              const DSheetHeader(
                children: [DSheetTitle(child: Text('Typed sheet'))],
              ),
              DSheetFooter(
                children: [
                  DSheetClose<String>(
                    result: 'chosen',
                    builder: (context, close) =>
                        DButton(onPressed: close, label: const Text('Choose')),
                  ),
                ],
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
    expect(changes.single.reason, DSheetChangeReason.trigger);
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(changes.last.result, 'chosen');
    expect(changes.last.reason, DSheetChangeReason.close);
    expect(triggerFocus.hasFocus, isTrue);
  });

  testWidgets('physical sides match base-nova edge geometry', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final side in const [
      DSheetSide.top,
      DSheetSide.right,
      DSheetSide.bottom,
      DSheetSide.left,
    ]) {
      await tester.pumpWidget(_host(_sheet<void>(side: side)));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(DSheetContent));
      switch (side) {
        case DSheetSide.top:
          expect(rect.top, 0);
          expect(rect.width, 800);
        case DSheetSide.right:
          expect(rect.right, 800);
          expect(rect.width, 384);
          expect(rect.height, 600);
        case DSheetSide.bottom:
          expect(rect.bottom, 600);
          expect(rect.width, 800);
        case DSheetSide.left:
          expect(rect.left, 0);
          expect(rect.width, 384);
          expect(rect.height, 600);
        case DSheetSide.start || DSheetSide.end:
          fail('Logical sides are not in this loop.');
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('side width is 75 percent below the 640 breakpoint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(_sheet<void>(), size: const Size(320, 640)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 240);
  });

  testWidgets('explicit side width is clamped by the maximum and viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(
        DSheet<void>(
          trigger: DSheetTrigger(
            builder: (context, open) =>
                DButton(onPressed: open, label: const Text('Open')),
          ),
          content: const DSheetContent(
            sidePanelWidth: 288,
            children: [DSheetBody(child: Text('Body'))],
          ),
        ),
        size: const Size(320, 640),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 288);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _host(
        DSheet<void>(
          trigger: DSheetTrigger(
            builder: (context, open) =>
                DButton(onPressed: open, label: const Text('Open')),
          ),
          content: const DSheetContent(
            sidePanelWidth: 480,
            children: [DSheetBody(child: Text('Body'))],
          ),
        ),
        size: const Size(320, 640),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 320);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(800, 640);
    await tester.pumpWidget(
      _host(
        DSheet<void>(
          trigger: DSheetTrigger(
            builder: (context, open) =>
                DButton(onPressed: open, label: const Text('Open')),
          ),
          content: const DSheetContent(
            sidePanelWidth: 480,
            children: [DSheetBody(child: Text('Body'))],
          ),
        ),
        size: const Size(800, 640),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 384);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _host(
        DSheet<void>(
          trigger: DSheetTrigger(
            builder: (context, open) =>
                DButton(onPressed: open, label: const Text('Open')),
          ),
          content: const DSheetContent(
            side: DSheetSide.top,
            sidePanelWidth: 100,
            children: [DSheetBody(child: Text('Body'))],
          ),
        ),
        size: const Size(800, 640),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 800);
  });

  testWidgets('logical sides resolve with current RTL direction', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_sheet<void>(side: DSheetSide.start), direction: TextDirection.rtl),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(DSheetContent)).right, 800);
  });

  testWidgets('corner close stays physically right in RTL', (tester) async {
    await tester.pumpWidget(
      _host(_sheet<void>(), direction: TextDirection.rtl),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final sheet = tester.getRect(find.byType(DSheetContent));
    final close = tester.getRect(find.byTooltip('Close'));
    expect(close.right, closeTo(sheet.right - 12, .01));
  });

  testWidgets('title matches the reference text-base leading', (tester) async {
    await tester.pumpWidget(_host(_sheet<void>()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final titleContext = tester.element(find.text('Example sheet'));
    final style = DefaultTextStyle.of(titleContext).style;
    expect(style.fontSize, 16);
    expect(style.height, 24 / 16);
    expect(style.fontWeight, FontWeight.w500);
  });

  testWidgets('no close button and disabled dismissal remain open', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _sheet<void>(
          showCloseButton: false,
          dismissOnBarrier: false,
          dismissOnEscape: false,
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close'), findsNothing);
    await tester.tapAt(const Offset(8, 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Example sheet'), findsOneWidget);
  });

  testWidgets('barrier and Escape report Sheet dismissal reasons', (
    tester,
  ) async {
    final changes = <DSheetChangeDetails<void>>[];
    await tester.pumpWidget(_host(_sheet<void>(onOpenChanged: changes.add)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 300));
    await tester.pumpAndSettle();
    expect(changes.last.reason, DSheetChangeReason.barrier);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(changes.last.reason, DSheetChangeReason.escape);
  });

  testWidgets('controller coalesces submit and closes its open session', (
    tester,
  ) async {
    final controller = DSheetController<String>();
    addTearDown(controller.dispose);
    final gate = Completer<String>();
    await tester.pumpWidget(_host(_sheet<String>(controller: controller)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final first = controller.submit(() => gate.future);
    final second = controller.submit(() async => 'wrong');
    expect(identical(first, second), isTrue);
    gate.complete('saved');
    await first;
    await tester.pumpAndSettle();
    expect(find.text('Example sheet'), findsNothing);
  });

  testWidgets('live theme and direction update an open sheet', (tester) async {
    var dark = false;
    var direction = TextDirection.ltr;
    late StateSetter update;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          final scheme = ColorScheme.fromSeed(
            seedColor: dark ? Colors.purple : Colors.orange,
            brightness: dark ? Brightness.dark : Brightness.light,
          );
          return _host(
            _sheet<void>(side: DSheetSide.end),
            direction: direction,
            theme: ThemeData(colorScheme: scheme),
          );
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final before = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(DSheetContent),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(tester.getRect(find.byType(DSheetContent)).right, 800);
    update(() {
      dark = true;
      direction = TextDirection.rtl;
    });
    await tester.pumpAndSettle();
    final after = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(DSheetContent),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(after.color, isNot(before.color));
    expect(tester.getRect(find.byType(DSheetContent)).left, 0);
  });

  testWidgets('narrow 200 percent text and keyboard insets remain bounded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(
        _sheet<void>(),
        size: const Size(320, 640),
        textScaler: const TextScaler.linear(2),
        disableAnimations: true,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.byType(DSheetContent));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(640));
  });

  testWidgets('keyboard inset scrolls a capped fixed-height bottom sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(
        DSheet<void>(
          trigger: DSheetTrigger(
            builder: (context, open) =>
                DButton(onPressed: open, label: const Text('Open')),
          ),
          content: const DSheetContent(
            side: DSheetSide.bottom,
            topBottomMaxHeightFactor: .85,
            children: [
              DSheetHeader(children: [DSheetTitle(child: Text('Room chat'))]),
              SizedBox(height: 448, child: TextField()),
            ],
          ),
        ),
        size: const Size(320, 640),
        viewInsets: const EdgeInsets.only(bottom: 300),
        disableAnimations: true,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byType(DSheetContent),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(tester.getRect(find.byType(DSheetContent)).bottom, 640);
  });

  testWidgets('showDSheet uses nearest Navigator and returns typed result', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      _host(
        Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (nestedContext) => Builder(
              builder: (context) => DButton(
                onPressed: () async {
                  result = await showDSheet<String>(
                    context: context,
                    sidePanelWidth: 288,
                    inset: true,
                    builder: (context, controller) => DSheetContent(
                      children: [
                        DSheetClose<String>(
                          result: 'result',
                          builder: (context, close) => DButton(
                            onPressed: close,
                            label: const Text('Return'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                label: const Text('Helper'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Helper'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 288);
    expect(tester.getTopLeft(find.byType(DSheetContent)).dy, DSpacing.md);
    final surface = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(DSheetContent),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(surface.borderRadius, isNot(BorderRadius.zero));
    expect(surface.clipBehavior, Clip.antiAlias);
    await tester.tap(find.text('Return'));
    await tester.pumpAndSettle();
    expect(result, 'result');
  });
}
