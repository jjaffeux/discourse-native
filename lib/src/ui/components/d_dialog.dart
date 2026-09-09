import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';

/// Why an open-state change was requested.
enum DDialogChangeReason {
  trigger,
  barrier,
  escape,
  close,
  programmatic,
  routeRemoved,
}

@immutable
class DDialogChangeDetails<T> {
  const DDialogChangeDetails({
    required this.open,
    required this.reason,
    this.result,
  });

  final bool open;
  final DDialogChangeReason reason;
  final T? result;
}

/// Imperative and asynchronous state for a mounted [DDialog].
///
/// A caller-created controller is borrowed and is never disposed by the dialog.
/// [submit] coalesces repeated activation, keeps errors with the caller, and only
/// closes the same still-open attachment that started the operation.
class DDialogController<T> extends ChangeNotifier {
  DDialogController({bool initiallyOpen = false}) : _open = initiallyOpen;

  bool _open;
  bool _busy = false;
  Object? _attachment;
  void Function()? _requestOpen;
  void Function(T? result, DDialogChangeReason reason)? _requestClose;
  Future<T?>? _submission;

  bool get isOpen => _open;
  bool get isBusy => _busy;

  void open() => _requestOpen?.call();

  void close([T? result]) =>
      _requestClose?.call(result, DDialogChangeReason.programmatic);

  Future<T?> submit(Future<T> Function() operation) {
    final current = _submission;
    if (current != null) return current;
    final attachment = _attachment;
    final completer = Completer<T?>();
    _submission = completer.future;
    _busy = true;
    notifyListeners();
    Future<T>.sync(operation)
        .then(
          (result) {
            if (_attachment == attachment && _open) close(result);
            completer.complete(result);
          },
          onError: (Object error, StackTrace stackTrace) {
            completer.completeError(error, stackTrace);
          },
        )
        .whenComplete(() {
          if (_submission == completer.future) {
            _submission = null;
            _busy = false;
            notifyListeners();
          }
        })
        .ignore();
    return completer.future;
  }

  void _attach(
    Object attachment,
    void Function() requestOpen,
    void Function(T?, DDialogChangeReason) requestClose,
  ) {
    _attachment = attachment;
    _requestOpen = requestOpen;
    _requestClose = requestClose;
  }

  void _detach(Object attachment) {
    if (_attachment != attachment) return;
    _attachment = null;
    _requestOpen = null;
    _requestClose = null;
  }

  void _setOpen(bool value) {
    if (_open == value) return;
    _open = value;
    notifyListeners();
  }
}

typedef DDialogTriggerBuilder =
    Widget Function(BuildContext context, VoidCallback open);

/// Composes any trigger widget with the root dialog state.
class DDialogTrigger extends StatelessWidget {
  const DDialogTrigger({super.key, required this.builder});

  final DDialogTriggerBuilder builder;

  @override
  Widget build(BuildContext context) {
    final scope = _DDialogRootScope.of(context);
    return builder(context, scope.open);
  }
}

/// Declarative Dialog root with either internal or caller-controlled open state.
class DDialog<T> extends StatefulWidget {
  const DDialog({
    super.key,
    required this.trigger,
    required this.content,
    this.controller,
    this.open,
    this.initiallyOpen = false,
    this.onOpenChanged,
    this.useRootNavigator = false,
    this.dismissOnBarrier = true,
    this.dismissOnEscape = true,
    this.barrierLabel = 'Dismiss dialog',
    this.routeSettings,
    this.initialFocusNode,
    this.finalFocusNode,
  }) : assert(open == null || !initiallyOpen);

  final DDialogTrigger trigger;
  final Widget content;
  final DDialogController<T>? controller;

  /// Non-null makes the open state controlled by the caller.
  final bool? open;
  final bool initiallyOpen;
  final ValueChanged<DDialogChangeDetails<T>>? onOpenChanged;
  final bool useRootNavigator;
  final bool dismissOnBarrier;
  final bool dismissOnEscape;
  final String barrierLabel;
  final RouteSettings? routeSettings;
  final FocusNode? initialFocusNode;
  final FocusNode? finalFocusNode;

  @override
  State<DDialog<T>> createState() => _DDialogState<T>();
}

class _DDialogState<T> extends State<DDialog<T>> {
  late DDialogController<T> _controller;
  late bool _internalOpen;
  final Object _attachment = Object();
  final ValueNotifier<_DDialogEnvironment?> _environment = ValueNotifier(null);
  _DDialogRoute<T>? _route;
  NavigatorState? _navigator;
  FocusNode? _previousFocus;
  DDialogChangeReason _closingReason = DDialogChangeReason.routeRemoved;
  T? _pendingResult;

