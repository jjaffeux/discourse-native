import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';

/// Presentation metadata independent of a chart's data model. Resolve colors
/// during build to support live site palettes and light/dark themes.
@immutable
class DChartConfigEntry {
  const DChartConfigEntry({required this.label, this.color, this.icon});

  final String label;
  final Color Function(BuildContext context)? color;
  final WidgetBuilder? icon;
}

/// A local chart configuration scope. Compose any drawing widget inside it;
/// it does not take ownership of data, controllers or application state.
class DChartContainer extends InheritedWidget {
  const DChartContainer({
    super.key,
    required this.config,
    required super.child,
  });

  final Map<String, DChartConfigEntry> config;

  static DChartContainer of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DChartContainer>();
    if (scope == null) {
      throw FlutterError('Chart content requires a DChartContainer ancestor.');
    }
    return scope;
  }

  DChartConfigEntry? entry(String key, Map<String, Object?> payload) =>
      config[payload[key] is String ? payload[key] : key] ?? config[key];

  Color color(BuildContext context, String key) =>
      config[key]?.color?.call(context) ?? DTokens.of(context).primary;

  @override
  bool updateShouldNotify(DChartContainer oldWidget) => true;
}

TextStyle _chartText(BuildContext context) =>
    (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontSize: DiscourseTypography.xs,
      height: 16 / 12,
      fontWeight: FontWeight.normal,
      letterSpacing: 0,
      color: DTokens.of(context).foreground,
    );

/// A tooltip/legend entry. [payload] supports reference nameKey/labelKey
/// indirection; application objects never need to use a prescribed data shape.
@immutable
class DChartItem {
  const DChartItem({
    required this.key,
    this.value,
    this.color,
    this.payload = const {},
    this.hidden = false,
  });

  final String key;
  final num? value;
  final Color? color;
  final Map<String, Object?> payload;
  final bool hidden;
}

enum DChartIndicator { dot, line, dashed }

/// The reference tooltip content, also usable with another plotting owner.
/// Formatters replace a whole label or row. Icons take precedence over marks.
class DChartTooltipContent extends StatelessWidget {
  const DChartTooltipContent({
    super.key,
    required this.items,
    this.label,
    this.indicator = DChartIndicator.dot,
    this.hideLabel = false,
    this.hideIndicator = false,
    this.nameKey,
    this.labelKey,
    this.color,
    this.labelBuilder,
    this.itemBuilder,
    this.valueFormatter,
  });

  final List<DChartItem> items;
  final String? label;
  final DChartIndicator indicator;
  final bool hideLabel;
  final bool hideIndicator;
  final String? nameKey;
  final String? labelKey;
  final Color? color;
  final Widget Function(BuildContext, String?, List<DChartItem>)? labelBuilder;
  final Widget Function(BuildContext, DChartItem, int)? itemBuilder;
  final String Function(num)? valueFormatter;

  @override
  Widget build(BuildContext context) {
    final visible = items.where((item) => !item.hidden).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final scope = DChartContainer.of(context);
    final tokens = DTokens.of(context);
    final labelText = labelKey == null
        ? (scope.config[label]?.label ?? label)
        : scope.entry(labelKey!, visible.first.payload)?.label;
    final heading = hideLabel
        ? null
        : labelBuilder?.call(context, labelText, visible) ??
              (labelText == null
                  ? null
                  : Text(
                      labelText,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ));
    final nested = visible.length == 1 && indicator != DChartIndicator.dot;
    double measure(String value, {bool mono = false}) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: _chartText(
            context,
          ).copyWith(fontFamily: mono ? 'monospace' : null),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      return painter.width;
    }

