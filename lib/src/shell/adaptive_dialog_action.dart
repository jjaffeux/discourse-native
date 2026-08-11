import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Opens an app-owned dialog with the Discourse modal theme on every platform.
///
/// [AlertDialog.adaptive] and [AdaptiveDialogAction] still remain useful to
/// callers outside this route. Inside it, Apple platforms are presented with
/// their Material counterparts so the site's surface, CSS radius, shadow, and
/// backdrop are not replaced by fixed Cupertino values.
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

/// The semantic importance of an action in an adaptive alert dialog.
enum AdaptiveDialogActionKind { regular, primary, destructive }

/// An alert-dialog action that uses the platform's expected presentation.
///
/// [AlertDialog.adaptive] deliberately does not rewrite its action children.
/// This keeps the call sites explicit while ensuring Apple dialogs contain
/// [CupertinoDialogAction]s rather than Material buttons.
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
  Widget build(BuildContext context) => switch (kind) {
    AdaptiveDialogActionKind.regular => TextButton(
      onPressed: onPressed,
      child: child,
    ),
    AdaptiveDialogActionKind.primary => FilledButton(
      onPressed: onPressed,
      child: child,
    ),
    AdaptiveDialogActionKind.destructive => FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.error,
        foregroundColor: Theme.of(context).colorScheme.onError,
      ),
      child: child,
    ),
  };
}
