import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../foundation/focus_highlight.dart';

import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_popover.dart';
import 'd_slider.dart';

enum DColorPresetAppearance { text, background }

/// A named opaque swatch. Appearance also distinguishes a text color from a
/// background color when both appear in a recently-used group.
@immutable
class DColorPreset {
  const DColorPreset({
    required this.color,
    required this.label,
    this.appearance = DColorPresetAppearance.text,
  });

  final Color color;
  final String label;
  final DColorPresetAppearance appearance;

  @override
  bool operator ==(Object other) =>
      other is DColorPreset &&
      color == other.color &&
      appearance == other.appearance;

  @override
  int get hashCode => Object.hash(color, appearance);
}

/// A controlled preset palette for the Native color-picker family.
///
/// The caller owns recent choices and the selected value. A null [selected]
/// represents the default color; [onReset] adds an explicit default swatch.
/// Button owns keyboard activation, tooltips, focus and accessible targets.
class DColorPickerPresets extends StatelessWidget {
  const DColorPickerPresets({
    super.key,
    required this.semanticLabel,
    required this.presets,
    required this.onChanged,
    this.selected,
    this.recentColors = const [],
    this.recentLabel = 'Recently used',
    this.onReset,
    this.resetLabel = 'Default',
    this.appearance = DColorPresetAppearance.text,
  });

  final String semanticLabel;
  final List<DColorPreset> presets;
  final ValueChanged<DColorPreset>? onChanged;
  final DColorPreset? selected;
  final List<DColorPreset> recentColors;
  final String recentLabel;
  final VoidCallback? onReset;
  final String resetLabel;
  final DColorPresetAppearance appearance;

  Widget _swatch(BuildContext context, DColorPreset? preset) {
    final tokens = DTokens.of(context);
    final chosen = selected == preset;
    final fill =
        (preset?.appearance ?? appearance) == DColorPresetAppearance.background;
    final color = preset?.color ?? tokens.foreground;
    final label = preset?.label ?? '$semanticLabel: $resetLabel';
    return Semantics(
      selected: chosen,
      child: DButton.iconOnly(
        tooltip: label,
        semanticLabel: label,
        variant: DButtonVariant.outline,
        backgroundColor: fill && preset != null ? color : null,
        foregroundColor: fill && preset != null
            ? (color.computeLuminance() > .45 ? Colors.black : Colors.white)
            : color,
        borderColor: chosen ? tokens.foreground : color.withValues(alpha: .4),
        icon: fill
            ? (chosen ? const Icon(Icons.check) : const SizedBox.shrink())
            : Builder(
                builder: (context) => Text(
                  'A',
                  style: TextStyle(
                    fontSize: IconTheme.of(context).size,
                    fontWeight: FontWeight.w700,
                    decoration: chosen ? TextDecoration.underline : null,
                  ),
                ),
              ),
        onPressed: onChanged == null
            ? null
            : preset == null
            ? onReset
            : () => onChanged!(preset),
      ),
    );
  }

  Widget _group(
    BuildContext context,
    String label,
    List<DColorPreset> choices, {
    bool reset = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: TextStyle(
          color: DTokens.of(context).mutedForeground,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: DSpacing.sm),
      Wrap(
        spacing: DSpacing.controlGap,
        runSpacing: DSpacing.controlGap,
        children: [
          if (reset) _swatch(context, null),
          for (final preset in choices) _swatch(context, preset),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (recentColors.isNotEmpty) ...[
        _group(context, recentLabel, recentColors),
        const SizedBox(height: DSpacing.lg),
      ],
      _group(context, semanticLabel, presets, reset: onReset != null),
    ],
  );
}

/// Opaque RGB color selection with a swatch/popover or an inline palette.
/// The caller owns [value]. Null [onChanged] disables the trigger.
/// Popover sliders provide keyboard and screen-reader access to every HSV axis.
class DColorPicker extends StatefulWidget {
  const DColorPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  }) : _inline = false;

  /// A persistent dotted hue/lightness palette. Arrow keys change hue and
  /// lightness; screen readers expose hue adjustment and lightness actions.
  const DColorPicker.inline({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  }) : _inline = true;

  final bool _inline;
  final Color value;
  final ValueChanged<Color>? onChanged;
  final String semanticLabel;

  @override
  State<DColorPicker> createState() => _DColorPickerState();
}

