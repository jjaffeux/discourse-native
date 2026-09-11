import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Application adapter for the common two-choice confirmation flow. The
/// generic component owns presentation, focus and typed results; callers keep
/// permissions, persistence and asynchronous mutations after this future.
Future<T?> showDiscourseAlertDialog<T>({
  required BuildContext context,
  required Widget title,
  required Widget description,
  required Widget cancelLabel,
  required Widget actionLabel,
  T? cancelResult,
  T? actionResult,
  DButtonVariant actionVariant = DButtonVariant.primary,
  DAlertDialogSize size = DAlertDialogSize.regular,
  Widget? media,
  Key? cancelKey,
  Key? actionKey,
  bool dismissOnEscape = true,
  String barrierLabel = 'Confirmation',
}) => showDAlertDialog<T>(
  context: context,
  dismissOnEscape: dismissOnEscape,
  barrierLabel: barrierLabel,
  builder: (context, controller) => DAlertDialogContent(
    size: size,
    semanticLabel: switch (title) {
      Text(data: final data?) => data,
      _ => barrierLabel,
    },
    children: [
      DAlertDialogHeader(media: media, title: title, description: description),
      DAlertDialogFooter(
        children: [
          DAlertDialogCancel<T>(
            key: cancelKey,
            label: cancelLabel,
            result: cancelResult,
          ),
          DAlertDialogAction<T>(
            key: actionKey,
            label: actionLabel,
            result: actionResult,
            variant: actionVariant,
          ),
        ],
      ),
    ],
  ),
);

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
        variant: DButtonVariant.outline,
        label: child,
      ),
      AdaptiveDialogActionKind.primary => DButton(
        onPressed: onPressed,
        variant: DButtonVariant.primary,
        label: child,
      ),
      AdaptiveDialogActionKind.destructive => DButton(
        onPressed: onPressed,
        variant: DButtonVariant.destructive,
        label: child,
      ),
    };
  }
}