    final preferredWidth = itemBuilder != null
        ? 220.0
        : math.max(
            128.0,
            math.max(
              hideLabel ? 0 : measure(labelText ?? '') + 22,
              visible.fold<double>(
                0,
                (width, item) => math.max(
                  width,
                  measure(
                        scope.entry(nameKey ?? item.key, item.payload)?.label ??
                            item.key,
                      ) +
                      (item.value == null
                          ? 0
                          : measure(
                              valueFormatter?.call(item.value!) ??
                                  _formatValue(context, item.value!),
                              mono: true,
                            )) +
                      (hideIndicator ? 0 : 18) +
                      22,
                ),
              ),
            ),
          );
    return DefaultTextStyle(
      style: _chartText(context),
      child: SizedBox(
        width: preferredWidth.toDouble(),
        child: Container(
          constraints: const BoxConstraints(minWidth: 128),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: tokens.background,
            borderRadius: BorderRadius.circular(tokens.radius),
            border: Border.all(
              color: tokens.border.withValues(alpha: tokens.border.a * .5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .1),
                offset: const Offset(0, 20),
                blurRadius: 25,
                spreadRadius: -5,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: .1),
                offset: const Offset(0, 8),
                blurRadius: 10,
                spreadRadius: -6,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [
              if (!nested && heading != null) heading,
              for (var index = 0; index < visible.length; index++)
                if (itemBuilder != null)
                  itemBuilder!(context, visible[index], index)
                else
                  _row(context, scope, visible[index], nested ? heading : null),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    DChartContainer scope,
    DChartItem item,
    Widget? heading,
  ) {
    final config = scope.entry(nameKey ?? item.key, item.payload);
    final markColor =
        color ??
        item.color ??
        config?.color?.call(context) ??
        scope.color(context, item.key);
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (config?.icon != null)
            IconTheme(
              data: IconThemeData(
                size: 10,
                color: DTokens.of(context).mutedForeground,
              ),
              child: config!.icon!(context),
            )
          else if (!hideIndicator)
            _ChartIndicator(
              color: markColor,
              indicator: indicator,
              height: heading == null
                  ? MediaQuery.textScalerOf(context).scale(12)
                  : MediaQuery.textScalerOf(context).scale(28) + 6,
            ),
          if (config?.icon != null || !hideIndicator) const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                ?heading,
                Text(
                  config?.label ?? item.key,
                  style: TextStyle(
                    color: DTokens.of(context).mutedForeground,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          if (item.value != null)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.max(
                  0,
                  (constraints.maxWidth - (hideIndicator ? 0 : 18)) / 2,
                ),
              ),
              child: Text(
                valueFormatter?.call(item.value!) ??
                    _formatValue(context, item.value!),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  height: 1,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _formatValue(BuildContext context, num value) =>
    value == value.roundToDouble()
    ? MaterialLocalizations.of(context).formatDecimal(value.toInt())
    : value.toString();

class _ChartIndicator extends StatelessWidget {
  const _ChartIndicator({
    required this.color,
    required this.indicator,
    required this.height,
  });
  final Color color;
  final DChartIndicator indicator;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: switch (indicator) {
      DChartIndicator.dot => 10,
      DChartIndicator.line => 4,
      DChartIndicator.dashed => 3,
    },
    height: indicator == DChartIndicator.dot ? 10 : height,
    child: indicator == DChartIndicator.dashed
        ? CustomPaint(painter: _DashPainter(color))
        : DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
  );
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3;
    for (var y = 0.0; y < size.height; y += 6) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, math.min(y + 3, size.height)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => color != oldDelegate.color;
}

/// Wrapping legend with reference 8px marks, 6px label gaps and 16px item gaps.
/// [hideIcon] substitutes color marks for configured icons, as in base-nova.
class DChartLegendContent extends StatelessWidget {
  const DChartLegendContent({
    super.key,
    required this.items,
    this.nameKey,
    this.hideIcon = false,
    this.atTop = false,
    this.itemBuilder,
  });
  final List<DChartItem> items;
  final String? nameKey;
  final bool hideIcon;
  final bool atTop;
  final Widget Function(BuildContext, DChartItem)? itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (!items.any((item) => !item.hidden)) return const SizedBox.shrink();
    final scope = DChartContainer.of(context);
    return DefaultTextStyle(
      style: _chartText(context),
      child: Padding(
        padding: EdgeInsets.only(top: atTop ? 0 : 12, bottom: atTop ? 12 : 0),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 6,
          children: [
            for (final item in items.where((item) => !item.hidden))
              itemBuilder?.call(context, item) ?? _item(context, scope, item),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, DChartContainer scope, DChartItem item) {
    final config = scope.entry(nameKey ?? item.key, item.payload);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        if (config?.icon != null && !hideIcon)
          IconTheme(
            data: IconThemeData(
              size: 12,
              color: DTokens.of(context).mutedForeground,
            ),
            child: config!.icon!(context),
          )
        else
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color:
                  item.color ??
                  config?.color?.call(context) ??
                  scope.color(context, item.key),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        Flexible(child: Text(config?.label ?? item.key)),
      ],
    );
  }
}

/// A quantitative bar mark, usable in inline result rows or other chart layouts.
/// [fraction] is clamped to 0–1. The containing row owns semantic description.
/// It is not a task-progress or editable Form control.
class DChartBar extends StatelessWidget {
  const DChartBar({
    super.key,
    required this.fraction,
    this.color,
    this.backgroundColor,
    this.height = 7,
    this.radius = 4,
  }) : assert(fraction > -double.infinity && fraction < double.infinity),
       assert(height > 0 && height < double.infinity),
       assert(radius >= 0 && radius < double.infinity);
  final double fraction;
  final Color? color;
  final Color? backgroundColor;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(radius),
    ),
    clipBehavior: Clip.antiAlias,
    alignment: AlignmentDirectional.centerStart,
    child: FractionallySizedBox(
      widthFactor: fraction.clamp(0.0, 1.0),
      heightFactor: 1,
      child: ColoredBox(color: color ?? DTokens.of(context).primary),
    ),
  );
}

/// Typed value accessors keep arbitrary domain data outside rendering primitives.
@immutable
class DChartSeries<T> {
  const DChartSeries({required this.key, required this.value, this.color});
  final String key;

  /// Null means missing, not zero. Non-finite values are rejected.
  final num? Function(T datum) value;
  final Color? Function(BuildContext context, T datum)? color;
}

/// A borrowed selection controller is never disposed by [DBarChart]. Null hides
/// the cursor/tooltip. Selection indexes refer to the current input list.
class DChartController extends ValueNotifier<int?> {
  DChartController([super.value]);
}

typedef DChartTooltipBuilder =
    Widget Function(BuildContext context, String label, List<DChartItem> items);

/// Native plotting owner for the frozen grouped-bar compositions. Adds no
/// dependency or abstraction over an external plotting engine. Other plotting
/// widgets can reuse [DChartContainer] and its tooltip/legend content directly.
///
/// Tab enters once; arrows inspect categories (physical directions in RTL),
/// Home/End select endpoints, Escape dismisses. Mouse hover and touch inspect
/// the same data. An optional controller supplies persistent controlled state;
/// [initialIndex] is consumed only when creating an owned controller.
class DBarChart<T> extends StatefulWidget {
  const DBarChart({
    super.key,
    required this.data,
    required this.series,
    required this.label,
    required this.semanticLabel,
    this.payload,
    this.controller,
    this.initialIndex,
    this.onSelectionChanged,
    this.focusNode,
    this.grid = false,
    this.axis = false,
    this.valueAxis = false,
    this.tooltip = true,
    this.tooltipBuilder,
    this.tickFormatter,
    this.valueFormatter,
    this.height = 200,
    this.barRadius = 4,
    this.margin = const EdgeInsets.all(5),
    this.tickMargin = 10,
    this.minTickGap = 5,
    this.minValue,
    this.maxValue,
  }) : assert(height > 0 && height < double.infinity),
       assert(barRadius >= 0 && barRadius < double.infinity),
       assert(tickMargin >= 0 && tickMargin < double.infinity),
       assert(minTickGap >= 0 && minTickGap < double.infinity),
       assert(
         minValue == null ||
             (minValue > -double.infinity && minValue < double.infinity),
       ),
       assert(
         maxValue == null ||
             (maxValue > -double.infinity && maxValue < double.infinity),
       ),
       assert(minValue == null || maxValue == null || minValue < maxValue);

  final List<T> data;
  final List<DChartSeries<T>> series;
  final String Function(T datum) label;
  final String semanticLabel;
  final Map<String, Object?> Function(T datum)? payload;
  final DChartController? controller;
  final int? initialIndex;
  final ValueChanged<int?>? onSelectionChanged;
  final FocusNode? focusNode;
  final bool grid;
  final bool axis;
  final bool valueAxis;
  final bool tooltip;

  /// Display-only content. Interactive controls belong outside the plot.
  final DChartTooltipBuilder? tooltipBuilder;
  final String Function(String label)? tickFormatter;
  final String Function(num value)? valueFormatter;

  /// Minimum total height; grows to retain a 120px plot with scaled axis text.
  final double height;
  final double barRadius;
  final EdgeInsetsGeometry margin;
  final double tickMargin;
  final double minTickGap;

  /// Optional explicit domain. Values outside it are clipped to the plot.
  final double? minValue;
  final double? maxValue;

  @override
  State<DBarChart<T>> createState() => _DBarChartState<T>();
}

class _DBarChartState<T> extends State<DBarChart<T>> {
  late DChartController _controller;
  late FocusNode _focus;
  bool _focusHighlight = false;
  double? _pointerY;
  void _inspect(Offset point, int? index) {
    setState(() => _pointerY = point.dy);
    _select(index);
  }

  int? get _selected {
    final index = _controller.value;
    return index != null && index >= 0 && index < widget.data.length
        ? index
        : null;
  }

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? DChartController(widget.initialIndex);
    _controller.addListener(_changed);
    _focus = widget.focusNode ?? FocusNode();
  }

  @override
  void didUpdateWidget(covariant DBarChart<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      final previous = _selected;
      _controller.removeListener(_changed);
      if (oldWidget.controller == null) _controller.dispose();
      _controller = widget.controller ?? DChartController(previous);
      _controller.addListener(_changed);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (oldWidget.focusNode == null) _focus.dispose();
      _focus = widget.focusNode ?? FocusNode();
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _select(int? index) {
    if (_controller.value == index) return;
    _controller.value = index;
    widget.onSelectionChanged?.call(index);
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    if (widget.controller == null) _controller.dispose();
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_selected == null) return KeyEventResult.ignored;
      _select(null);
      return KeyEventResult.handled;
    }
    if (widget.data.isEmpty) return KeyEventResult.ignored;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _pointerY = null;
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowRight => rtl ? -1 : 1,
      LogicalKeyboardKey.arrowLeft => rtl ? 1 : -1,
      _ => 0,
    };
    if (delta != 0) {
      _select(
        _selected == null
            ? (delta > 0 ? 0 : widget.data.length - 1)
            : (_selected! + delta).clamp(0, widget.data.length - 1),
      );
    } else if (event.logicalKey == LogicalKeyboardKey.home) {
      _select(0);
    } else if (event.logicalKey == LogicalKeyboardKey.end) {
      _select(widget.data.length - 1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final scope = DChartContainer.of(context);
    final tokens = DTokens.of(context);
    final rows = [
      for (final datum in widget.data)
        [
          for (final series in widget.series)
            DChartItem(
              key: series.key,
              value: series.value(datum),
              color:
                  series.color?.call(context, datum) ??
                  scope.color(context, series.key),
              payload: widget.payload?.call(datum) ?? const {},
            ),
        ],
    ];
    for (final row in rows) {
      for (final item in row) {
        if (item.value != null && !item.value!.isFinite) {
          throw ArgumentError.value(
            item.value,
            'series value',
            'Must be finite or null',
          );
        }
      }
    }
    final values = rows.expand((row) => row).map((item) => item.value).nonNulls;
    var low =
        widget.minValue ??
        values.fold<double>(0, (a, b) => math.min(a, b.toDouble()));
    var high =
        widget.maxValue ??
        values.fold<double>(0, (a, b) => math.max(a, b.toDouble()));
    if (high <= low) {
      if (widget.maxValue != null) {
        low = high - 1;
      } else {
        high = low + 1;
      }
    }
    // Five-tick source formatting: 305 → 80-step/320, 454 → 150-step/600.
    if (widget.minValue == null && widget.maxValue == null) {
      final normalization = math.max(low.abs(), high.abs());
      final rough =
          (high / normalization - low / normalization) * (normalization / 4);
      if (rough.isFinite && rough > 0) {
        final digits = (math.log(rough) / math.ln10).floor() + 1;
        final unit = math.pow(10, digits).toDouble();
        final scale = digits == 1 ? .1 : .05;
        if (unit.isFinite && unit > 0) {
          var step = (rough / unit / scale).ceil() * scale * unit;
          while ((-low / step).ceil() + (high / step).ceil() > 4) {
            step += scale * unit;
          }
          final nextLow = -(-low / step).ceil() * step;
          final nextHigh = nextLow + step * 4;
          if (nextLow.isFinite && nextHigh.isFinite) {
            low = nextLow;
            high = nextHigh;
          }
        }
      }
    }
    final labels = widget.data.map(widget.label).toList();
    final scale = MediaQuery.textScalerOf(context);
    final axisHeight = widget.axis ? scale.scale(16) + 14 : 0.0;
    final chartHeight = math.max(widget.height, 120 + axisHeight);
    final selected = _selected;
    String summary(int index) =>
        '${labels[index]}: ${rows[index].map((item) => '${scope.config[item.key]?.label ?? item.key} ${item.value == null ? 'No data' : widget.valueFormatter?.call(item.value!) ?? _formatValue(context, item.value!)}').join(', ')}';
    final next = rows.isEmpty
        ? null
        : ((_selected ?? -1) + 1).clamp(0, rows.length - 1);
    final previous = rows.isEmpty
        ? null
        : ((_selected ?? 1) - 1).clamp(0, rows.length - 1);
    return TapRegion(
      onTapOutside: (_) => _select(null),
      child: DefaultTextStyle(
        style: _chartText(context),
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: _key,
          child: FocusableActionDetector(
            focusNode: _focus,
            enabled: widget.data.isNotEmpty,
            onShowFocusHighlight: (value) =>
                setState(() => _focusHighlight = value),
            child: Semantics(
              label: widget.semanticLabel,
              value: selected == null
                  ? 'No category selected'
                  : summary(selected),
              increasedValue: next == null ? null : summary(next),
              decreasedValue: previous == null ? null : summary(previous),
              hint: 'Use left and right arrow keys to inspect values',
              onIncrease: widget.data.isEmpty
                  ? null
                  : () => _select(
                      ((_selected ?? -1) + 1).clamp(0, widget.data.length - 1),
                    ),
              onDecrease: widget.data.isEmpty
                  ? null
                  : () => _select(
                      ((_selected ?? 1) - 1).clamp(0, widget.data.length - 1),
                    ),
              child: Container(
                height: chartHeight,
                foregroundDecoration: BoxDecoration(
                  border: Border.all(
                    color: _focusHighlight
                        ? tokens.focusRing
                        : Colors.transparent,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (!constraints.hasBoundedWidth) {
                      throw FlutterError(
                        'DBarChart requires a bounded width. Use SizedBox or Expanded.',
                      );
                    }
                    final rtl = Directionality.of(context) == TextDirection.rtl;
                    final gutter = widget.valueAxis
                        ? math.min(
                            56 * scale.scale(12) / 12,
                            constraints.maxWidth / 3,
                          )
                        : 0.0;
                    final insets = widget.margin.resolve(
                      Directionality.of(context),
                    );
                    final plot = Rect.fromLTWH(
                      insets.left + (rtl ? 0 : gutter),
                      insets.top,
                      math.max(
                        0,
                        constraints.maxWidth - gutter - insets.horizontal,
                      ),
                      math.max(
                        0,
                        constraints.maxHeight - axisHeight - insets.vertical,
                      ),
                    );
                    int? hit(Offset position) {
                      if (!plot.contains(position) ||
                          labels.isEmpty ||
                          plot.width <= 0) {
                        return null;
                      }
                      final physical =
                          ((position.dx - plot.left) /
                                  plot.width *
                                  labels.length)
                              .floor()
                              .clamp(0, labels.length - 1);
                      return rtl ? labels.length - physical - 1 : physical;
                    }

                    return MouseRegion(
                      onHover: (event) => _inspect(
                        event.localPosition,
                        hit(event.localPosition),
                      ),
                      onExit: (_) {
                        if (!_focus.hasFocus) _select(null);
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        excludeFromSemantics: true,
                        onTapDown: (event) {
                          _focus.requestFocus();
                          _inspect(
                            event.localPosition,
                            hit(event.localPosition),
                          );
                        },
                        onHorizontalDragUpdate: (event) => _inspect(
                          event.localPosition,
                          hit(event.localPosition),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _BarPainter(
                                  rows: rows,
                                  labels: labels,
                                  plot: plot,
                                  low: low,
                                  high: high,
                                  grid: widget.grid,
                                  axis: widget.axis,
                                  valueAxis: widget.valueAxis,
                                  selected: selected,
                                  rtl: rtl,
                                  radius: widget.barRadius,
                                  textStyle: _chartText(
                                    context,
                                  ).copyWith(color: tokens.mutedForeground),
                                  textScaler: scale,
                                  direction: Directionality.of(context),
                                  gridColor: tokens.border.withValues(
                                    alpha: tokens.border.a * .5,
                                  ),
                                  cursorColor: tokens.muted,
                                  tickFormatter: widget.tickFormatter,
                                  tickMargin: widget.tickMargin,
                                  minTickGap: widget.minTickGap,
                                  valueFormatter:
                                      widget.valueFormatter ??
                                      (value) => _formatValue(context, value),
                                ),
                              ),
                            ),
                            if (rows.isEmpty || widget.series.isEmpty)
                              const Center(child: Text('No data')),
                            if (selected != null &&
                                widget.tooltip &&
                                plot.width > 0)
                              Positioned.fill(
                                child: CustomSingleChildLayout(
                                  delegate: _ChartTooltipLayout(
                                    anchor: Offset(
                                      plot.left +
                                          ((rtl
                                                      ? labels.length -
                                                            selected -
                                                            1
                                                      : selected) +
                                                  .5) /
                                              labels.length *
                                              plot.width,
                                      _pointerY ?? plot.center.dy,
                                    ),
                                    rtl: rtl,
                                  ),
                                  child: IntrinsicWidth(
                                    child: ExcludeSemantics(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxHeight: constraints.maxHeight,
                                          maxWidth: math.min(
                                            220,
                                            constraints.maxWidth,
                                          ),
                                        ),
                                        child: SingleChildScrollView(
                                          child:
                                              widget.tooltipBuilder?.call(
                                                context,
                                                labels[selected],
                                                rows[selected],
                                              ) ??
                                              DChartTooltipContent(
                                                label: labels[selected],
                                                items: rows[selected],
                                                valueFormatter:
                                                    widget.valueFormatter,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.rows,
    required this.labels,
    required this.plot,
    required this.low,
    required this.high,
    required this.grid,
    required this.axis,
    required this.valueAxis,
    required this.selected,
    required this.rtl,
    required this.radius,
    required this.textStyle,
    required this.textScaler,
    required this.direction,
    required this.gridColor,
    required this.cursorColor,
    required this.tickFormatter,
    required this.valueFormatter,
    required this.tickMargin,
    required this.minTickGap,
  });
  final List<List<DChartItem>> rows;
  final List<String> labels;
  final Rect plot;
  final double low, high, radius;
  final double tickMargin, minTickGap;
  final bool grid, axis, valueAxis, rtl;
  final int? selected;
  final TextStyle textStyle;
  final TextScaler textScaler;
  final TextDirection direction;
  final Color gridColor, cursorColor;
  final String Function(String)? tickFormatter;
  final String Function(num) valueFormatter;

  double y(num value) {
    final normalization = math.max(low.abs(), high.abs());
    final fraction =
        (value / normalization - low / normalization) /
        (high / normalization - low / normalization);
    return plot.bottom - fraction.clamp(0.0, 1.0) * plot.height;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (plot.isEmpty) return;
    final paint = Paint();
    if (grid || valueAxis) {
      for (var tick = 0; tick <= 4; tick++) {
        final value = low + (high - low) * tick / 4;
        final top = y(value);
        if (grid) {
          canvas.drawLine(
            Offset(plot.left, top),
            Offset(plot.right, top),
            paint
              ..color = gridColor
              ..strokeWidth = 1,
          );
        }
        if (valueAxis) {
          _text(
            canvas,
            valueFormatter(value),
            Rect.fromLTWH(
              rtl ? plot.right + 4 : 0,
              top - textScaler.scale(8),
              math.max(0, size.width - plot.width - 14),
              textScaler.scale(16),
            ),
            align: rtl ? TextAlign.left : TextAlign.right,
          );
        }
      }
    }
    if (rows.isEmpty) return;
    final slot = plot.width / rows.length;
    for (var index = 0; index < rows.length; index++) {
      final x = plot.left + (rtl ? rows.length - index - 1 : index) * slot;
      if (selected == index) {
        canvas.drawRect(
          Rect.fromLTWH(x, plot.top, slot, plot.height),
          paint..color = cursorColor,
        );
      }
      final row = rows[index];
      if (row.isNotEmpty) {
        final gap = math.min(4.0, slot * .8 / math.max(1, row.length * 2 - 1));
        final rawWidth = math.max(
          0.0,
          (slot * .8 - gap * (row.length - 1)) / row.length,
        );
        final width = rawWidth >= 1 ? rawWidth.floorToDouble() : rawWidth;
        for (var series = 0; series < row.length; series++) {
          final item = row[series];
          if (item.value == null || item.hidden) continue;
          final zero = y(0);
          final valueY = y(item.value!);
          final bar = Rect.fromLTWH(
            x + slot * .1 + series * (width + gap),
            math.min(zero, valueY),
            width,
            (zero - valueY).abs(),
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(bar, Radius.circular(radius)),
            paint..color = item.color!,
          );
        }
      }
    }
    if (axis) {
      var boundary = rtl ? 0.0 : size.width;
      for (var index = rows.length - 1; index >= 0; index--) {
        final label = tickFormatter?.call(labels[index]) ?? labels[index];
        final text = TextPainter(
          text: TextSpan(text: label, style: textStyle),
          textDirection: direction,
          textScaler: textScaler,
        )..layout(maxWidth: plot.width);
        final center =
            plot.left + ((rtl ? rows.length - index - 1 : index) + .5) * slot;
        final left = (center - text.width / 2).clamp(
          0.0,
          size.width - text.width,
        );
        final right = left + text.width;
        if (rtl ? left >= boundary : right <= boundary) {
          _text(
            canvas,
            label,
            Rect.fromLTWH(
              left,
              plot.bottom + tickMargin,
              text.width,
              textScaler.scale(16),
            ),
          );
          boundary = rtl ? right + minTickGap : left - minTickGap;
        }
      }
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Rect bounds, {
    TextAlign align = TextAlign.center,
  }) {
    if (bounds.width <= 0) return;
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: direction,
      textScaler: textScaler,
      maxLines: 1,
      ellipsis: '…',
      textAlign: align,
    )..layout(maxWidth: bounds.width);
    painter.paint(
      canvas,
      Offset(
        bounds.left +
            switch (align) {
              TextAlign.right => bounds.width - painter.width,
              TextAlign.center => (bounds.width - painter.width) / 2,
              _ => 0,
            },
        bounds.top,
      ),
    );
  }

  @override
  bool shouldRepaint(_BarPainter oldDelegate) => true;
}

class _ChartTooltipLayout extends SingleChildLayoutDelegate {
  const _ChartTooltipLayout({required this.anchor, required this.rtl});
  final Offset anchor;
  final bool rtl;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);
  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = rtl ? anchor.dx - childSize.width - 10 : anchor.dx + 10;
    if (x < 0 || x + childSize.width > size.width) {
      x = rtl ? anchor.dx + 10 : anchor.dx - childSize.width - 10;
    }
    var y = anchor.dy + 10;
    if (y + childSize.height > size.height) {
      y = anchor.dy - childSize.height - 10;
    }
    return Offset(
      x.clamp(0, math.max(0, size.width - childSize.width)),
      y.clamp(0, math.max(0, size.height - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(_ChartTooltipLayout oldDelegate) =>
      anchor != oldDelegate.anchor || rtl != oldDelegate.rtl;
}
