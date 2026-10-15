import 'package:flutter/widgets.dart';

import '../../theme/discourse_typography.dart';

@immutable
final class AppTextScaler extends TextScaler {
  const AppTextScaler({
    required this.platformScaler,
    required this.appScale,
    this.baselineScale = 1,
  }) : assert(appScale > 0),
       assert(baselineScale > 0);

  final TextScaler platformScaler;
  final double appScale;
  final double baselineScale;

  @override
  double scale(double fontSize) =>
      platformScaler.scale(fontSize * baselineScale) * appScale;

  @override
  double get textScaleFactor {
    // flutter_widget_from_html_core still reads this compatibility value when
    // laying out cooked posts. Anchor its linear estimate to the 14px reference
    // body, including the mobile baseline, until it consumes TextScaler directly.
    return scale(DiscourseTypography.base) / DiscourseTypography.base;
  }

  @override
  bool operator ==(Object other) =>
      other is AppTextScaler &&
      other.platformScaler == platformScaler &&
      other.appScale == appScale &&
      other.baselineScale == baselineScale;

  @override
  int get hashCode => Object.hash(platformScaler, appScale, baselineScale);
}

/// Reference-sized chrome already supplies its mobile control geometry. Keep
/// app zoom and platform accessibility scaling without the reading-text uplift.
class DReferenceTextScale extends StatelessWidget {
  const DReferenceTextScale({super.key, required this.child});

  final Widget child;

  static TextScaler scalerOf(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return scaler is AppTextScaler && scaler.baselineScale != 1
        ? AppTextScaler(
            platformScaler: scaler.platformScaler,
            appScale: scaler.appScale,
          )
        : scaler;
  }

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: scalerOf(context)),
    child: child,
  );
}
