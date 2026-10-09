import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/tokens.dart';

/// A redaction whose hidden text, media and links cannot be selected or focused.
/// Only plain text is measured while closed; rich content is constructed on demand.
class DSpoiler extends StatefulWidget {
  const DSpoiler({
    super.key,
    required this.text,
    required this.builder,
    required this.showLabel,
    required this.hideLabel,
    this.hasMedia = false,
  });
  final String text;
  final WidgetBuilder builder;
  final String showLabel;
  final String hideLabel;
  final bool hasMedia;
  @override
  State<DSpoiler> createState() => _DSpoilerState();
}

class _DSpoilerState extends State<DSpoiler> {
  bool _shown = false;
  bool _focused = false;
  final _focus = FocusNode();
  void _toggle() => setState(() => _shown = !_shown);
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Semantics(
      button: true,
      expanded: _shown,
      label: _shown ? widget.hideLabel : widget.showLabel,
      onTap: _toggle,
      child: FocusableActionDetector(
        focusNode: _focus,
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggle();
              return null;
            },
          ),
        },
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: _focused
                ? Border.all(color: tokens.focusRing, width: 2)
                : null,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            excludeFromSemantics: true,
            onTap: () {
              _focus.requestFocus();
              _toggle();
            },
            child: _shown
                ? widget.builder(context)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final painter =
                          TextPainter(
                            text: TextSpan(
                              text: widget.text.isEmpty
                                  ? '          '
                                  : widget.text,
                              style: DefaultTextStyle.of(context).style,
                            ),
                            textDirection: Directionality.of(context),
                            textScaler: MediaQuery.textScalerOf(context),
                          )..layout(
                            maxWidth: constraints.hasBoundedWidth
                                ? constraints.maxWidth
                                : double.infinity,
                          );
                      final boxes = painter
                          .getBoxesForSelection(
                            TextSelection(
                              baseOffset: 0,
                              extentOffset: painter.text!.toPlainText().length,
                            ),
                          )
                          .map((box) => box.toRect())
                          .toList();
                      final size = Size(
                        painter.width,
                        painter.height + (widget.hasMedia ? 72 : 0),
                      );
                      painter.dispose();
                      return CustomPaint(
                        size: size,
                        painter: _Redaction(
                          boxes,
                          Color.lerp(
                            tokens.background,
                            tokens.foreground,
                            .78,
                          )!,
                          widget.hasMedia,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _Redaction extends CustomPainter {
  _Redaction(this.lines, this.color, this.media);
  final List<Rect> lines;
  final Color color;
  final bool media;
  Rect? _mediaRect;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final line in lines) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(line, const Radius.circular(4)),
        paint,
      );
    }
    if (media) {
      _mediaRect = Rect.fromLTWH(0, size.height - 68, size.width, 68);
      canvas.drawRRect(
        RRect.fromRectAndRadius(_mediaRect!, const Radius.circular(6)),
        paint,
      );
    }
  }

  @override
  bool hitTest(Offset position) =>
      lines.any(
        (line) => RRect.fromRectAndRadius(
          line,
          const Radius.circular(4),
        ).contains(position),
      ) ||
      (_mediaRect != null &&
          RRect.fromRectAndRadius(
            _mediaRect!,
            const Radius.circular(6),
          ).contains(position));

  @override
  bool shouldRepaint(_Redaction old) => true;
}