class _DColorPickerState extends State<DColorPicker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.value).withAlpha(1);
  bool _open = false;

  @override
  void didUpdateWidget(DColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _hsv.toColor().toARGB32() != widget.value.toARGB32()) {
      _hsv = HSVColor.fromColor(widget.value).withAlpha(1);
    }
    if (widget.onChanged == null) _open = false;
  }

  void _change(HSVColor value) {
    if (widget.onChanged == null) return;
    setState(() => _hsv = value);
    widget.onChanged!(value.toColor());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _hsv.toColor().toARGB32() != widget.value.toARGB32()) {
        setState(() => _hsv = HSVColor.fromColor(widget.value).withAlpha(1));
      }
    });
  }

  Widget _slider(
    String label,
    double value,
    double max,
    ValueChanged<double> change,
  ) => Row(
    children: [
      SizedBox(width: 82, child: Text(label)),
      Expanded(
        child: DSlider(
          value: value,
          max: max,
          semanticLabel: '${widget.semanticLabel} $label',
          onChanged: widget.onChanged == null ? null : change,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (widget._inline) {
      return _InlineColorPalette(
        value: widget.value,
        onChanged: widget.onChanged,
        label: widget.semanticLabel,
      );
    }
    return DPopover(
      open: _open,
      onOpenChange: (open, _) =>
          setState(() => _open = open && widget.onChanged != null),
      content: DPopoverContent(
        semanticLabel: widget.semanticLabel,
        align: DPopoverAlign.start,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.semanticLabel,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: DSpacing.md),
            LayoutBuilder(
              builder: (context, bounds) {
                void pick(Offset position) => _change(
                  _hsv
                      .withSaturation(
                        (position.dx / bounds.maxWidth).clamp(0, 1),
                      )
                      .withValue((1 - position.dy / 150).clamp(0, 1)),
                );
                return ExcludeSemantics(
                  child: GestureDetector(
                    key: const ValueKey('color-picker-plane'),
                    behavior: HitTestBehavior.opaque,
                    onPanDown: (event) => pick(event.localPosition),
                    onPanUpdate: (event) => pick(event.localPosition),
                    child: SizedBox(
                      height: 150,
                      child: CustomPaint(painter: _ColorPlane(_hsv)),
                    ),
                  ),
                );
              },
            ),
            _slider(
              'Hue',
              _hsv.hue,
              360,
              (value) => _change(_hsv.withHue(value)),
            ),
            _slider(
              'Saturation',
              _hsv.saturation * 100,
              100,
              (value) => _change(_hsv.withSaturation(value / 100)),
            ),
            _slider(
              'Brightness',
              _hsv.value * 100,
              100,
              (value) => _change(_hsv.withValue(value / 100)),
            ),
          ],
        ),
      ),
      child: DPopoverTrigger(
        builder: (context, state) => DButton.iconOnly(
          focusNode: state.focusNode,
          tooltip: widget.semanticLabel,
          hasPopup: true,
          expanded: state.open,
          semanticLabel: widget.semanticLabel,
          variant: DButtonVariant.transparentBackground,
          size: DButtonSize.small,
          onPressed: widget.onChanged == null ? null : state.toggle,
          icon: SizedBox.square(
            dimension: 16,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.value,
                border: Border.all(color: DTokens.of(context).border),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorPlane extends CustomPainter {
  const _ColorPlane(this.hsv);
  final HSVColor hsv;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    final center = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawCircle(
      center,
      6,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      center,
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ColorPlane oldDelegate) => oldDelegate.hsv != hsv;
}

class _InlineColorPalette extends StatefulWidget {
  const _InlineColorPalette({
    required this.value,
    required this.onChanged,
    required this.label,
  });
  final Color value;
  final ValueChanged<Color>? onChanged;
  final String label;

  @override
  State<_InlineColorPalette> createState() => _InlineColorPaletteState();
}

class _InlineColorPaletteState extends State<_InlineColorPalette> {
  final _focus = FocusNode();
  bool _focused = false;
  HSLColor get _color => HSLColor.fromColor(widget.value);
  bool get _enabled => widget.onChanged != null;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _change(double hue, double lightness) {
    if (!_enabled) return;
    widget.onChanged!(_proposedColor(hue, lightness));
  }

  Color _proposedColor(double hue, double lightness) => _color
      .withHue(hue.clamp(0, 359.9))
      .withSaturation(math.max(.55, _color.saturation))
      .withLightness(lightness.clamp(.02, .98))
      .toColor();

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    String hex(Color color) =>
        '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    return Semantics(
      label: widget.label,
      value: hex(widget.value),
      increasedValue: _enabled
          ? hex(_proposedColor(_color.hue + 3, _color.lightness))
          : null,
      decreasedValue: _enabled
          ? hex(_proposedColor(_color.hue - 3, _color.lightness))
          : null,
      slider: true,
      hint: 'Left and right change hue. Up and down change lightness.',
      enabled: _enabled,
      focusable: _enabled,
      focused: _focused,
      onIncrease: _enabled
          ? () => _change(_color.hue + 3, _color.lightness)
          : null,
      onDecrease: _enabled
          ? () => _change(_color.hue - 3, _color.lightness)
          : null,
      customSemanticsActions: _enabled
          ? {
              const CustomSemanticsAction(label: 'Lighter'): () =>
                  _change(_color.hue, _color.lightness + .02),
              const CustomSemanticsAction(label: 'Darker'): () =>
                  _change(_color.hue, _color.lightness - .02),
            }
          : null,
      child: Focus(
        focusNode: _focus,
        canRequestFocus: _enabled,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (_, event) {
          if (!_enabled || event is KeyUpEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft) {
            _change(_color.hue - 3, _color.lightness);
          } else if (key == LogicalKeyboardKey.arrowRight) {
            _change(_color.hue + 3, _color.lightness);
          } else if (key == LogicalKeyboardKey.arrowUp) {
            _change(_color.hue, _color.lightness + .02);
          } else if (key == LogicalKeyboardKey.arrowDown) {
            _change(_color.hue, _color.lightness - .02);
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: MouseRegion(
          cursor: _enabled
              ? SystemMouseCursors.precise
              : SystemMouseCursors.basic,
          child: LayoutBuilder(
            builder: (context, bounds) {
              final width = bounds.hasBoundedWidth ? bounds.maxWidth : 320.0;
              void pick(Offset position) {
                _focus.requestFocus();
                _change(
                  (position.dx - 12) / math.max(1, width - 24) * 359.9,
                  1 - (position.dy - 12) / 112,
                );
              }

              return GestureDetector(
                key: const ValueKey('color-picker-inline-plane'),
                behavior: HitTestBehavior.opaque,
                onPanDown: _enabled
                    ? (event) => pick(event.localPosition)
                    : null,
                onPanUpdate: _enabled
                    ? (event) => pick(event.localPosition)
                    : null,
                child: SizedBox(
                  width: width,
                  height: 136,
                  child: CustomPaint(
                    painter: _DottedColorPlane(
                      color: _color,
                      tokens: tokens,
                      focused: _focused && DFocusHighlight.visibleOf(context),
                      enabled: _enabled,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DottedColorPlane extends CustomPainter {
  const _DottedColorPlane({
    required this.color,
    required this.tokens,
    required this.focused,
    required this.enabled,
  });
  final HSLColor color;
  final DTokens tokens;
  final bool focused, enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(
      rect.deflate(1),
      const Radius.circular(18),
    );
    canvas.drawRRect(
      shape,
      Paint()..color = tokens.muted.withValues(alpha: .35),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..color = focused ? tokens.focusRing : tokens.border
        ..style = PaintingStyle.stroke,
    );
    canvas.save();
    canvas.clipRRect(shape);
    final width = math.max(1.0, size.width - 24);
    final height = size.height - 24;
    final selected = Offset(
      12 + color.hue / 359.9 * width,
      12 + (1 - color.lightness) * height,
    );
    final glow = Rect.fromCircle(center: selected, radius: 46);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.toColor().withValues(alpha: enabled ? .3 : .1),
            color.toColor().withValues(alpha: 0),
          ],
        ).createShader(glow),
    );
    for (var x = 12.0; x <= size.width - 12; x += 12) {
      for (var y = 12.0; y <= size.height - 12; y += 12) {
        final point = Offset(x, y);
        final distance = (point - selected).distance;
        final highlight = (1 - distance / 42).clamp(0.0, 1.0);
        final dot = Color.lerp(
          tokens.mutedForeground,
          color.toColor(),
          highlight,
        )!;
        canvas.drawCircle(
          point,
          2.1 + highlight * .6,
          Paint()
            ..color = dot.withValues(
              alpha: enabled ? .25 + highlight * .7 : .15,
            ),
        );
      }
    }
    canvas.drawCircle(
      selected,
      5,
      Paint()
        ..color = tokens.foreground.withValues(alpha: enabled ? .9 : .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DottedColorPlane oldDelegate) =>
      color != oldDelegate.color ||
      tokens != oldDelegate.tokens ||
      focused != oldDelegate.focused ||
      enabled != oldDelegate.enabled;
}
