import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
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
  String? barrierLabel,
}) => showDAlertDialog<T>(
  context: context,
  dismissOnEscape: dismissOnEscape,
  barrierLabel: barrierLabel ?? appL10n.confirmation,
  builder: (context, controller) => DAlertDialogContent(
    size: size,
    semanticLabel: switch (title) {
      Text(data: final data?) => data,
      _ => barrierLabel ?? appL10n.confirmation,
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
