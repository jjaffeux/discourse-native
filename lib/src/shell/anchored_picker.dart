import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_layout.dart';
import 'platform.dart';
import 'shell_sheet.dart';

/// Opens picker content in a compact popover for pointers and a sheet for
/// touch input.
///
/// Sidebar property pickers share this route so switching between category
/// and tag editing does not also switch surface geometry or animation.
Future<T?> showAnchoredPicker<T>({
  required BuildContext context,
  required BuildContext anchorContext,
  required String title,
  required String barrierLabel,
  required Key popoverKey,
  required WidgetBuilder builder,
  double popoverWidth = _AnchoredPickerSurface.defaultWidth,
  EdgeInsetsGeometry popoverPadding = EdgeInsets.zero,
}) {
  if (context.isTouch) {
    return showShellSheet<T>(
      context: context,
      title: title,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      builder: builder,
    );
  }

  final navigator = Navigator.of(context);
  final overlay = navigator.overlay?.context.findRenderObject() as RenderBox?;
  final anchor = anchorRect(
    anchor: anchorContext.findRenderObject() as RenderBox?,
    overlay: overlay,
  );
  final media = MediaQuery.of(context);
  final alignment = anchor == null
      ? Alignment.center
      : Alignment(
          anchor.center.dx > media.size.width / 2 ? 1 : -1,
          anchor.center.dy > media.size.height / 2 ? 1 : -1,
        );
  final duration = media.disableAnimations
      ? Duration.zero
      : discourseMenuOpenDuration;

  return navigator.push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: barrierLabel,
      barrierColor: Colors.transparent,
      transitionDuration: duration,
      reverseTransitionDuration: media.disableAnimations
          ? Duration.zero
          : discourseMenuCloseDuration,
      pageBuilder: (routeContext, animation, secondaryAnimation) =>
          CustomSingleChildLayout(
            delegate: AnchoredLayout(
              anchor: anchor,
              maxWidth: popoverWidth,
              gap: 4,
              margin: 10,
            ),
            child: _AnchoredPickerTransition(
              animation: animation,
              alignment: alignment,
              child: _AnchoredPickerSurface(
                key: popoverKey,
                width: popoverWidth,
                padding: popoverPadding,
                child: builder(routeContext),
              ),
            ),
          ),
    ),
  );
}

/// Search-and-results layout shared by anchored dropdown pickers.
///
/// Pointer platforms get compact menu geometry. Touch platforms keep the same
/// content in a sheet with comfortable input and row targets.
class AnchoredPickerContent extends StatelessWidget {
  const AnchoredPickerContent({
    super.key,
    required this.queryKey,
    required this.queryController,
    required this.queryHint,
    required this.onQueryChanged,
    required this.onQuerySubmitted,
    required this.children,
    this.separatorKey,
  });

  final Key queryKey;
  final TextEditingController queryController;
  final String queryHint;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onQuerySubmitted;
  final List<Widget> children;
  final Key? separatorKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = !context.isTouch;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: queryKey,
          controller: queryController,
          autofocus: true,
          style: compact ? theme.textTheme.bodySmall : null,
          textInputAction: TextInputAction.done,
          onChanged: onQueryChanged,
          onSubmitted: onQuerySubmitted,
          decoration: InputDecoration(
            hintText: queryHint,
            border: InputBorder.none,
            isDense: compact,
            contentPadding: compact
                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 11)
                : null,
          ),
        ),
        Divider(
          key: separatorKey,
          height: 1,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.14),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 6 : 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// A consistently sized choice inside an [AnchoredPickerContent].
class AnchoredPickerOption extends StatelessWidget {
  const AnchoredPickerOption({
    super.key,
    required this.title,
    required this.onTap,
    this.leading,
    this.subtitle,
    this.trailing,
    this.enabled = true,
    this.indent = 0,
    this.selected = false,
    this.showSelectionIndicator = false,
  });

  final Widget title;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? subtitle;
  final Widget? trailing;
  final bool enabled;
  final double indent;
  final bool selected;
  final bool showSelectionIndicator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = !context.isTouch;
    final horizontalPadding = compact ? 10.0 : 16.0;
    final highlightColor = Color.alphaBlend(
      theme.colorScheme.onSurface.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.10 : 0.06,
      ),
      compact ? theme.shell.floating : theme.shell.content,
    );
    final effectiveLeading = showSelectionIndicator
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AnchoredPickerSelectionIndicator(selected: selected),
              if (leading != null) ...[const SizedBox(width: 8), leading!],
            ],
          )
        : leading;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 0),
      child: ListTile(
        dense: true,
        visualDensity: compact ? VisualDensity.compact : null,
        minTileHeight: compact ? 32 : null,
        minLeadingWidth: compact ? 14 : null,
        horizontalTitleGap: compact ? 10 : null,
        contentPadding: EdgeInsets.only(
          left: horizontalPadding + indent,
          right: horizontalPadding,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        selected: selected,
        selectedColor: theme.colorScheme.onSurface,
        selectedTileColor: highlightColor,
        hoverColor: highlightColor,
        focusColor: highlightColor,
        titleTextStyle: compact ? theme.textTheme.bodySmall : null,
        subtitleTextStyle: compact ? theme.textTheme.labelSmall : null,
        enabled: enabled,
        leading: effectiveLeading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

class _AnchoredPickerSelectionIndicator extends StatelessWidget {
  const _AnchoredPickerSelectionIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: selected ? colors.primary : Colors.transparent,
        border: selected
            ? null
            : Border.all(
                color: colors.onSurfaceVariant.withValues(alpha: 0.75),
              ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: selected
          ? DIcon(DIcons.check, size: 10, color: colors.onPrimary)
          : null,
    );
  }
}

/// Adaptive progress geometry for an [AnchoredPickerContent].
class AnchoredPickerProgress extends StatelessWidget {
  const AnchoredPickerProgress({super.key});

  @override
  Widget build(BuildContext context) {
    final compact = !context.isTouch;
    return Padding(
      padding: EdgeInsets.all(compact ? 8 : 24),
      child: Center(
        child: compact
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              )
            : const CircularProgressIndicator.adaptive(),
      ),
    );
  }
}

/// Empty or error copy inside an [AnchoredPickerContent].
class AnchoredPickerMessage extends StatelessWidget {
  const AnchoredPickerMessage(
    this.message, {
    super.key,
    this.color,
    this.padding = const EdgeInsets.all(18),
    this.textAlign = TextAlign.center,
  });

  final String message;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(
        message,
        textAlign: textAlign,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color ?? theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AnchoredPickerTransition extends StatelessWidget {
  const _AnchoredPickerTransition({
    required this.animation,
    required this.alignment,
    required this.child,
  });

  final Animation<double> animation;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
        alignment: alignment,
        child: child,
      ),
    );
  }
}

class _AnchoredPickerSurface extends StatelessWidget {
  const _AnchoredPickerSurface({
    super.key,
    required this.width,
    required this.padding,
    required this.child,
  });

  static const double defaultWidth = 252;

  final double width;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const radius = BorderRadius.all(Radius.circular(12));
    return Material(
      color: theme.shell.floating,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: width,
        constraints: const BoxConstraints(maxHeight: 440),
        decoration: BoxDecoration(
          border: Border.all(color: theme.shell.divider),
          borderRadius: radius,
        ),
        child: SingleChildScrollView(padding: padding, child: child),
      ),
    );
  }
}
