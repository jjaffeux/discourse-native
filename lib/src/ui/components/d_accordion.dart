import 'dart:collection';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_collapsible.dart';

/// Explicit state owner for a [DAccordion]. Dispose borrowed instances in the
/// same object that created them. A root without a controller owns and disposes
/// an internal controller.
class DAccordionController<T> extends ChangeNotifier {
  DAccordionController({
    this.multiple = false,
    Iterable<T> initialValues = const [],
  }) : _values = _normalize(initialValues, multiple);

  final bool multiple;
  Set<T> _values;

  Set<T> get values => UnmodifiableSetView(_values);
  bool isOpen(T value) => _values.contains(value);

  void replace(Iterable<T> values) {
    final next = _normalize(values, multiple);
    if (setEquals(_values, next)) return;
    _values = next;
    notifyListeners();
  }

  void open(T value) => replace(multiple ? {..._values, value} : {value});
  void close(T value) => replace(_values.where((item) => item != value));
  void toggle(T value) => isOpen(value) ? close(value) : open(value);

  static Set<T> _normalize<T>(Iterable<T> values, bool multiple) {
    final result = LinkedHashSet<T>.of(values);
    if (!multiple && result.length > 1) return {result.first};
    return result;
  }
}

/// A vertically stacked group of disclosure items.
///
/// [values] selects controlled mode: activation reports through
/// [onValuesChange] and the caller must rebuild with the accepted values.
/// [controller] selects borrowed-controller mode. With neither, the root owns
/// local state initialized by [defaultValues]. Values must be stable and unique.
class DAccordion<T> extends StatefulWidget {
  const DAccordion({
    super.key,
    required this.children,
    this.values,
    this.defaultValues = const [],
    this.onValuesChange,
    this.controller,
    this.multiple = false,
    this.disabled = false,
    this.keepMounted = false,
    this.outlined = false,
  }) : assert(values == null || controller == null);

  final List<Widget> children;
  final Set<T>? values;
  final Iterable<T> defaultValues;
  final ValueChanged<Set<T>>? onValuesChange;
  final DAccordionController<T>? controller;
  final bool multiple;
  final bool disabled;
  final bool keepMounted;

  /// Reference Borders composition: a rounded outer border and 16px item inset.
  final bool outlined;

  @override
  State<DAccordion<T>> createState() => _DAccordionState<T>();
}

class _DAccordionState<T> extends State<DAccordion<T>> {
  late DAccordionController<T> _ownedController;
  final Map<T, int> _registrations = {};
  bool _pruneScheduled = false;

  DAccordionController<T> get _activeController =>
      widget.controller ?? _ownedController;
  bool get _controlled => widget.values != null;
  Set<T> get values => _controlled
      ? DAccordionController._normalize(widget.values!, widget.multiple)
      : _activeController.values;

  @override
  void initState() {
    super.initState();
    assert(
      widget.controller == null ||
          widget.controller!.multiple == widget.multiple,
      'The controller and DAccordion must use the same multiple value.',
    );
    _ownedController = DAccordionController<T>(
      multiple: widget.multiple,
      initialValues: widget.defaultValues,
    );
    if (!_controlled) _activeController.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(DAccordion<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      widget.controller == null ||
          widget.controller!.multiple == widget.multiple,
      'DAccordion and its controller must use the same multiple value.',
    );
    final wasControlled = oldWidget.values != null;
    final oldActive = oldWidget.controller ?? _ownedController;
    final oldValues = Set<T>.of(
      oldWidget.values == null
          ? oldActive.values
          : DAccordionController._normalize(
              oldWidget.values!,
              oldWidget.multiple,
            ),
    );
    if (!wasControlled) oldActive.removeListener(_controllerChanged);

    final becomingLocal = widget.values == null && widget.controller == null;
    if (_ownedController.multiple != widget.multiple) {
      final oldOwned = _ownedController;
      _ownedController = DAccordionController<T>(
        multiple: widget.multiple,
        initialValues: becomingLocal ? oldValues : oldOwned.values,
      );
      oldOwned.dispose();
    } else if (becomingLocal &&
        (oldWidget.values != null || oldWidget.controller != null)) {
      _ownedController.replace(oldValues);
    }
    if (!_controlled) _activeController.addListener(_controllerChanged);
  }

