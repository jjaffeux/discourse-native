import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_spinner.dart';

/// Visual status used by the built-in shadcn toast renderer.
enum DToastType { standard, success, info, warning, error, loading }

/// Placement of the toast viewport inside its local [DToaster] scope.
enum DToastPosition {
  topStart,
  topCenter,
  topEnd,
  bottomStart,
  bottomCenter,
  bottomEnd,
}

enum DToastCloseReason {
  timeout,
  action,
  closeButton,
  swipe,
  replacement,
  programmatic,
  limit,
}

enum DToastPriority { normal, high }

@immutable
class DToastAction {
  const DToastAction({
    required this.label,
    required this.onPressed,
    this.dismissOnPressed = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool dismissOnPressed;
  final String? semanticLabel;
}

typedef DToastContentBuilder =
    Widget Function(BuildContext context, DToastEntry toast);

/// Immutable content and behavior for a toast.
@immutable
class DToastOptions {
  const DToastOptions({
    this.title,
    this.description,
    this.type = DToastType.standard,
    this.action,
    this.duration = const Duration(seconds: 5),
    this.priority = DToastPriority.normal,
    this.contentBuilder,
    this.data,
    this.showClose = true,
    this.onClose,
  }) : assert(
         title != null || description != null || contentBuilder != null,
         'A toast needs a title, description, or custom content.',
       );

  final String? title;
  final String? description;
  final DToastType type;
  final DToastAction? action;

  /// Null keeps the toast open until explicitly dismissed. Loading toasts
  /// created by [DToastController.promise] use this automatically.
  final Duration? duration;
  final DToastPriority priority;
  final DToastContentBuilder? contentBuilder;
  final Object? data;
  final bool showClose;
  final ValueChanged<DToastCloseReason>? onClose;

  DToastOptions copyWith({
    String? title,
    String? description,
    DToastType? type,
    DToastAction? action,
    Duration? duration,
    bool clearDuration = false,
    DToastPriority? priority,
    DToastContentBuilder? contentBuilder,
    Object? data,
    bool? showClose,
    ValueChanged<DToastCloseReason>? onClose,
  }) => DToastOptions(
    title: title ?? this.title,
    description: description ?? this.description,
    type: type ?? this.type,
    action: action ?? this.action,
    duration: clearDuration ? null : (duration ?? this.duration),
    priority: priority ?? this.priority,
    contentBuilder: contentBuilder ?? this.contentBuilder,
    data: data ?? this.data,
    showClose: showClose ?? this.showClose,
    onClose: onClose ?? this.onClose,
  );
}

@immutable
class DToastEntry {
  const DToastEntry({
    required this.id,
    required this.options,
    required this.revision,
  });

  final Object id;
  final DToastOptions options;
  final int revision;
}

typedef DToastResultBuilder<T> = DToastOptions Function(T value);
typedef DToastErrorBuilder = DToastOptions Function(Object error);

/// Controls one toast scope. Callers dispose controllers they create.
///
/// Reusing an id updates that toast in place and restarts its timeout. Promise
/// completions only update the exact still-mounted revision they created.
class DToastController extends ChangeNotifier {
  DToastController({this.limit = 3}) : assert(limit > 0);

  final int limit;
  final List<DToastEntry> _toasts = [];
  final Map<Object, Timer> _timers = {};
  final Map<Object, Duration> _remaining = {};
  final Map<Object, Stopwatch> _elapsed = {};
  final Set<Object> _pauseOwners = {};
  int _nextId = 0;
  bool _disposed = false;

  static final Object _manualPauseOwner = Object();

  List<DToastEntry> get toasts => List.unmodifiable(_toasts);
  bool get isDisposed => _disposed;

  Object add(DToastOptions options, {Object? id}) {
    if (_disposed) return id ?? Object();
    final resolvedId = id ?? ++_nextId;
    final index = _toasts.indexWhere((toast) => toast.id == resolvedId);
    final revision = index < 0 ? 0 : _toasts[index].revision + 1;
    final entry = DToastEntry(
      id: resolvedId,
      options: options,
      revision: revision,
    );
    if (index < 0) {
      _toasts.add(entry);
    } else {
      final replaced = _toasts[index];
      _toasts[index] = entry;
      _startTimer(entry);
      replaced.options.onClose?.call(DToastCloseReason.replacement);
    }
    if (index < 0) _startTimer(entry);
    while (_toasts.length > limit) {
      _remove(_toasts.first.id, DToastCloseReason.limit);
    }
    notifyListeners();
    return resolvedId;
  }

  bool update(Object id, DToastOptions options) {
    if (_disposed) return false;
    final index = _toasts.indexWhere((toast) => toast.id == id);
    if (index < 0) return false;
    final entry = DToastEntry(
      id: id,
      options: options,
      revision: _toasts[index].revision + 1,
    );
    final replaced = _toasts[index];
    _toasts[index] = entry;
    _startTimer(entry);
    replaced.options.onClose?.call(DToastCloseReason.replacement);
    notifyListeners();
    return true;
  }

  bool close(
    Object id, {
    DToastCloseReason reason = DToastCloseReason.programmatic,
  }) {
    if (_disposed || !_toasts.any((toast) => toast.id == id)) return false;
    _remove(id, reason);
    notifyListeners();
    return true;
  }

  void closeAll({DToastCloseReason reason = DToastCloseReason.programmatic}) {
    if (_disposed) return;
    final ids = _toasts.map((toast) => toast.id).toList(growable: false);
    for (final id in ids) {
      _remove(id, reason);
    }
    notifyListeners();
  }

  Object promise<T>(
    Future<T> future, {
    required DToastOptions loading,
    required DToastResultBuilder<T> success,
    required DToastErrorBuilder error,
    Object? id,
  }) {
    final loadingOptions = loading.copyWith(
      type: DToastType.loading,
      clearDuration: true,
    );
    final resolvedId = add(loadingOptions, id: id);
    final revision = _entry(resolvedId)?.revision;
    unawaited(
      future.then(
        (value) {
          if (_disposed || _entry(resolvedId)?.revision != revision) return;
          update(resolvedId, success(value).copyWith(type: DToastType.success));
        },
        onError: (Object failure, StackTrace _) {
          if (_disposed || _entry(resolvedId)?.revision != revision) return;
          update(resolvedId, error(failure).copyWith(type: DToastType.error));
        },
      ),
    );
    return resolvedId;
  }

  void pause() {
    _pause(_manualPauseOwner);
  }

  void _pause(Object owner) {
    if (_disposed || !_pauseOwners.add(owner) || _pauseOwners.length != 1) {
      return;
    }
    for (final timer in _timers.values) {
      timer.cancel();
    }
    for (final entry in _toasts) {
      final watch = _elapsed[entry.id];
      final remaining = _remaining[entry.id];
      if (watch != null && remaining != null) {
        _remaining[entry.id] = remaining - watch.elapsed;
      }
    }
    _timers.clear();
    _elapsed.clear();
  }

  void resume() {
    _resume(_manualPauseOwner);
  }

  void _resume(Object owner) {
    if (_disposed || !_pauseOwners.remove(owner) || _pauseOwners.isNotEmpty) {
      return;
    }
    for (final entry in _toasts) {
      _schedule(entry, _remaining[entry.id]);
    }
  }

  DToastEntry? _entry(Object id) {
    for (final toast in _toasts) {
      if (toast.id == id) return toast;
    }
    return null;
  }

  void _startTimer(DToastEntry entry) {
    _timers.remove(entry.id)?.cancel();
    _elapsed.remove(entry.id);
    final duration = entry.options.duration;
    if (duration == null) {
      _remaining.remove(entry.id);
      return;
    }
    _remaining[entry.id] = duration;
    if (_pauseOwners.isEmpty) _schedule(entry, duration);
  }

  void _schedule(DToastEntry entry, Duration? duration) {
    if (duration == null) return;
    if (duration <= Duration.zero) {
      scheduleMicrotask(
        () => close(entry.id, reason: DToastCloseReason.timeout),
      );
      return;
    }
    final watch = Stopwatch()..start();
    _elapsed[entry.id] = watch;
    _timers[entry.id] = Timer(duration, () {
      if (_entry(entry.id)?.revision == entry.revision) {
        close(entry.id, reason: DToastCloseReason.timeout);
      }
    });
  }

  void _remove(Object id, DToastCloseReason reason) {
    final index = _toasts.indexWhere((toast) => toast.id == id);
    if (index < 0) return;
    final entry = _toasts.removeAt(index);
    _timers.remove(id)?.cancel();
    _elapsed.remove(id);
    _remaining.remove(id);
    entry.options.onClose?.call(reason);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _remaining.clear();
    _elapsed.clear();
    _pauseOwners.clear();
    _toasts.clear();
    super.dispose();
  }
}

/// Scoped access and convenience helpers for the nearest [DToaster].
abstract final class DToast {
  static DToastController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DToastScope>()!.controller;

  static DToastController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DToastScope>()?.controller;

  static Object? show(
    BuildContext context,
    String description, {
    String? title,
    DToastType type = DToastType.standard,
    DToastAction? action,
    Duration? duration = const Duration(seconds: 5),
    Object? id,
    DToastPriority priority = DToastPriority.normal,
  }) => maybeOf(context)?.add(
    DToastOptions(
      title: title,
      description: description,
      type: type,
      action: action,
      duration: duration,
      priority: priority,
    ),
    id: id,
  );
}

/// Hosts a locally scoped toast manager and renderer.
///
/// When [controller] is null the host owns and disposes a controller. A passed
/// controller is borrowed. Removing this widget therefore cancels only owned
/// timers; late promise completions never target a replacement scope.
class DToaster extends StatefulWidget {
  const DToaster({
    super.key,
    required this.child,
    this.controller,
    this.position = DToastPosition.bottomEnd,
    this.limit = 3,
    this.viewportPadding = const EdgeInsets.all(16),
  });

  final Widget child;
  final DToastController? controller;
  final DToastPosition position;
  final int limit;
  final EdgeInsetsGeometry viewportPadding;

  @override
  State<DToaster> createState() => _DToasterState();
}

class _DToasterState extends State<DToaster> with WidgetsBindingObserver {
  late DToastController _controller;
  late bool _ownsController;
  final FocusNode _viewportFocus = FocusNode(debugLabel: 'Toast viewport');
  final Object _lifecyclePauseOwner = Object();
  late bool _lifecyclePaused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecyclePaused =
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
    _setController();
  }

  void _setController() {
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? DToastController(limit: widget.limit);
    if (_lifecyclePaused) _controller._pause(_lifecyclePauseOwner);
  }

  @override
  void didUpdateWidget(DToaster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller &&
        (widget.controller != null || oldWidget.limit == widget.limit)) {
      return;
    }
    _controller._resume(_lifecyclePauseOwner);
    if (_ownsController) _controller.dispose();
    _setController();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecyclePaused = state != AppLifecycleState.resumed;
    if (!_lifecyclePaused) {
      _controller._resume(_lifecyclePauseOwner);
    } else {
      _controller._pause(_lifecyclePauseOwner);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewportFocus.dispose();
    _controller._resume(_lifecyclePauseOwner);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DToastScope(
    controller: _controller,
    child: Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.f6): _FocusToastViewportIntent(),
      },
      child: Actions(
        actions: {
          _FocusToastViewportIntent: CallbackAction<_FocusToastViewportIntent>(
            onInvoke: (_) {
              if (_controller.toasts.isNotEmpty) _viewportFocus.requestFocus();
              return null;
            },
          ),
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            _DToastViewport(
              controller: _controller,
              focusNode: _viewportFocus,
              position: widget.position,
              padding: widget.viewportPadding,
            ),
          ],
        ),
      ),
    ),
  );
}

