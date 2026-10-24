import 'package:discourse_native/src/shell/topic_text_measurements.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const style = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);

  double width(
    TopicTextMeasurements cache,
    String text, {
    TextStyle textStyle = style,
    TextScaler scaler = TextScaler.noScaling,
    TextDirection direction = TextDirection.ltr,
    Locale? locale,
    TextStyle? inherited,
    double? lineHeight,
    double? letterSpacing,
    double? wordSpacing,
  }) => cache.measure(
    text,
    style: textStyle,
    textScaler: scaler,
    textDirection: direction,
    ambientLocale: locale,
    ambientDefaultTextStyle: inherited,
    ambientLineHeightScaleFactor: lineHeight,
    ambientLetterSpacing: letterSpacing,
    ambientWordSpacing: wordSpacing,
  );

  test('retained text is shaped once and matches uncached painter widths', () {
    final cache = TopicTextMeasurements();
    for (final text in [
      'Category',
      '#Café👩🏽‍💻',
      '+12',
      '12.4k',
      '…',
      'العربية',
    ]) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textScaler: TextScaler.noScaling,
        textDirection: TextDirection.ltr,
      )..layout();
      final expected = painter.width;
      painter.dispose();
      expect(width(cache, text), expected);
      expect(width(cache, text), expected);
    }
    expect(cache.measurementCount, 6);
    expect(cache.cachedEntryCount, 6);
  });

  test('every effective typography dependency invalidates retained widths', () {
    final cache = TopicTextMeasurements();
    void verify(double Function() request) {
      final before = cache.measurementCount;
      final result = request();
      expect(request(), result);
      expect(cache.measurementCount, before + 1);
      expect(cache.cachedEntryCount, 1);
    }

    verify(() => width(cache, 'metadata'));
    for (final changed in [
      style.copyWith(fontFamily: 'Lato'),
      style.copyWith(fontFamilyFallback: ['Lato', 'serif']),
      style.copyWith(fontSize: 16),
      style.copyWith(fontWeight: FontWeight.bold),
      style.copyWith(fontStyle: FontStyle.italic),
      style.copyWith(letterSpacing: 1),
      style.copyWith(wordSpacing: 2),
      style.copyWith(height: 1.8),
      style.copyWith(fontFeatures: [const FontFeature.tabularFigures()]),
      style.copyWith(fontVariations: [const FontVariation('wght', 600)]),
    ]) {
      verify(() => width(cache, 'metadata', textStyle: changed));
    }
    verify(() => width(cache, 'metadata', scaler: const TextScaler.linear(2)));
    verify(() => width(cache, 'metadata', scaler: const _NonlinearScaler()));
    verify(() => width(cache, 'metadata', direction: TextDirection.rtl));
    verify(() => width(cache, 'metadata', locale: const Locale('ja')));
    verify(
      () => width(
        cache,
        'metadata',
        inherited: const TextStyle(fontFamily: 'serif'),
      ),
    );
    verify(() => width(cache, 'metadata', lineHeight: 1.2));
    verify(() => width(cache, 'metadata', letterSpacing: 1));
    verify(() => width(cache, 'metadata', wordSpacing: 2));
  });

  test('least recently used eviction keeps retention bounded', () {
    final cache = TopicTextMeasurements();
    for (var i = 0; i < TopicTextMeasurements.maximumEntries; i++) {
      width(cache, 'label-$i');
    }
    width(cache, 'label-0');
    width(cache, 'new-label');
    expect(cache.cachedEntryCount, TopicTextMeasurements.maximumEntries);
    final before = cache.measurementCount;
    width(cache, 'label-0');
    expect(cache.measurementCount, before);
    width(cache, 'label-1');
    expect(cache.measurementCount, before + 1);
    expect(cache.cachedEntryCount, TopicTextMeasurements.maximumEntries);
  });

  test('clear discards text after font or owner invalidation', () {
    final cache = TopicTextMeasurements();
    final before = width(cache, 'private category');
    cache.clear();
    expect(cache.cachedEntryCount, 0);
    expect(width(cache, 'private category'), before);
    expect(cache.measurementCount, 2);
  });
}

final class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) => fontSize + fontSize * fontSize / 20;
  @override
  double get textScaleFactor => 1.5;
}