  void _controllerChanged() {
    if (mounted) setState(() {});
  }

  void _change(T value, bool open) {
    var next = LinkedHashSet<T>.of(values);
    if (open) {
      next = widget.multiple ? (next..add(value)) : LinkedHashSet.of([value]);
    } else {
      next.remove(value);
    }
    if (_controlled) {
      widget.onValuesChange?.call(UnmodifiableSetView(next));
    } else {
      _activeController.replace(next);
      widget.onValuesChange?.call(_activeController.values);
    }
  }

  void _register(T value) {
    _registrations.update(value, (count) => count + 1, ifAbsent: () => 1);
  }

  bool _debugItemsHaveUniqueValues() {
    final values = <T>{};
    for (final child in widget.children) {
      if (child is DAccordionItem<T> && !values.add(child.value)) return false;
    }
    return true;
  }

  void _unregister(T value) {
    final count = _registrations[value] ?? 0;
    if (count <= 1) {
      _registrations.remove(value);
    } else {
      _registrations[value] = count - 1;
    }
    if (_controlled || _pruneScheduled) return;
    _pruneScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pruneScheduled = false;
      if (!mounted || _controlled) return;
      _activeController.replace(
        _activeController.values.where(_registrations.containsKey),
      );
    });
  }

  @override
  void dispose() {
    if (!_controlled) _activeController.removeListener(_controllerChanged);
    _ownedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(
      _debugItemsHaveUniqueValues(),
      'Every direct DAccordionItem must have a unique value.',
    );
    final tokens = DTokens.of(context);
    Widget result = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < widget.children.length; index++)
          _DAccordionPosition(
            key: widget.children[index].key == null
                ? null
                : ValueKey<Key>(widget.children[index].key!),
            isLast: index == widget.children.length - 1,
            child: widget.children[index],
          ),
      ],
    );
    if (widget.outlined) {
      result = DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(tokens.radius),
        ),
        child: result,
      );
    }
    return _DAccordionVisualScope(
      keepMounted: widget.keepMounted,
      child: _DAccordionScope<T>(
        owner: this,
        values: Set<T>.unmodifiable(values),
        disabled: widget.disabled,
        outlined: widget.outlined,
        child: result,
      ),
    );
  }
}

class _DAccordionScope<T> extends InheritedWidget {
  const _DAccordionScope({
    required this.owner,
    required this.values,
    required this.disabled,
    required this.outlined,
    required super.child,
  });
  final _DAccordionState<T> owner;
  final Set<T> values;
  final bool disabled;
  final bool outlined;

  static _DAccordionScope<T> of<T>(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DAccordionScope<T>>();
    assert(scope != null, 'Accordion parts require a DAccordion<$T> ancestor.');
    return scope!;
  }

  @override
  bool updateShouldNotify(_DAccordionScope<T> oldWidget) =>
      !setEquals(values, oldWidget.values) ||
      disabled != oldWidget.disabled ||
      outlined != oldWidget.outlined;
}

class _DAccordionVisualScope extends InheritedWidget {
  const _DAccordionVisualScope({
    required this.keepMounted,
    required super.child,
  });
  final bool keepMounted;
  @override
  bool updateShouldNotify(_DAccordionVisualScope oldWidget) =>
      keepMounted != oldWidget.keepMounted;
}

class _DAccordionPosition extends InheritedWidget {
  const _DAccordionPosition({
    super.key,
    required this.isLast,
    required super.child,
  });
  final bool isLast;
  static bool isLastOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_DAccordionPosition>()
          ?.isLast ??
      false;
  @override
  bool updateShouldNotify(_DAccordionPosition oldWidget) =>
      isLast != oldWidget.isLast;
}

/// Groups one heading and its panel. [value] is the stable identity used by the
/// root. [onOpenChange] observes user requests after root/item disabled checks.
class DAccordionItem<T> extends StatefulWidget {
  const DAccordionItem({
    super.key,
    required this.value,
    required this.child,
    this.disabled = false,
    this.onOpenChange,
    this.border,
  });

  final T value;
  final Widget child;
  final bool disabled;
  final ValueChanged<bool>? onOpenChange;

  /// Null applies the base-nova bottom border except to the final item.
  final bool? border;

  @override
  State<DAccordionItem<T>> createState() => _DAccordionItemState<T>();
}