  bool get _desiredOpen => widget.open ?? _internalOpen;

  @override
  void initState() {
    super.initState();
    _internalOpen = widget.controller?.isOpen ?? widget.initiallyOpen;
    _controller =
        widget.controller ?? DDialogController<T>(initiallyOpen: _internalOpen);
    _attachController();
    if (_desiredOpen) _scheduleSync();
  }

  @override
  void didUpdateWidget(DDialog<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller._detach(_attachment);
      if (oldWidget.controller == null) _controller.dispose();
      _controller =
          widget.controller ??
          DDialogController<T>(initiallyOpen: _desiredOpen);
      _attachController();
    }
    _controller._setOpen(_desiredOpen);
    _scheduleSync();
  }

  void _attachController() => _controller._attach(
    _attachment,
    () => _requestOpen(DDialogChangeReason.programmatic),
    _requestClose,
  );

  void _scheduleSync() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _syncRoute();
  });

  void _requestOpen(DDialogChangeReason reason) {
    if (_desiredOpen) return;
    widget.onOpenChanged?.call(
      DDialogChangeDetails(open: true, reason: reason),
    );
    if (widget.open != null) return;
    setState(() => _internalOpen = true);
    _controller._setOpen(true);
    _scheduleSync();
  }

  void _requestClose(T? result, DDialogChangeReason reason) {
    if (!_desiredOpen && _route == null) return;
    _closingReason = reason;
    _pendingResult = result;
    widget.onOpenChanged?.call(
      DDialogChangeDetails(open: false, reason: reason, result: result),
    );
    if (widget.open != null) return;
    setState(() => _internalOpen = false);
    _controller._setOpen(false);
    _route?.authorizePop(result);
  }

  void _syncRoute() {
    if (_desiredOpen) {
      if (_route == null) _present();
    } else {
      _route?.authorizePop(_pendingResult);
    }
  }

  void _present() {
    final navigator = Navigator.of(
      context,
      rootNavigator: widget.useRootNavigator,
    );
    _navigator = navigator;
    _previousFocus = FocusManager.instance.primaryFocus;
    final route = _DDialogRoute<T>(
      settings: widget.routeSettings,
      barrierLabel: widget.barrierLabel,
      dismissOnBarrier: widget.dismissOnBarrier,
      dismissOnEscape: widget.dismissOnEscape,
      environment: _environment,
      content: widget.content,
      dialogController: _controller,
      initialFocusNode: widget.initialFocusNode,
      onDismissRequested: (reason) => _requestClose(null, reason),
      onCloseRequested: (result) =>
          _requestClose(result, DDialogChangeReason.close),
      transitionDuration: DMotion.duration(context, DMotion.open),
      reverseTransitionDuration: DMotion.duration(context, DMotion.close),
    );
    _route = route;
    unawaited(
      navigator.push<T>(route).then((result) {
        if (!mounted || _route != route) return;
        _route = null;
        _navigator = null;
        _pendingResult = null;
        final wasOpen = _desiredOpen;
        if (widget.open == null) {
          setState(() => _internalOpen = false);
          _controller._setOpen(false);
        }
        if (wasOpen) {
          widget.onOpenChanged?.call(
            DDialogChangeDetails(
              open: false,
              reason: _closingReason,
              result: result,
            ),
          );
        }
        final target = widget.finalFocusNode ?? _previousFocus;
        if (target?.canRequestFocus ?? false) target!.requestFocus();
        _previousFocus = null;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nextEnvironment = _DDialogEnvironment.capture(context);
    if (_environment.value != nextEnvironment) {
      if (_route == null) {
        _environment.value = nextEnvironment;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _environment.value = nextEnvironment;
        });
      }
    }
    return _DDialogRootScope(
      open: () => _requestOpen(DDialogChangeReason.trigger),
      child: widget.trigger,
    );
  }

  @override
  void dispose() {
    _controller._setOpen(false);
    _controller._detach(_attachment);
    if (widget.controller == null) _controller.dispose();
    final route = _route;
    final navigator = _navigator;
    if (route != null && navigator != null) navigator.removeRoute(route);
    _environment.dispose();
    super.dispose();
  }
}

class _DDialogRootScope extends InheritedWidget {
  const _DDialogRootScope({required this.open, required super.child});

  final VoidCallback open;

