import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'platform.dart';

Future<T?> showShellSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  WidgetBuilder? footerBuilder,
  bool nested = false,
  bool dialogOnDesktop = false,
  bool showHeaderDivider = true,
  BoxConstraints desktopDialogConstraints = const BoxConstraints(
    maxWidth: 480,
    maxHeight: 560,
  ),
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    horizontal: 24,
    vertical: 16,
  ),
  EdgeInsetsGeometry footerPadding = const EdgeInsets.fromLTRB(24, 12, 24, 16),
  bool enableDrag = true,
  bool Function()? canDismiss,
}) {
  if (dialogOnDesktop && !context.isTouch) {
    return showDDialog<T>(
      context: context,
      useRootNavigator: true,
      canDismiss: canDismiss,
      builder: (context, _) => ConstrainedBox(
        constraints: desktopDialogConstraints,
        child: DDialogContent(
          semanticLabel: title,
          showCloseButton: false,
          maxWidth: desktopDialogConstraints.maxWidth,
          maxHeight: desktopDialogConstraints.maxHeight,
          contentPadding: EdgeInsets.zero,
          verticalPadding: 0,
          spacing: 0,
          children: [
            Flexible(
              child: _SheetBody(
                title: title,
                builder: builder,
                footerBuilder: footerBuilder,
                nested: nested,
                showHeaderDivider: showHeaderDivider,
                padding: padding,
                footerPadding: footerPadding,
              ),
            ),
          ],
        ),
      ),
    );
  }
  final variant = enableDrag ? DSheetVariant.menu : DSheetVariant.standard;
  return showDSheet<T>(
    context: context,
    side: DSheetSide.bottom,
    variant: variant,
    dismissOnSwipe: enableDrag,
    canDismiss: canDismiss,
    topBottomMaxWidth: 640,
    builder: (context, _) => ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 640),
      child: DSheetContent(
        side: DSheetSide.bottom,
        variant: variant,
        semanticLabel: title,
        showCloseButton: false,
        scrollWholeSheet: false,
        topBottomMaxHeightFactor: 1,
        children: [
          Flexible(
            child: _SheetBody(
              title: title,
              builder: builder,
              footerBuilder: footerBuilder,
              nested: nested,
              showHeaderDivider: showHeaderDivider,
              padding: padding,
              footerPadding: footerPadding,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.title,
    required this.builder,
    required this.footerBuilder,
    required this.nested,
    required this.showHeaderDivider,
    required this.padding,
    required this.footerPadding,
  });

  final String title;
  final WidgetBuilder builder;
  final WidgetBuilder? footerBuilder;
  final bool nested;
  final bool showHeaderDivider;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry footerPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(nested ? 4 : 20, 8, 8, 8),
          child: Row(
            children: [
              if (nested)
                DButton.iconOnly(
                  onPressed: () => DDialogClose.close<void>(context),
                  variant: DButtonVariant.ghost,
                  tooltip: context.l10n.back,
                  icon: const DIcon(DIcons.arrowLeft),
                ),
              Expanded(
                child: DText(title, variant: DTextVariant.h4, headingLevel: 1),
              ),
              if (!nested)
                DButton.iconOnly(
                  onPressed: () => DDialogClose.close<void>(context),
                  variant: DButtonVariant.ghost,
                  tooltip: context.l10n.close,
                  icon: const DIcon(DIcons.xmark),
                ),
            ],
          ),
        ),
        if (showHeaderDivider) DSeparator(color: theme.shell.divider, space: 1),
        Flexible(
          child: SingleChildScrollView(
            child: Padding(padding: padding, child: builder(context)),
          ),
        ),
        if (footerBuilder case final footerBuilder?) ...[
          DSeparator(color: theme.shell.divider, space: 1),
          Padding(padding: footerPadding, child: footerBuilder(context)),
        ],
      ],
    );
  }
}
