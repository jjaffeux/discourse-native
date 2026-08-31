import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/d_button.dart';

Future<T?> showDiscourseDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: (dialogContext) {
    final theme = Theme.of(dialogContext);
    final materialPlatform = switch (theme.platform) {
      TargetPlatform.iOS => TargetPlatform.android,
      TargetPlatform.macOS => TargetPlatform.linux,
      final platform => platform,
    };
    return Theme(
      data: theme.copyWith(platform: materialPlatform),
      child: Builder(builder: builder),
    );
  },
);

class DiscourseAlertDialog extends StatelessWidget {
  const DiscourseAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: title,
    content: content,
    actions: actions,
    actionsAlignment: MainAxisAlignment.start,
    actionsOverflowAlignment: OverflowBarAlignment.start,
    actionsOverflowButtonSpacing: 8,
    buttonPadding: const EdgeInsets.symmetric(horizontal: 8),
  );
}

enum AdaptiveDialogActionKind { regular, primary, destructive }

class AdaptiveDialogAction extends StatelessWidget {
  const AdaptiveDialogAction({
    super.key,
    required this.onPressed,
    required this.child,
    this.kind = AdaptiveDialogActionKind.regular,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final AdaptiveDialogActionKind kind;

  @override
  Widget build(BuildContext context) {
    return switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.macOS => CupertinoDialogAction(
        onPressed: onPressed,
        isDefaultAction: kind == AdaptiveDialogActionKind.primary,
        isDestructiveAction: kind == AdaptiveDialogActionKind.destructive,
        child: child,
      ),
      _ => _MaterialDialogAction(
        onPressed: onPressed,
        kind: kind,
        child: child,
      ),
    };
  }
}

class _MaterialDialogAction extends StatelessWidget {
  const _MaterialDialogAction({
    required this.onPressed,
    required this.kind,
    required this.child,
  });

  final VoidCallback? onPressed;
  final AdaptiveDialogActionKind kind;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return switch (kind) {
      AdaptiveDialogActionKind.regular => DButton(
        onPressed: onPressed,
        variant: DButtonVariant.standard,
        label: child,
      ),
      AdaptiveDialogActionKind.primary => DButton(
        onPressed: onPressed,
        variant: DButtonVariant.primary,
        label: child,
      ),
      AdaptiveDialogActionKind.destructive => DButton(
        onPressed: onPressed,
        variant: DButtonVariant.danger,
        label: child,
      ),
    };
  }
}