  static _DDialogRootScope of(BuildContext context) {
    final result = context
        .dependOnInheritedWidgetOfExactType<_DDialogRootScope>();
    assert(result != null, 'DDialogTrigger must be below a DDialog.');
    return result!;
  }

  @override
  bool updateShouldNotify(_DDialogRootScope oldWidget) =>
      open != oldWidget.open;
}

class _DDialogEnvironment {
  const _DDialogEnvironment({
    required this.theme,
    required this.mediaQuery,
    required this.directionality,
  });

  factory _DDialogEnvironment.capture(BuildContext context) =>
      _DDialogEnvironment(
        theme: Theme.of(context),
        mediaQuery: MediaQuery.of(context),
        directionality: Directionality.of(context),
      );

  final ThemeData theme;
  final MediaQueryData mediaQuery;
  final TextDirection directionality;

  Widget wrap(Widget child) => Theme(
    data: theme,
    child: MediaQuery(
      data: mediaQuery,
      child: Directionality(textDirection: directionality, child: child),
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is _DDialogEnvironment &&
      other.theme == theme &&
      other.mediaQuery == mediaQuery &&
      other.directionality == directionality;

  @override
  int get hashCode => Object.hash(theme, mediaQuery, directionality);
}

class _DDialogRoute<T> extends PopupRoute<T> {
  _DDialogRoute({
    super.settings,
    super.requestFocus = true,
    super.traversalEdgeBehavior = TraversalEdgeBehavior.closedLoop,
    super.directionalTraversalEdgeBehavior = TraversalEdgeBehavior.closedLoop,
    required this.barrierLabel,
    required this.dismissOnBarrier,
    required this.dismissOnEscape,
    required this.environment,
    required this.content,
    required this.dialogController,
    required this.initialFocusNode,
    required this.onDismissRequested,
    required this.onCloseRequested,
    required this.transitionDuration,
    required this.reverseTransitionDuration,
  });

  @override
  final String barrierLabel;
  final bool dismissOnBarrier;
  final bool dismissOnEscape;
  final ValueListenable<_DDialogEnvironment?> environment;
  final Widget content;
  final DDialogController<T> dialogController;
  final FocusNode? initialFocusNode;
  final ValueChanged<DDialogChangeReason> onDismissRequested;
  final ValueChanged<T?> onCloseRequested;
  @override
  final Duration transitionDuration;
  @override
  final Duration reverseTransitionDuration;
  bool _authorized = false;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => false;

  @override
  RoutePopDisposition get popDisposition =>
      _authorized ? RoutePopDisposition.pop : RoutePopDisposition.doNotPop;

  void authorizePop(T? result) {
    if (_authorized || !isActive) return;
    _authorized = true;
    navigator?.pop<T>(result);
  }

  @override
  void onPopInvokedWithResult(bool didPop, T? result) {
    super.onPopInvokedWithResult(didPop, result);
    if (!didPop && dismissOnEscape) {
      onDismissRequested(DDialogChangeReason.escape);
    }
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => ValueListenableBuilder<_DDialogEnvironment?>(
    valueListenable: environment,
    builder: (context, value, _) =>
        (value ?? _DDialogEnvironment.capture(context)).wrap(
          _DDialogRoutePage<T>(
            content: content,
            controller: dialogController,
            barrierLabel: barrierLabel,
            dismissOnBarrier: dismissOnBarrier,
            dismissOnEscape: dismissOnEscape,
            initialFocusNode: initialFocusNode,
            onBarrierDismiss: () =>
                onDismissRequested(DDialogChangeReason.barrier),
            onEscapeDismiss: () =>
                onDismissRequested(DDialogChangeReason.escape),
            onClose: onCloseRequested,
            animation: animation,
          ),
        ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

class _DDialogRoutePage<T> extends StatefulWidget {
  const _DDialogRoutePage({
    required this.content,
    required this.controller,
    required this.barrierLabel,
    required this.dismissOnBarrier,
    required this.dismissOnEscape,
    required this.initialFocusNode,
    required this.onBarrierDismiss,
    required this.onEscapeDismiss,
    required this.onClose,
    required this.animation,
  });

  final Widget content;
  final DDialogController<T> controller;
  final String barrierLabel;
  final bool dismissOnBarrier;
  final bool dismissOnEscape;
  final FocusNode? initialFocusNode;
  final VoidCallback onBarrierDismiss;
  final VoidCallback onEscapeDismiss;
  final ValueChanged<T?> onClose;
  final Animation<double> animation;

  @override
  State<_DDialogRoutePage<T>> createState() => _DDialogRoutePageState<T>();
}

class _DDialogRoutePageState<T> extends State<_DDialogRoutePage<T>> {
  final FocusScopeNode _focusScope = FocusScopeNode(debugLabel: 'DDialog');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final initial = widget.initialFocusNode;
      if (initial?.canRequestFocus ?? false) {
        initial!.requestFocus();
      } else {
        _focusScope.requestFocus();
        _focusScope.nextFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusScope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final insets = media.viewInsets;
    final curved = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final animate = !media.disableAnimations;
    Widget backdrop = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: ModalBarrier(
        color: Colors.black.withValues(alpha: .1),
        dismissible: widget.dismissOnBarrier,
        onDismiss: widget.onBarrierDismiss,
        semanticsLabel: widget.barrierLabel,
      ),
    );
    Widget popup = SafeArea(
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          DSpacing.lg,
          DSpacing.lg + insets.top,
          DSpacing.lg,
          DSpacing.lg + insets.bottom,
        ),
        child: Center(
          child: SingleChildScrollView(
            primary: false,
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: FocusScope(node: _focusScope, child: widget.content),
            ),
          ),
        ),
      ),
    );
    if (animate) {
      backdrop = FadeTransition(opacity: curved, child: backdrop);
      popup = FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: .95, end: 1).animate(curved),
          child: popup,
        ),
      );
    }
    Widget page = _DDialogContentScope(
      controller: widget.controller,
      close: (result) => widget.onClose(result as T?),
      child: Stack(
        children: [
          Positioned.fill(child: backdrop),
          Positioned.fill(child: popup),
        ],
      ),
    );
    if (widget.dismissOnEscape) {
      page = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape):
              widget.onEscapeDismiss,
        },
        child: page,
      );
    }
    return page;
  }
}

