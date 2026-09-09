import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_dialog.dart';

/// The two sizes in the frozen base-nova Alert Dialog reference.
enum DAlertDialogSize { regular, small }

/// Alert Dialog uses Dialog for route, focus, state, and result ownership, but
/// deliberately disables outside-press dismissal and has no corner close.
class DAlertDialog<T> extends StatelessWidget {
  const DAlertDialog({
    super.key,
    required this.trigger,
    required this.content,
    this.controller,
    this.open,
    this.initiallyOpen = false,
    this.onOpenChanged,
    this.useRootNavigator = false,
    this.dismissOnEscape = true,
    this.barrierLabel = 'Alert dialog',
    this.routeSettings,
    this.initialFocusNode,
    this.finalFocusNode,
  }) : assert(open == null || !initiallyOpen);

  final DAlertDialogTrigger trigger;
  final Widget content;
  final DDialogController<T>? controller;
  final bool? open;
  final bool initiallyOpen;
  final ValueChanged<DDialogChangeDetails<T>>? onOpenChanged;
  final bool useRootNavigator;
  final bool dismissOnEscape;
  final String barrierLabel;
  final RouteSettings? routeSettings;
  final FocusNode? initialFocusNode;
  final FocusNode? finalFocusNode;

  @override
  Widget build(BuildContext context) => DDialog<T>(
    controller: controller,
    open: open,
    initiallyOpen: initiallyOpen,
    onOpenChanged: onOpenChanged,
    useRootNavigator: useRootNavigator,
    // A confirmation must receive an explicit response. Base UI ignores
    // outside presses while still allowing Escape to mean cancel.
    dismissOnBarrier: false,
    dismissOnEscape: dismissOnEscape,
    barrierLabel: barrierLabel,
    routeSettings: routeSettings,
    initialFocusNode: initialFocusNode,
    finalFocusNode: finalFocusNode,
    trigger: DDialogTrigger(builder: trigger.builder),
    content: content,
  );
}

typedef DAlertDialogTriggerBuilder =
    Widget Function(BuildContext context, VoidCallback open);

class DAlertDialogTrigger extends StatelessWidget {
  const DAlertDialogTrigger({super.key, required this.builder});

  final DAlertDialogTriggerBuilder builder;

  @override
  Widget build(BuildContext context) => DDialogTrigger(builder: builder);
}

class _DAlertDialogScope extends InheritedWidget {
  const _DAlertDialogScope({required this.size, required super.child});

  final DAlertDialogSize size;

  static DAlertDialogSize sizeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DAlertDialogScope>()?.size ??
      DAlertDialogSize.regular;

  @override
  bool updateShouldNotify(_DAlertDialogScope oldWidget) =>
      oldWidget.size != size;
}

/// The base-nova popup surface. Default dialogs grow from 320 to 384 logical
/// pixels at the reference's 640px breakpoint; small dialogs stay at 320px.
class DAlertDialogContent extends StatelessWidget {
  const DAlertDialogContent({
    super.key,
    required this.children,
    this.size = DAlertDialogSize.regular,
    this.semanticLabel,
    this.maxWidth,
  }) : assert(maxWidth == null || maxWidth > 0);