class _DToastScope extends InheritedWidget {
  const _DToastScope({required this.controller, required super.child});
  final DToastController controller;

  @override
  bool updateShouldNotify(_DToastScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}

class _FocusToastViewportIntent extends Intent {
  const _FocusToastViewportIntent();
}

class _DToastViewport extends StatefulWidget {
  const _DToastViewport({
    required this.controller,
    required this.focusNode,
    required this.position,
    required this.padding,
  });
  final DToastController controller;
  final FocusNode focusNode;
  final DToastPosition position;
  final EdgeInsetsGeometry padding;

  @override
  State<_DToastViewport> createState() => _DToastViewportState();
}

class _DToastViewportState extends State<_DToastViewport> {
  bool _hovered = false;
  bool _focused = false;
  final Object _interactionPauseOwner = Object();

  void _syncInteractionPause() {
    if (_hovered || _focused) {
      widget.controller._pause(_interactionPauseOwner);
    } else {
      widget.controller._resume(_interactionPauseOwner);
    }
  }

  @override
  void didUpdateWidget(_DToastViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller._resume(_interactionPauseOwner);
    _syncInteractionPause();
  }

  @override
  void dispose() {
    widget.controller._resume(_interactionPauseOwner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final entries = widget.controller.toasts.reversed.toList();
      if (entries.isEmpty) return const SizedBox.shrink();
      final top = switch (widget.position) {
        DToastPosition.topStart ||
        DToastPosition.topCenter ||
        DToastPosition.topEnd => true,
        _ => false,
      };
      final alignment = switch (widget.position) {
        DToastPosition.topStart => AlignmentDirectional.topStart,
        DToastPosition.topCenter => Alignment.topCenter,
        DToastPosition.topEnd => AlignmentDirectional.topEnd,
        DToastPosition.bottomStart => AlignmentDirectional.bottomStart,
        DToastPosition.bottomCenter => Alignment.bottomCenter,
        DToastPosition.bottomEnd => AlignmentDirectional.bottomEnd,
      };
      final ordered = top ? entries.reversed.toList() : entries;
      return SafeArea(
        minimum: widget.padding.resolve(Directionality.of(context)),
        child: Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 384),
            child: MouseRegion(
              onEnter: (_) {
                setState(() => _hovered = true);
                _syncInteractionPause();
              },
              onExit: (_) {
                setState(() => _hovered = false);
                _syncInteractionPause();
              },
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                },
                child: Actions(
                  actions: {
                    DismissIntent: CallbackAction<DismissIntent>(
                      onInvoke: (_) {
                        widget.controller.close(entries.first.id);
                        return null;
                      },
                    ),
                  },
                  child: Focus(
                    focusNode: widget.focusNode,
                    onFocusChange: (focused) {
                      _focused = focused;
                      _syncInteractionPause();
                    },
                    child: Semantics(
                      container: true,
                      label: 'Notifications',
                      child: SingleChildScrollView(
                        primary: false,
                        reverse: !top,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          verticalDirection: top
                              ? VerticalDirection.down
                              : VerticalDirection.up,
                          children: [
                            for (final entry in ordered)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: _DToastCard(
                                  key: ValueKey((entry.id, entry.revision)),
                                  entry: entry,
                                  controller: widget.controller,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _DToastCard extends StatefulWidget {
  const _DToastCard({super.key, required this.entry, required this.controller});
  final DToastEntry entry;
  final DToastController controller;

  @override
  State<_DToastCard> createState() => _DToastCardState();
}

class _DToastCardState extends State<_DToastCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final options = widget.entry.options;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(tokens.radius * 1.8);
    final card = AnimatedContainer(
      duration: DMotion.duration(context, DMotion.change),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: radius,
        border: Border.all(color: _focused ? tokens.focusRing : tokens.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .14),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      foregroundDecoration: _focused
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radius * 1.8 + 3),
              border: Border.all(
                color: tokens.focusRing.withValues(
                  alpha: tokens.focusRing.a * .5,
                ),
                width: 3,
              ),
            )
          : null,
      child:
          options.contentBuilder?.call(context, widget.entry) ??
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (options.type != DToastType.standard) ...[
                  _DToastStatusIcon(type: options.type),
                  const SizedBox(width: 12),
                ],
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (options.title != null)
                        Text(
                          options.title!,
                          style: textTheme.bodyMedium?.copyWith(
                            fontSize: DiscourseTypography.sm,
                            height: DiscourseTypography.lineHeightSmall,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                          ),
                        ),
                      if (options.title != null && options.description != null)
                        const SizedBox(height: 4),
                      if (options.description != null)
                        Text(
                          options.description!,
                          style: textTheme.bodyMedium?.copyWith(
                            fontSize: DiscourseTypography.sm,
                            height: DiscourseTypography.lineHeightSmall,
                            fontWeight: FontWeight.normal,
                            letterSpacing: 0,
                            color: tokens.mutedForeground,
                          ),
                        ),
                    ],
                  ),
                ),
                if (options.action case final action?) ...[
                  const SizedBox(width: 12),
                  DButton(
                    label: Text(action.label),
                    semanticLabel: action.semanticLabel,
                    variant: DButtonVariant.outline,
                    size: DButtonSize.small,
                    onPressed: action.onPressed == null
                        ? null
                        : () {
                            action.onPressed!();
                            if (action.dismissOnPressed) {
                              widget.controller.close(
                                widget.entry.id,
                                reason: DToastCloseReason.action,
                              );
                            }
                          },
                  ),
                ],
                if (options.showClose) ...[
                  const SizedBox(width: 4),
                  DButton.iconOnly(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: 'Close toast',
                    semanticLabel: 'Close notification',
                    variant: DButtonVariant.ghost,
                    size: DButtonSize.extraSmall,
                    onPressed: () => widget.controller.close(
                      widget.entry.id,
                      reason: DToastCloseReason.closeButton,
                    ),
                  ),
                ],
              ],
            ),
          ),
    );
    return Semantics(
      liveRegion: true,
      container: true,
      label: [
        if (options.title != null) options.title,
        if (options.description != null) options.description,
      ].whereType<String>().join('. '),
      child: FocusableActionDetector(
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              widget.controller.close(widget.entry.id);
              return null;
            },
          ),
        },
        child: Dismissible(
          key: ValueKey(widget.entry.id),
          direction: _dismissDirection(context),
          movementDuration: DMotion.duration(
            context,
            const Duration(milliseconds: 500),
          ),
          resizeDuration: DMotion.duration(
            context,
            const Duration(milliseconds: 500),
          ),
          onDismissed: (_) => widget.controller.close(
            widget.entry.id,
            reason: DToastCloseReason.swipe,
          ),
          child: card,
        ),
      ),
    );
  }

  DismissDirection _dismissDirection(BuildContext context) {
    final touch =
        MediaQuery.maybeOf(context)?.gestureSettings.touchSlop != null;
    return touch || defaultTargetPlatform == TargetPlatform.iOS
        ? DismissDirection.horizontal
        : DismissDirection.endToStart;
  }
}

class _DToastStatusIcon extends StatelessWidget {
  const _DToastStatusIcon({required this.type});
  final DToastType type;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    if (type == DToastType.loading) {
      return const DSpinner(size: 16, semanticLabel: null);
    }
    final icon = switch (type) {
      DToastType.success => Icons.check_circle_outline,
      DToastType.info => Icons.info_outline,
      DToastType.warning => Icons.warning_amber_outlined,
      DToastType.error => Icons.cancel_outlined,
      _ => null,
    };
    return Icon(
      icon,
      size: 16,
      color: type == DToastType.error ? tokens.destructive : tokens.foreground,
    );
  }
}