class _DDialogContentScope extends InheritedWidget {
  const _DDialogContentScope({
    required this.controller,
    required this.close,
    required super.child,
  });

  final Object controller;
  final ValueChanged<Object?> close;

  static _DDialogContentScope of(BuildContext context) {
    final result = context
        .dependOnInheritedWidgetOfExactType<_DDialogContentScope>();
    assert(result != null, 'DDialogClose must be inside a DDialogContent.');
    return result!;
  }

  @override
  bool updateShouldNotify(_DDialogContentScope oldWidget) =>
      controller != oldWidget.controller || close != oldWidget.close;
}

/// The base-nova popup surface.
class DDialogContent extends StatelessWidget {
  const DDialogContent({
    super.key,
    required this.children,
    this.showCloseButton = true,
    this.closeButton,
    this.closeSemanticLabel = 'Close',
    this.maxWidth = 384,
    this.semanticLabel,
  }) : assert(maxWidth > 0);

  final List<Widget> children;
  final bool showCloseButton;
  final Widget? closeButton;
  final String closeSemanticLabel;
  final double maxWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
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
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: DSpacing.lg),
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) const SizedBox(height: DSpacing.lg),
                if (children[index] is DDialogFooter)
                  children[index]
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DSpacing.lg,
                    ),
                    child: children[index],
                  ),
              ],
              if (children.isEmpty || children.last is! DDialogFooter)
                const SizedBox(height: DSpacing.lg),
            ],
          ),
          if (showCloseButton)
            PositionedDirectional(
              top: DSpacing.sm,
              end: DSpacing.sm,
              child:
                  closeButton ??
                  DDialogClose<void>(
                    builder: (context, close) => DButton.iconOnly(
                      onPressed: close,
                      size: DButtonSize.regular,
                      variant: DButtonVariant.ghost,
                      icon: const _DDialogCloseIcon(),
                      tooltip: closeSemanticLabel,
                      semanticLabel: closeSemanticLabel,
                      insetSurface: true,
                    ),
                  ),
            ),
        ],
      ),
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      scopesRoute: true,
      label: semanticLabel,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
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
    );
  }
}

class DDialogHeader extends StatelessWidget {
  const DDialogHeader({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < children.length; index++) ...[
        if (index > 0) const SizedBox(height: DSpacing.sm),
        children[index],
      ],
    ],
  );
}

class DDialogTitle extends StatelessWidget {
  const DDialogTitle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Semantics(
      header: true,
      namesRoute: true,
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.titleMedium!.copyWith(
          fontSize: DiscourseTypography.base,
          height: 1,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          color: tokens.foreground,
        ),
        child: child,
      ),
    );
  }
}