  final List<Widget> children;
  final DAlertDialogSize size;
  final String? semanticLabel;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final windowWide = MediaQuery.sizeOf(context).width >= 640;
    final width =
        maxWidth ??
        (size == DAlertDialogSize.regular && windowWide ? 384.0 : 320.0);
    final radius = BorderRadius.circular(tokens.radius * 1.4);
    final body = Material(
      animationDuration: Duration.zero,
      color: tokens.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: DiscourseTypography.sm,
        height: 20 / 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: tokens.foreground,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: DSpacing.lg),
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(height: DSpacing.lg),
            if (children[index] is DAlertDialogFooter)
              children[index]
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: DSpacing.lg),
                child: children[index],
              ),
          ],
          if (children.isEmpty || children.last is! DAlertDialogFooter)
            const SizedBox(height: DSpacing.lg),
        ],
      ),
    );
    return _DAlertDialogScope(
      size: size,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        scopesRoute: true,
        label: semanticLabel,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: tokens.foreground.withValues(alpha: .1),
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

/// Responsive header matching the media, default, and small compositions.
class DAlertDialogHeader extends StatelessWidget {
  const DAlertDialogHeader({
    super.key,
    required this.title,
    required this.description,
    this.media,
  });

  final Widget title;
  final Widget description;
  final Widget? media;

  @override
  Widget build(BuildContext context) {
    final size = _DAlertDialogScope.sizeOf(context);
    final wideRegular =
        size == DAlertDialogSize.regular &&
        MediaQuery.sizeOf(context).width >= 640;
    if (wideRegular && media != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          media!,
          const SizedBox(width: DSpacing.lg),
          Expanded(child: _text(context, TextAlign.start)),
        ],
      );
    }
    if (wideRegular) return _text(context, TextAlign.start);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (media != null) ...[
          Align(child: media),
          const SizedBox(height: DSpacing.md),
        ],
        _text(context, TextAlign.center),
      ],
    );
  }

  Widget _text(BuildContext context, TextAlign alignment) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: alignment == TextAlign.start
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.stretch,
    children: [
      DAlertDialogTitle(textAlign: alignment, child: title),
      const SizedBox(height: 6),
      DAlertDialogDescription(textAlign: alignment, child: description),
    ],
  );
}

class DAlertDialogMedia extends StatelessWidget {
  const DAlertDialogMedia({
    super.key,
    required this.child,
    this.destructive = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  final Widget child;
  final bool destructive;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground =
        foregroundColor ??
        (destructive ? tokens.destructive : tokens.foreground);
    final background =
        backgroundColor ??
        (destructive
            ? tokens.destructive.withValues(alpha: dark ? .2 : .1)
            : tokens.muted);
    return Semantics(
      container: true,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(tokens.radius * .8),
          ),
          child: SizedBox.square(
            dimension: 40,
            child: IconTheme(
              data: IconThemeData(size: 24, color: foreground),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class DAlertDialogTitle extends StatelessWidget {
  const DAlertDialogTitle({
    super.key,
    required this.child,
    this.textAlign = TextAlign.center,
  });

  final Widget child;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    namesRoute: true,
    child: DefaultTextStyle(
      textAlign: textAlign,
      style: Theme.of(context).textTheme.titleMedium!.copyWith(
        fontSize: DiscourseTypography.base,
        height: 24 / 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: DTokens.of(context).foreground,
      ),
      child: child,
    ),
  );
}

class DAlertDialogDescription extends StatelessWidget {
  const DAlertDialogDescription({
    super.key,
    required this.child,
    this.textAlign = TextAlign.center,
  });

  final Widget child;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    textAlign: textAlign,
    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: DiscourseTypography.sm,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: DTokens.of(context).mutedForeground,
    ),
    child: child,
  );
}

/// A visible, live-region failure message for caller-owned async operations.
class DAlertDialogError extends StatelessWidget {
  const DAlertDialogError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: DTokens.of(context).destructive),
    ),
  );
}

class DAlertDialogFooter extends StatelessWidget {
  const DAlertDialogFooter({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final small = _DAlertDialogScope.sizeOf(context) == DAlertDialogSize.small;
    final wide = MediaQuery.sizeOf(context).width >= 640;
    Widget actions;
    if (small) {
      actions = Row(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(width: DSpacing.sm),
            Expanded(child: children[index]),
          ],
        ],
      );
    } else if (wide) {
      actions = Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(width: DSpacing.sm),
            children[index],
          ],
        ],
      );
    } else {
      actions = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = children.length - 1; index >= 0; index--) ...[
            if (index != children.length - 1)
              const SizedBox(height: DSpacing.sm),
            children[index],
          ],
        ],
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.muted.withValues(alpha: tokens.muted.a * .5),
        border: Border(top: BorderSide(color: tokens.border)),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(tokens.radius * 1.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DSpacing.lg),
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: actions,
        ),
      ),
    );
  }
}

