import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The shared surface used by rendered and composer quotes.
///
/// The accent is deliberately not a one-sided [BoxDecoration.border]. Flutter
/// paints that combination with rounded corners as two nested rounded
/// rectangles, which can leave accent-coloured pixels at the opposite corners.
class QuotePanel extends StatelessWidget {
  const QuotePanel({
    super.key,
    required this.margin,
    required this.padding,
    required this.child,
  });

  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final Widget child;

  static const double _barWidth = 3;
  static const Radius _leftRadius = Radius.circular(3);
  static const BorderRadius _panelRadius = BorderRadius.horizontal(
    left: _leftRadius,
    right: Radius.circular(6),
  );
  static const BorderRadius _barRadius = BorderRadius.only(
    topLeft: _leftRadius,
    bottomLeft: _leftRadius,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: theme.shell.panel,
        borderRadius: _panelRadius,
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _barWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: _barRadius,
              ),
            ),
          ),
          Padding(
            // The old border contributed this inset through
            // BoxDecoration.padding. Keep the quote's content geometry stable.
            padding: const EdgeInsets.only(left: _barWidth),
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    );
  }
}
