import 'dart:math' as math;

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
  bool scrollBody = true,
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
  FocusNode? initialFocusNode,

  /// Fills the viewport above the keyboard on touch. An opener inside a
  /// Scaffold has already consumed the keyboard inset, so a sheet that
  /// autofocuses a field must track the view's inset instead. A draggable
  /// touch sheet instead reserves its lower opening height, so arriving
  /// results cannot resize it, and takes the room above a visible keyboard.
  bool fillAvailableHeight = false,

  /// Wraps the whole surface, so an inherited theme also reaches its fill.
  Widget Function(BuildContext context, Widget child)? surfaceBuilder,
}) {
  Widget surface(BuildContext context, Widget child) =>
      surfaceBuilder?.call(context, child) ?? child;
  if (dialogOnDesktop && !context.isTouch) {
    return showDDialog<T>(
      context: context,
      useRootNavigator: true,
      canDismiss: canDismiss,
      initialFocusNode: initialFocusNode,
      builder: (context, _) => surface(
        context,
        ConstrainedBox(
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
                  scrollBody: scrollBody,
                  showHeaderDivider: showHeaderDivider,
                  padding: padding,
                  footerPadding: footerPadding,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  // On a phone a draggable sheet comes up from the foot as every other panel
  // does, put away by its grabber or the page around it.
  final variant = !enableDrag
      ? DSheetVariant.standard
      : context.isTouch
      ? DSheetVariant.adaptiveMenu
      : DSheetVariant.menu;
  final adaptive = variant == DSheetVariant.adaptiveMenu;
  final pinnedFooter = adaptive && footerBuilder != null;
  final sizeToContent = !(adaptive && (fillAvailableHeight || pinnedFooter));
  return showDSheet<T>(
    context: context,
    side: DSheetSide.bottom,
    variant: variant,
    sizeToContent: sizeToContent,
    dismissOnSwipe: enableDrag,
    canDismiss: canDismiss,
    initialFocusNode: initialFocusNode,
    fillAvailableHeight: fillAvailableHeight,
    topBottomMaxWidth: 640,
    builder: (context, _) => surface(
      context,
      Padding(
        // The adaptive sheet spans the viewport; centre the capped width
        // without loosening the height it lays the surface out at.
        padding: EdgeInsets.symmetric(
          horizontal: adaptive
              ? math.max(0, (MediaQuery.sizeOf(context).width - 640) / 2)
              : 0,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 640),
          child: DSheetContent(
            side: DSheetSide.bottom,
            variant: variant,
            sizeToContent: sizeToContent,
            semanticLabel: title,
            showCloseButton: false,
            scrollWholeSheet: false,
            topBottomMaxHeightFactor: 1,
            fillAvailableHeight: fillAvailableHeight,
            children: [
              Flexible(
                child: _SheetBody(
                  title: title,
                  builder: builder,
                  footerBuilder: footerBuilder,
                  nested: nested,
                  grabbed: adaptive,
                  expandBody: pinnedFooter,
                  scrollBody: scrollBody,
                  showHeaderDivider: showHeaderDivider,
                  padding: padding,
                  footerPadding: footerPadding,
                ),
              ),
            ],
          ),
        ),
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
    this.grabbed = false,
    this.expandBody = false,
    required this.scrollBody,
    required this.showHeaderDivider,
    required this.padding,
    required this.footerPadding,
  });

  final String title;
  final WidgetBuilder builder;
  final WidgetBuilder? footerBuilder;
  final bool nested;

  /// Put away by its grabber, so its title stands alone as the heading.
  final bool grabbed;
  final bool expandBody;
  final bool scrollBody;
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
          padding: grabbed && !nested
              ? const EdgeInsets.fromLTRB(20, 2, 20, 12)
              : EdgeInsets.fromLTRB(nested ? 4 : 20, 8, 8, 8),
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
                child: DText(
                  title,
                  variant: DTextVariant.h4,
                  headingLevel: 1,
                  style: grabbed
                      ? TextStyle(
                          fontSize: DiscourseTypography.sheetTitle,
                          color: DTokens.of(context).foreground,
                        )
                      : null,
                ),
              ),
              if (!nested && !grabbed)
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
          fit: expandBody ? FlexFit.tight : FlexFit.loose,
          child: scrollBody
              ? SingleChildScrollView(
                  child: Padding(padding: padding, child: builder(context)),
                )
              : Padding(padding: padding, child: builder(context)),
        ),
        if (footerBuilder case final footerBuilder?) ...[
          DSeparator(color: theme.shell.divider, space: 1),
          DSheetFooter(
            padding: footerPadding,
            children: [footerBuilder(context)],
          ),
        ],
      ],
    );
  }
}

/// One form's state, shared by the body and footer that [showShellSheet]
/// builds as separate subtrees. The form wraps the surface through
/// `surfaceBuilder`, and each part rebuilds from it through [of].
class ShellSheetForm<S extends State> extends InheritedWidget {
  const ShellSheetForm({super.key, required this.state, required super.child});

  final S state;

  static S of<S extends State>(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellSheetForm<S>>()!.state;

  // The form rebuilds this scope only when its state changed.
  @override
  bool updateShouldNotify(ShellSheetForm<S> oldWidget) => true;
}

/// A sheet footer's actions, in order towards its trailing edge.
class ShellSheetActions extends StatelessWidget {
  const ShellSheetActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.end,
    spacing: DSpacing.sm,
    runSpacing: DSpacing.sm,
    children: children,
  );
}
