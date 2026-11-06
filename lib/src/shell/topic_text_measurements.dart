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

/// Retains bounded text widths across recent typography configurations.
///
/// Topic footers ask for a few widths each as rows enter the list, so a
/// retained width costs one lookup: a configuration's text styles are hashed
/// once, when it is interned, and recency is a counter rather than a
/// reinsertion.
final class TopicTextMeasurements {
  /// A live forum's list window holds a few hundred distinct ages, counts,
  /// tags and category names; fewer entries re-shape most of them per pass.
  static const maximumEntries = 512;

  /// Configurations beyond this many clear the cache: typography changes are
  /// rare, but a text scale slider produces a new scaler per step.
  static const maximumConfigurations = 32;

  final _configurations = <_MeasurementConfiguration, int>{};
  final _widths = <(String, int), _RetainedWidth>{};
  int _generation = 0;
  int _clock = 0;
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
  }) => measurer(
    style: style,
    textScaler: textScaler,
    textDirection: textDirection,
    ambientLocale: ambientLocale,
    ambientDefaultTextStyle: ambientDefaultTextStyle,
    ambientLineHeightScaleFactor: ambientLineHeightScaleFactor,
    ambientLetterSpacing: ambientLetterSpacing,
    ambientWordSpacing: ambientWordSpacing,
  ).measure(text);

  /// Measures texts in one typography configuration, which it interns on
  /// first use and again after [clear].
  TopicTextMeasurer measurer({
    required TextStyle style,
    required TextScaler textScaler,
    required TextDirection textDirection,
    Locale? ambientLocale,
    TextStyle? ambientDefaultTextStyle,
    double? ambientLineHeightScaleFactor,
    double? ambientLetterSpacing,
    double? ambientWordSpacing,
  }) => TopicTextMeasurer._(this, (
    style: style,
    textScaler: textScaler,
    textDirection: textDirection,
    ambientLocale: ambientLocale,
    ambientDefaultTextStyle: ambientDefaultTextStyle,
    ambientLineHeightScaleFactor: ambientLineHeightScaleFactor,
    ambientLetterSpacing: ambientLetterSpacing,
    ambientWordSpacing: ambientWordSpacing,
  ));

  int _intern(_MeasurementConfiguration configuration) {
    if (_configurations[configuration] case final id?) return id;
    if (_configurations.length == maximumConfigurations) clear();
    return _configurations[configuration] = _configurations.length;
  }

  double _measure(
    String text,
    int configurationId,
    _MeasurementConfiguration configuration,
  ) {
    final key = (text, configurationId);
    if (_widths[key] case final retained?) {
      retained.used = ++_clock;
      return retained.width;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: configuration.style),
      textDirection: configuration.textDirection,
      textScaler: configuration.textScaler,
    );
    try {
      painter.layout();
      _measurementCount++;
      final width = painter.width;
      if (_widths.length == maximumEntries) _evictLeastRecentlyUsed();
      _widths[key] = _RetainedWidth(width, ++_clock);
      return width;
    } finally {
      painter.dispose();
    }
  }

  // A miss already shapes a paragraph; scanning the bounded entries for the
  // oldest costs far less, and keeps hits free of map reordering.
  void _evictLeastRecentlyUsed() {
    (String, int)? oldest;
    var oldestUse = 0;
    for (final MapEntry(:key, :value) in _widths.entries) {
      if (oldest == null || value.used < oldestUse) {
        oldest = key;
        oldestUse = value.used;
      }
    }
    _widths.remove(oldest);
  }

  void clear() {
    _widths.clear();
    _configurations.clear();
    _generation++;
  }
}

/// Measures texts for [TopicTextMeasurements] in one typography
/// configuration.
final class TopicTextMeasurer {
  TopicTextMeasurer._(this._cache, this._configuration);

  final TopicTextMeasurements _cache;
  final _MeasurementConfiguration _configuration;
  int _generation = -1;
  int _id = 0;

  double measure(String text) {
    if (_generation != _cache._generation) {
      _id = _cache._intern(_configuration);
      _generation = _cache._generation;
    }
    return _cache._measure(text, _id, _configuration);
  }
}

final class _RetainedWidth {
  _RetainedWidth(this.width, this.used);

  final double width;
  int used;
}