class DDialogDescription extends StatelessWidget {
  const DDialogDescription({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
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

/// Muted footer that stacks in reverse order below 640 logical pixels.
class DDialogFooter extends StatelessWidget {
  const DDialogFooter({
    super.key,
    required this.children,
    this.showCloseButton = false,
    this.closeLabel = 'Close',
  });

  final List<Widget> children;
  final bool showCloseButton;
  final String closeLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 640;
    final parts = <Widget>[
      ...children,
      if (showCloseButton)
        DDialogClose<void>(
          builder: (context, close) => DButton(
            onPressed: close,
            variant: DButtonVariant.outline,
            label: Text(closeLabel),
          ),
        ),
    ];
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
        child: wide
            ? Wrap(
                alignment: WrapAlignment.end,
                spacing: DSpacing.sm,
                runSpacing: DSpacing.sm,
                children: parts,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = parts.length - 1; index >= 0; index--) ...[
                    if (index != parts.length - 1)
                      const SizedBox(height: DSpacing.sm),
                    parts[index],
                  ],
                ],
              ),
      ),
    );
  }
}

/// Inner scrolling region used by the documented sticky/scrollable examples.
class DDialogScrollArea extends StatelessWidget {
  const DDialogScrollArea({
    super.key,
    required this.child,
    this.maxHeightFactor = .5,
    this.controller,
  }) : assert(maxHeightFactor > 0 && maxHeightFactor <= 1);

  final Widget child;
  final double maxHeightFactor;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
    ),
    child: SingleChildScrollView(controller: controller, child: child),
  );
}

typedef DDialogCloseBuilder =
    Widget Function(BuildContext context, VoidCallback close);

class DDialogClose<T> extends StatelessWidget {
  const DDialogClose({super.key, required this.builder, this.result});

  final DDialogCloseBuilder builder;
  final T? result;

  @override
  Widget build(BuildContext context) {
    final scope = _DDialogContentScope.of(context);
    return builder(context, () => scope.close(result));
  }
}

class _DDialogCloseIcon extends StatelessWidget {
  const _DDialogCloseIcon();

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 16,
    child: CustomPaint(
      painter: _DDialogCloseIconPainter(
        IconTheme.of(context).color ?? DTokens.of(context).foreground,
      ),
    ),
  );
}

class _DDialogCloseIconPainter extends CustomPainter {
  const _DDialogCloseIconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4 / 3
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(const Offset(4, 4), const Offset(12, 12), paint)
      ..drawLine(const Offset(12, 4), const Offset(4, 12), paint);
  }

  @override
  bool shouldRepaint(_DDialogCloseIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Opens a route-owned Dialog and returns its typed result.
Future<T?> showDDialog<T>({
  required BuildContext context,
  required DDialogContentBuilder<T> builder,
  bool useRootNavigator = false,
  bool dismissOnBarrier = true,
  bool dismissOnEscape = true,
  String barrierLabel = 'Dismiss dialog',
  RouteSettings? routeSettings,
  FocusNode? initialFocusNode,
  FocusNode? finalFocusNode,
}) async {
  final controller = DDialogController<T>(initiallyOpen: true);
  final environment = ValueNotifier<_DDialogEnvironment?>(null);
  final previousFocus = FocusManager.instance.primaryFocus;
  late _DDialogRoute<T> route;
  route = _DDialogRoute<T>(
    settings: routeSettings,
    barrierLabel: barrierLabel,
    dismissOnBarrier: dismissOnBarrier,
    dismissOnEscape: dismissOnEscape,
    environment: environment,
    content: builder(context, controller),
    dialogController: controller,
    initialFocusNode: initialFocusNode,
    onDismissRequested: (_) => route.authorizePop(null),
    onCloseRequested: (result) => route.authorizePop(result),
    transitionDuration: DMotion.duration(context, DMotion.open),
    reverseTransitionDuration: DMotion.duration(context, DMotion.close),
  );
  controller._attach(route, () {}, (result, _) => route.authorizePop(result));
  try {
    return await Navigator.of(
      context,
      rootNavigator: useRootNavigator,
    ).push<T>(route);
  } finally {
    controller._detach(route);
    controller.dispose();
    environment.dispose();
    final target = finalFocusNode ?? previousFocus;
    if (target?.canRequestFocus ?? false) target!.requestFocus();
  }
}

typedef DDialogContentBuilder<T> =
    Widget Function(BuildContext context, DDialogController<T> controller);