class _DAccordionItemState<T> extends State<DAccordionItem<T>> {
  _DAccordionState<T>? _owner;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = _DAccordionScope.of<T>(context).owner;
    if (_owner != owner) {
      _owner?._unregister(widget.value);
      _owner = owner;
      owner._register(widget.value);
    }
  }

  @override
  void didUpdateWidget(DAccordionItem<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _owner?._unregister(oldWidget.value);
      _owner?._register(widget.value);
    }
  }

  @override
  void dispose() {
    _owner?._unregister(widget.value);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _DAccordionScope.of<T>(context);
    final disabled = scope.disabled || widget.disabled;
    final open = scope.values.contains(widget.value);
    final showBorder = widget.border ?? !_DAccordionPosition.isLastOf(context);
    return _DAccordionItemScope<T>(
      value: widget.value,
      disabled: disabled,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: scope.outlined ? 16 : 0),
        decoration: showBorder
            ? BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: DTokens.of(context).border),
                ),
              )
            : null,
        child: DCollapsible(
          open: open,
          disabled: disabled,
          onOpenChange: (next) {
            scope.owner._change(widget.value, next);
            widget.onOpenChange?.call(next);
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class _DAccordionItemScope<T> extends InheritedWidget {
  const _DAccordionItemScope({
    required this.value,
    required this.disabled,
    required super.child,
  });
  final T value;
  final bool disabled;
  @override
  bool updateShouldNotify(_DAccordionItemScope<T> oldWidget) =>
      value != oldWidget.value || disabled != oldWidget.disabled;
}

/// Native heading boundary. It deliberately does not merge the trigger or
/// panel descendants into one accessibility node.
class DAccordionHeader extends StatelessWidget {
  const DAccordionHeader({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    header: true,
    explicitChildNodes: true,
    child: child,
  );
}

/// Styled base-nova heading button with a bounded expanded-state semantic node.
class DAccordionTrigger extends StatelessWidget {
  const DAccordionTrigger({
    super.key,
    required this.child,
    this.focusNode,
    this.semanticLabel,
    this.showChevron = true,
  });

  final Widget child;
  final FocusNode? focusNode;
  final String? semanticLabel;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    return DCollapsibleTrigger(
      focusNode: focusNode,
      semanticLabel: semanticLabel,
      focusBorderRadius: BorderRadius.circular(tokens.radius),
      focusBorder: true,
      focusRingWidth: 3,
      focusRingOpacity: .5,
      builder: (context, state) => Opacity(
        opacity: state.disabled ? .5 : 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: touch ? 48 : 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: tokens.foreground,
                      fontSize: DiscourseTypography.sm,
                      height: 20 / 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                      decoration: state.hovered
                          ? TextDecoration.underline
                          : null,
                    ),
                    child: child,
                  ),
                ),
                if (showChevron) ...[
                  const SizedBox(width: 16),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _DAccordionChevron(open: state.open),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DAccordionChevron extends StatelessWidget {
  const _DAccordionChevron({required this.open});
  final bool open;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: const Size.square(16),
      painter: _ChevronPainter(
        open: open,
        color: DTokens.of(context).mutedForeground,
      ),
    ),
  );
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.open, required this.color});
  final bool open;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(3.5, open ? 10 : 6)
      ..lineTo(8, open ? 5.5 : 10.5)
      ..lineTo(12.5, open ? 10 : 6);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      open != oldDelegate.open || color != oldDelegate.color;
}

/// Animated panel. Closed content is lazy by default; [keepMounted] retains
/// state while excluding it from focus, semantics, hit testing and tickers.
class DAccordionContent extends StatelessWidget {
  const DAccordionContent({
    super.key,
    required this.child,
    this.keepMounted,
    this.duration = const Duration(milliseconds: 200),
    this.curve = Curves.easeInOut,
  });

  final Widget child;
  final bool? keepMounted;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final inheritedKeepMounted = context
        .dependOnInheritedWidgetOfExactType<_DAccordionVisualScope>()
        ?.keepMounted;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: DCollapsibleContent(
        keepMounted: keepMounted ?? inheritedKeepMounted ?? false,
        duration: duration,
        curve: curve,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: DTokens.of(context).foreground,
              fontSize: DiscourseTypography.sm,
              height: 20 / 14,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
