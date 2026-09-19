import 'package:flutter/material.dart';

import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_popover.dart';
import 'd_slider.dart';

/// Opaque RGB color selection with a swatch trigger and a live HSV popover.
/// The caller owns [value]. Null [onChanged] disables the trigger.
/// Sliders provide keyboard and screen-reader access to every plane axis.
class DColorPicker extends StatefulWidget {
  const DColorPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });
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
  Widget build(BuildContext context) => DPopover(
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
                    .withSaturation((position.dx / bounds.maxWidth).clamp(0, 1))
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
