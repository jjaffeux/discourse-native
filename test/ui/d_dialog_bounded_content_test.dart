import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'default Dialog content retains natural height and outer scrolling',
    (tester) async {
      await _open(
        tester,
        (context) => const DDialogContent(
          showCloseButton: false,
          contentPadding: EdgeInsets.zero,
          verticalPadding: 0,
          children: [SizedBox(height: 800)],
        ),
      );
      expect(tester.getSize(find.byType(DDialogContent)).height, 800);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('DialogScrollArea retains its full viewport height factor', (
    tester,
  ) async {
    await _open(
      tester,
      (context) => const DDialogContent(
        children: [
          DDialogScrollArea(maxHeightFactor: .5, child: SizedBox(height: 800)),
        ],
      ),
    );
    expect(tester.getSize(find.byType(DDialogScrollArea)).height, 300);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bounded Dialog keeps header and footer above a live keyboard', (
    tester,
  ) async {
    final keyboard = ValueNotifier<double>(0);
    addTearDown(keyboard.dispose);
    await _open(
      tester,
      (context) => DDialogContent(
        maxHeight: 560,
        children: [
          const DDialogHeader(
            children: [DDialogTitle(child: Text('Pinned title'))],
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var index = 0; index < 20; index++)
                    SizedBox(height: 48, child: Text('Row $index')),
                  DInput(key: const ValueKey('last-input')),
                ],
              ),
            ),
          ),
          DDialogFooter(
            children: [DButton(label: const Text('Done'), onPressed: () {})],
          ),
        ],
      ),
      keyboard: keyboard,
    );
    keyboard.value = 240;
    await tester.pumpAndSettle();
    final surface = tester.getRect(find.byType(DDialogContent));
    expect(surface.height, 328);
    expect(surface.top, greaterThanOrEqualTo(16));
    expect(surface.bottom, lessThanOrEqualTo(344));
    final title = tester.getRect(find.text('Pinned title'));
    final footer = tester.getRect(find.byType(DDialogFooter));
    await tester.ensureVisible(find.byKey(const ValueKey('last-input')));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Pinned title')), title);
    expect(tester.getRect(find.byType(DDialogFooter)), footer);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bounded Dialog retains safe-area and keyboard clearance', (
    tester,
  ) async {
    final keyboard = ValueNotifier<double>(240);
    addTearDown(keyboard.dispose);
    await _open(
      tester,
      (context) => const DDialogContent(
        maxHeight: 560,
        children: [
          Flexible(child: SingleChildScrollView(child: SizedBox(height: 1000))),
        ],
      ),
      keyboard: keyboard,
      padding: const EdgeInsets.only(top: 24),
    );
    final surface = tester.getRect(find.byType(DDialogContent));
    expect(surface.height, 304);
    expect(surface.top, 40);
    expect(surface.bottom, 344);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bounded Dialog uses its actual nested Navigator viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 600,
            height: 400,
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  body: DButton(
                    label: const Text('Open nested viewport'),
                    onPressed: () => showDDialog<void>(
                      context: context,
                      builder: (context, _) => const DDialogContent(
                        maxHeight: 560,
                        children: [
                          Flexible(
                            child: SingleChildScrollView(
                              child: SizedBox(height: 1000),
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
        ),
      ),
    );
    await tester.tap(find.text('Open nested viewport'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DDialogContent)).height, 368);
    expect(tester.takeException(), isNull);
  });

  for (final restoreFocus in [true, false]) {
    testWidgets(
      'imperative Dialog restoreFocus=$restoreFocus respects final focus',
      (tester) async {
        final finalFocus = FocusNode();
        addTearDown(finalFocus.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    DButton(
                      label: const Text('Final target'),
                      focusNode: finalFocus,
                      onPressed: () {},
                    ),
                    DButton(
                      label: const Text('Open'),
                      onPressed: () => showDDialog<void>(
                        context: context,
                        restoreFocus: restoreFocus,
                        finalFocusNode: finalFocus,
                        builder: (context, _) => DDialogContent(
                          children: [
                            DButton(
                              label: const Text('Close typed'),
                              onPressed: () =>
                                  DDialogClose.close<void>(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Close typed'));
        await tester.pumpAndSettle();
        expect(finalFocus.hasPrimaryFocus, restoreFocus);
      },
    );
  }

  testWidgets('descendant typed close removes its own covered route', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => DButton(
              label: const Text('Open parent'),
              onPressed: () async {
                result = await showDDialog<String>(
                  context: context,
                  builder: (parentContext, _) => DDialogContent(
                    children: [
                      DButton(
                        label: const Text('Open child'),
                        onPressed: () => showDDialog<void>(
                          context: parentContext,
                          builder: (childContext, _) => DDialogContent(
                            children: [
                              const Text('Child stays open'),
                              DButton(
                                label: const Text('Close parent'),
                                onPressed: () => DDialogClose.close<String>(
                                  parentContext,
                                  'parent result',
                                ),
                              ),
                              DButton(
                                label: const Text('Close child'),
                                onPressed: () =>
                                    DDialogClose.close<void>(childContext),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open parent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open child'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close parent'));
    await tester.pumpAndSettle();
    expect(result, 'parent result');
    expect(find.text('Child stays open'), findsOneWidget);
    expect(find.text('Open child'), findsNothing);
    await tester.tap(find.text('Close child'));
    await tester.pumpAndSettle();
    expect(find.text('Child stays open'), findsNothing);
  });
}

Future<void> _open(
  WidgetTester tester,
  WidgetBuilder builder, {
  ValueNotifier<double>? keyboard,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => keyboard == null
          ? child!
          : ValueListenableBuilder<double>(
              valueListenable: keyboard,
              builder: (context, bottom, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  viewInsets: EdgeInsets.only(bottom: bottom),
                  padding: padding,
                  viewPadding: padding,
                ),
                child: child!,
              ),
            ),
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Builder(
          builder: (context) => DButton(
            label: const Text('Open'),
            onPressed: () => showDDialog<void>(
              context: context,
              builder: (context, _) => builder(context),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