class DAlertDialogCancel<T> extends StatelessWidget {
  const DAlertDialogCancel({
    super.key,
    required this.label,
    this.result,
    this.onPressed,
    this.enabled = true,
    this.loading = false,
    this.semanticLabel,
  });

  final Widget label;
  final T? result;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool loading;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => FocusTraversalOrder(
    order: const NumericFocusOrder(1),
    child: DDialogClose<T>(
      result: result,
      builder: (context, close) => DButton(
        label: label,
        semanticLabel: semanticLabel,
        loading: loading,
        variant: DButtonVariant.outline,
        onPressed: enabled && !loading
            ? () {
                onPressed?.call();
                close();
              }
            : null,
      ),
    ),
  );
}

/// The affirmative action. By default it closes with [result]. Set
/// [closeOnPressed] to false for caller-owned async work and close through the
/// root controller only after success, or use [onSubmit] with [controller].
class DAlertDialogAction<T> extends StatelessWidget {
  const DAlertDialogAction({
    super.key,
    required this.label,
    this.result,
    this.onPressed,
    this.variant = DButtonVariant.primary,
    this.enabled = true,
    this.loading = false,
    this.closeOnPressed = true,
    this.controller,
    this.onSubmit,
    this.onError,
    this.semanticLabel,
  }) : assert((controller == null) == (onSubmit == null)),
       assert(onSubmit == null || !closeOnPressed);

  final Widget label;
  final T? result;
  final VoidCallback? onPressed;
  final DButtonVariant variant;
  final bool enabled;
  final bool loading;
  final bool closeOnPressed;
  final DDialogController<T>? controller;
  final Future<T> Function()? onSubmit;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final String? semanticLabel;

  void _submit() {
    final future = controller!.submit(onSubmit!);
    unawaited(
      future.then<void>((_) {}).catchError((Object error, StackTrace stack) {
        onError?.call(error, stack);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget buildButton(bool controllerBusy, VoidCallback close) => DButton(
      label: label,
      semanticLabel: semanticLabel,
      variant: variant,
      loading: loading || controllerBusy,
      invalid: false,
      onPressed: enabled && !loading && !controllerBusy
          ? () {
              onPressed?.call();
              if (onSubmit != null) {
                _submit();
              } else if (closeOnPressed) {
                close();
              }
            }
          : null,
    );

    return FocusTraversalOrder(
      order: const NumericFocusOrder(2),
      child: DDialogClose<T>(
        result: result,
        builder: (context, close) {
          final owner = controller;
          if (owner == null) return buildButton(false, close);
          return AnimatedBuilder(
            animation: owner,
            builder: (context, _) => buildButton(owner.isBusy, close),
          );
        },
      ),
    );
  }
}

/// Opens a route-owned Alert Dialog. Outside presses are intentionally ignored;
/// Escape remains an explicit cancellation path unless disabled by the caller.
Future<T?> showDAlertDialog<T>({
  required BuildContext context,
  required DDialogContentBuilder<T> builder,
  bool useRootNavigator = false,
  bool dismissOnEscape = true,
  String barrierLabel = 'Alert dialog',
  RouteSettings? routeSettings,
  FocusNode? initialFocusNode,
  FocusNode? finalFocusNode,
}) => showDDialog<T>(
  context: context,
  builder: builder,
  useRootNavigator: useRootNavigator,
  dismissOnBarrier: false,
  dismissOnEscape: dismissOnEscape,
  barrierLabel: barrierLabel,
  routeSettings: routeSettings,
  initialFocusNode: initialFocusNode,
  finalFocusNode: finalFocusNode,
);
