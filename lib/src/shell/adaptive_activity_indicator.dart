import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AdaptiveActivityIndicator extends StatelessWidget {
  const AdaptiveActivityIndicator({
    super.key,
    required this.color,
    this.cupertinoRadius = 10,
    this.materialStrokeWidth = 4,
  });

  final Color color;
  final double cupertinoRadius;
  final double materialStrokeWidth;

  @override
  Widget build(BuildContext context) => switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => CupertinoActivityIndicator(
      color: color,
      radius: cupertinoRadius,
    ),
    _ => CircularProgressIndicator(
      color: color,
      strokeWidth: materialStrokeWidth,
    ),
  };
}
