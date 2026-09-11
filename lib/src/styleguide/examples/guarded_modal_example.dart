import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

/// Exercises the imperative helpers' live dismissal policy with local state.
class GuardedModalExample extends StatelessWidget {
  const GuardedModalExample({super.key, this.drawer = false});

  final bool drawer;

  @override
  Widget build(BuildContext context) => DButton(
    variant: DButtonVariant.outline,
    label: Text(drawer ? 'Open guarded drawer' : 'Open guarded dialog'),
    onPressed: () => _open(context),
  );

  Future<void> _open(BuildContext context) {
    var allowDismissal = false;
    Widget content(VoidCallback close) => StatefulBuilder(
      builder: (context, setState) {
        final toggle = DButton(
          variant: DButtonVariant.outline,
          label: Text(allowDismissal ? 'Block dismissal' : 'Allow dismissal'),
          onPressed: () => setState(() => allowDismissal = !allowDismissal),
        );
        final done = DButton(label: const Text('Close'), onPressed: close);
        final description = allowDismissal
            ? 'Closing is allowed. Close this panel or press Escape.'
            : 'Closing is blocked. Try Close, Escape, back, an outside press, or a drawer swipe.';
        return drawer
            ? DDrawerContent(
                children: [
                  const DDrawerHeader(
                    children: [DDrawerTitle(child: Text('Guarded drawer'))],
                  ),
                  DDrawerScrollArea(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DSpacing.md,
                    ),
                    child: DDrawerDescription(child: Text(description)),
                  ),
                  DDrawerFooter(children: [toggle, done]),
                ],
              )
            : DDialogContent(
                children: [
                  DDialogHeader(
                    children: [
                      const DDialogTitle(child: Text('Guarded dialog')),
                      DDialogDescription(child: Text(description)),
                    ],
                  ),
                  DDialogFooter(children: [toggle, done]),
                ],
              );
      },
    );
    return drawer
        ? showDDrawer<void>(
            context: context,
            canDismiss: () => allowDismissal,
            showSwipeHandle: true,
            requestInitialFocus: false,
            builder: (_, controller) => content(controller.close),
          )
        : showDDialog<void>(
            context: context,
            canDismiss: () => allowDismissal,
            builder: (_, controller) => content(controller.close),
          );
  }
}
