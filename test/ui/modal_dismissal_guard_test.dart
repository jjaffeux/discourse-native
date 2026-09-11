import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final drawer in [false, true]) {
    testWidgets(
      '${drawer ? 'Drawer' : 'Dialog'} helper consults the current guard for every dismissal',
      (tester) async {
        var allowed = false;
        var checks = 0;
        var completed = false;
        String? result;
        late VoidCallback controllerClose;
        final input = TextEditingController(text: 'Keep this draft');
        final triggerFocus = FocusNode();
        bool canDismiss() {
          checks++;
          return allowed;
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => DButton(
                  focusNode: triggerFocus,
                  label: const Text('Open'),
                  onPressed: () async {
                    if (drawer) {
                      result = await showDDrawer<String>(
                        context: context,
                        canDismiss: canDismiss,
                        showSwipeHandle: true,
                        requestInitialFocus: false,
                        builder: (_, controller) {
                          controllerClose = () =>
                              controller.close('controller result');
                          return DDrawerContent(
                            children: [
                              DDrawerHeader(
                                children: [DInput(controller: input)],
                              ),
                              DDrawerFooter(
                                children: [
                                  DDrawerClose<String>(
                                    result: 'button result',
                                    builder: (_, close) => DButton(
                                      label: const Text('Close'),
                                      onPressed: close,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      );
                    } else {
                      result = await showDDialog<String>(
                        context: context,
                        canDismiss: canDismiss,
                        builder: (_, controller) {
                          controllerClose = () =>
                              controller.close('controller result');
                          return DDialogContent(
                            showCloseButton: false,
                            children: [
                              DInput(controller: input),
                              DDialogFooter(
                                children: [
                                  DDialogClose<String>(
                                    result: 'button result',
                                    builder: (_, close) => DButton(
                                      label: const Text('Close'),
                                      onPressed: close,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      );
                    }
                    completed = true;
                  },
                ),
              ),
            ),
          ),
        );
        triggerFocus.requestFocus();
        await tester.pump();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final surface = find.byType(drawer ? DDrawerContent : DDialogContent);
        final top = tester.getTopLeft(surface).dy;
        Future<void> verifyBlocked(Future<void> Function() dismiss) async {
          final previousChecks = checks;
          await dismiss();
          await tester.pumpAndSettle();
          expect(checks, greaterThan(previousChecks));
          expect(completed, isFalse);
          expect(surface, findsOneWidget);
          expect(input.text, 'Keep this draft');
        }

        await verifyBlocked(() => tester.tap(find.text('Close')));
        await verifyBlocked(() async => controllerClose());
        await verifyBlocked(
          () => tester.sendKeyEvent(LogicalKeyboardKey.escape),
        );
        await verifyBlocked(() async {
          await tester.binding.handlePopRoute();
        });
        await verifyBlocked(() => tester.tapAt(const Offset(4, 4)));
        if (drawer) {
          await verifyBlocked(
            () => tester.drag(
              find.byType(DDrawerSwipeHandle),
              const Offset(0, 500),
            ),
          );
          expect(tester.getTopLeft(surface).dy, closeTo(top, .5));
        }
        allowed = true;
        controllerClose();
        await tester.pumpAndSettle();
        expect(surface, findsNothing);
        expect(completed, isTrue);
        expect(result, 'controller result');
        expect(triggerFocus.hasFocus, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
        input.dispose();
        triggerFocus.dispose();
      },
    );
  }
}
