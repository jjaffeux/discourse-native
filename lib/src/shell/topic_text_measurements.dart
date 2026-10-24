import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

typedef _MeasurementConfiguration = ({
  TextStyle style,
  TextScaler textScaler,
  TextDirection textDirection,
  Locale? ambientLocale,
  TextStyle? ambientDefaultTextStyle,
  double? ambientLineHeightScaleFactor,
  double? ambientLetterSpacing,
  double? ambientWordSpacing,
});

/// Retains widths for one topic row and one typography configuration.
final class TopicTextMeasurements {
  static const maximumEntries = 128;

  final _widths = <String, double>{};
  _MeasurementConfiguration? _configuration;
  int _measurementCount = 0;

  @visibleForTesting
  int get measurementCount => _measurementCount;

  @visibleForTesting
  int get cachedEntryCount => _widths.length;

  double measure(
    String text, {
    required TextStyle style,
    required TextScaler textScaler,
    required TextDirection textDirection,
    Locale? ambientLocale,
    TextStyle? ambientDefaultTextStyle,
    double? ambientLineHeightScaleFactor,
    double? ambientLetterSpacing,
    double? ambientWordSpacing,
  }) {
    final configuration = (
      style: style,
      textScaler: textScaler,
      textDirection: textDirection,
      ambientLocale: ambientLocale,
      ambientDefaultTextStyle: ambientDefaultTextStyle,
      ambientLineHeightScaleFactor: ambientLineHeightScaleFactor,
      ambientLetterSpacing: ambientLetterSpacing,
      ambientWordSpacing: ambientWordSpacing,
    );
    if (_configuration != configuration) {
      clear();
      _configuration = configuration;
    }
    final retained = _widths.remove(text);
    if (retained != null) {
      _widths[text] = retained;
      return retained;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
    );
    try {
      painter.layout();
      _measurementCount++;
      final width = painter.width;
      if (_widths.length == maximumEntries) {
        _widths.remove(_widths.keys.first);
      }
      _widths[text] = width;
      return width;
    } finally {
      painter.dispose();
    }
  }

  void clear() {
    _widths.clear();
    _configuration = null;
  }
}
