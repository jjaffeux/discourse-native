import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/shell_sheet.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _title = 'Sheet title';

void main() {
  testWidgets('non-draggable mobile editor stays above a live keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final keyboard = ValueNotifier<double>(0);
    addTearDown(keyboard.dispose);
    await _pumpSurface(
      tester,
      dialog: false,
      enableDrag: false,
      platform: TargetPlatform.iOS,
      keyboard: keyboard,
      builder: (_) => DTextarea(minLines: 3, maxLines: 8),
      footerBuilder: (context) => DButton(
        label: const Text('Apply editor'),
        onPressed: () => DDialogClose.close<void>(context),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    keyboard.value = 240;
    await tester.pumpAndSettle();
    expect(
      tester.getBottomRight(find.text('Apply editor')).dy,
      lessThanOrEqualTo(410),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Apply editor'));
    await tester.pumpAndSettle();
    expect(find.byType(DSheetContent), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  for (final dialog in [true, false]) {
    final presentation = dialog ? 'dialog' : 'sheet';

    for (final keyboard in [true, false]) {
      final input = keyboard ? 'keyboard' : 'pointer';

      testWidgets(
        'a $presentation opened from a menu by $input takes focus from the '
        'menu trigger and returns it on Escape',
        (tester) async {
          final trigger = await _pumpMenu(tester, dialog: dialog);

          await _openFromMenu(tester, trigger, keyboard: keyboard);
          expect(find.text(_title), findsOneWidget);
          expect(_primaryFocusRoute(), same(_surfaceRoute(tester)));

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.text(_title), findsNothing);
          expect(trigger.hasPrimaryFocus, isTrue);

          await _openFromMenu(tester, trigger, keyboard: keyboard);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(_primaryFocusRoute(), same(_surfaceRoute(tester)));
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }

    for (final nested in [false, true]) {
      testWidgets(
        'the $presentation ${nested ? 'back' : 'close'} action returns focus '
        'to its menu trigger',
        (tester) async {
          final trigger = await _pumpMenu(
            tester,
            dialog: dialog,
            nested: nested,
          );
          await _openFromMenu(tester, trigger, keyboard: true);
          await tester.tap(find.byTooltip(nested ? 'Back' : 'Close'));
          await tester.pumpAndSettle();
          expect(find.text(_title), findsNothing);
          expect(trigger.hasPrimaryFocus, isTrue);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }

    testWidgets(
      'a $presentation opened from a menu keeps an autofocused field focused',
      (tester) async {
        final trigger = await _pumpMenu(tester, dialog: dialog, field: true);
        await _openFromMenu(tester, trigger, keyboard: true);

        final field = find.byKey(const ValueKey('sheet-field'));
        expect(field, findsOneWidget);
        expect(_focusWithin(field), isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'desktop preference still opens the phone sheet from the foot on '
      '$platform',
      (tester) async {
        await _pumpSurface(tester, platform: platform, dialog: true);
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byType(DSheetContent), findsOneWidget);
        expect(find.byType(DDialogContent), findsNothing);
        expect(find.byKey(const ValueKey('sheet-drag-handle')), findsOneWidget);
        expect(find.byTooltip('Close'), findsNothing);
        expect(
          tester.getRect(find.byType(DSheetContent)).bottom,
          600 - const DMobileDockGeometry(foot: 0).endLift,
        );
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets('a phone sheet is put away by its grabber', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpSurface(tester, platform: TargetPlatform.iOS, dialog: true);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('sheet-drag-handle')),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    expect(find.text(_title), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a wide touch sheet keeps the 640px width', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpSurface(tester, dialog: false, platform: TargetPlatform.iOS);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final surface = tester.getRect(find.byType(DSheetContent));
    expect(surface.width, 640);
    expect(surface.left, 180);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  for (final dialog in [false, true]) {
    testWidgets(
      '${dialog ? 'dialog' : 'sheet'} descendants return typed results and '
      'restore their opening control',
      (tester) async {
        String? result;
        final trigger = await _pumpSurface(
          tester,
          dialog: dialog,
          onResult: (value) => result = value,
          builder: (context) => DButton(
            label: const Text('Choose'),
            onPressed: () => DDialogClose.close<String>(context, 'chosen'),
          ),
        );
        trigger.requestFocus();
        await tester.pump();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose'));
        await tester.pumpAndSettle();
        expect(result, 'chosen');
        expect(find.text(_title), findsNothing);
        expect(trigger.hasPrimaryFocus, isTrue);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      '${dialog ? 'dialog' : 'sheet'} keeps title and footer visible with '
      'large text and a live keyboard',
      (tester) async {
        tester.view.physicalSize = dialog
            ? const Size(800, 480)
            : const Size(390, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final keyboard = ValueNotifier<double>(0);
        addTearDown(keyboard.dispose);
        await _pumpSurface(
          tester,
          dialog: dialog,
          platform: dialog ? TargetPlatform.macOS : TargetPlatform.iOS,
          keyboard: keyboard,
          textScaler: const TextScaler.linear(2),
          builder: (context) => Column(
            children: [
              for (var index = 0; index < 20; index++)
                SizedBox(height: 48, child: Text('Row $index')),
              DInput(key: const ValueKey('last-input')),
            ],
          ),
          footerBuilder: (context) => DButton(
            key: const ValueKey('fixed-footer'),
            label: const Text('Apply'),
            onPressed: () => DDialogClose.close<String>(context, 'applied'),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        keyboard.value = 180;
        await tester.pumpAndSettle();
        // A phone sheet rises once the keyboard has settled.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final footer = find.byKey(const ValueKey('fixed-footer'));
        final before = tester.getRect(footer);
        expect(
          tester.getTopLeft(find.text(_title)).dy,
          greaterThanOrEqualTo(0),
        );
        expect(before.bottom, lessThanOrEqualTo(300));
        expect(
          before.top,
          greaterThan(tester.getBottomLeft(find.text(_title)).dy),
        );
        await tester.ensureVisible(find.byKey(const ValueKey('last-input')));
        await tester.pumpAndSettle();
        expect(tester.getRect(footer), before);
        expect(tester.takeException(), isNull);
        await tester.tap(footer);
        await tester.pumpAndSettle();
        expect(find.text(_title), findsNothing);
      },
      variant: TargetPlatformVariant.only(
        dialog ? TargetPlatform.macOS : TargetPlatform.iOS,
      ),
    );
  }

  testWidgets('desktop sheets retain the 640px width and height limits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpSurface(
      tester,
      dialog: false,
      builder: (_) => const SizedBox(height: 1000),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final surface = tester.getRect(find.byType(DSheetContent));
    expect(surface.width, 640);
    expect(surface.height, 640);
    expect(surface.left, 180);
    expect(surface.bottom, 900);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('desktop dialogs preserve their caller constraints', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpSurface(
      tester,
      dialog: true,
      constraints: const BoxConstraints(
        minWidth: 720,
        maxWidth: 960,
        maxHeight: 720,
      ),
      builder: (_) => const SizedBox(height: 1000),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DDialogContent)), const Size(960, 720));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a nested sheet back action leaves its parent open', (
    tester,
  ) async {
    final nestedFocus = FocusNode();
    addTearDown(nestedFocus.dispose);
    await _pumpSurface(
      tester,
      dialog: true,
      builder: (context) => DButton(
        focusNode: nestedFocus,
        label: const Text('Open nested'),
        onPressed: () => showShellSheet<void>(
          context: context,
          title: 'Nested sheet',
          nested: true,
          dialogOnDesktop: true,
          builder: (_) => const Text('Nested body'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    nestedFocus.requestFocus();
    await tester.pump();
    await tester.tap(find.text('Open nested'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Nested sheet'), findsNothing);
    expect(find.text(_title), findsOneWidget);
    expect(_focusWithin(find.widgetWithText(DButton, 'Open nested')), isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

Future<FocusNode> _pumpMenu(
  WidgetTester tester, {
  required bool dialog,
  bool field = false,
  bool nested = false,
}) async {
  final menu = DPopoverController();
  addTearDown(menu.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: DDropdownMenu(
            controller: menu,
            content: DDropdownMenuContent(
              semanticLabel: 'More',
              children: [
                Builder(
                  builder: (itemContext) => DDropdownMenuItem(
                    key: const ValueKey('open-sheet'),
                    onPressed: () => showShellSheet<void>(
                      context: itemContext,
                      title: _title,
                      dialogOnDesktop: dialog,
                      nested: nested,
                      builder: (context) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DButton(
                            label: const Text('Option'),
                            onPressed: () {},
                          ),
                          if (field)
                            DInput(
                              key: const ValueKey('sheet-field'),
                              autofocus: true,
                            ),
                        ],
                      ),
                    ),
                    child: const Text('Open sheet'),
                  ),
                ),
              ],
            ),
            child: DDropdownMenuTrigger(
              builder: (context, trigger) => DButton(
                key: const ValueKey('menu-trigger'),
                focusNode: trigger.focusNode,
                label: const Text('More'),
                onPressed: trigger.toggle,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return tester
      .widget<DButton>(find.byKey(const ValueKey('menu-trigger')))
      .focusNode!;
}

Future<void> _openFromMenu(
  WidgetTester tester,
  FocusNode trigger, {
  required bool keyboard,
}) async {
  if (keyboard) {
    trigger.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_focusWithin(find.byKey(const ValueKey('open-sheet'))), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await tester.tap(find.byKey(const ValueKey('menu-trigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-sheet')));
  }
  await tester.pumpAndSettle();
}

ModalRoute<Object?>? _primaryFocusRoute() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context == null ? null : ModalRoute.of(context);
}

bool _focusWithin(Finder finder) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  return find
      .descendant(
        of: finder,
        matching: find.byElementPredicate(
          (element) => identical(element, focused),
        ),
      )
      .evaluate()
      .isNotEmpty;
}

ModalRoute<Object?>? _surfaceRoute(WidgetTester tester) =>
    ModalRoute.of(tester.element(find.text(_title)));

Future<FocusNode> _pumpSurface(
  WidgetTester tester, {
  required bool dialog,
  bool enableDrag = true,
  TargetPlatform platform = TargetPlatform.macOS,
  WidgetBuilder? builder,
  WidgetBuilder? footerBuilder,
  ValueChanged<String?>? onResult,
  ValueNotifier<double>? keyboard,
  TextScaler textScaler = TextScaler.noScaling,
  BoxConstraints constraints = const BoxConstraints(
    maxWidth: 480,
    maxHeight: 560,
  ),
}) async {
  final trigger = FocusNode();
  addTearDown(trigger.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(platform: platform),
      builder: (context, child) => keyboard == null
          ? MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: child!,
            )
          : ValueListenableBuilder<double>(
              valueListenable: keyboard,
              builder: (context, bottom, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: textScaler,
                  viewInsets: EdgeInsets.only(bottom: bottom),
                ),
                child: child!,
              ),
            ),
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Center(
          child: Builder(
            builder: (context) => DButton(
              focusNode: trigger,
              label: const Text('Open'),
              onPressed: () async {
                final result = await showShellSheet<String>(
                  context: context,
                  title: _title,
                  dialogOnDesktop: dialog,
                  enableDrag: enableDrag,
                  desktopDialogConstraints: constraints,
                  builder: builder ?? (_) => const Text('Body'),
                  footerBuilder: footerBuilder,
                );
                onResult?.call(result);
              },
            ),
          ),
        ),
      ),
    ),
  );
  return trigger;
}
