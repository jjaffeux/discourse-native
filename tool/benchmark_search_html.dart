import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/progressive_html_mode.dart';
import 'package:discourse_native/src/shell/search_words.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

final _body = ValueNotifier<Widget>(const SizedBox.shrink());
final _boundary = GlobalKey();

String _source(int count, int revision) => List.generate(
  count,
  (i) =>
      '<p>Paragraph $i revision $revision needle with <b>bold needle</b> '
      'and <i>italic needle</i> text.</p>',
).join();

Future<void> main() async {
  final binding = _Binding();
  final rows = <Map<String, Object?>>[];
  final errors = <String>[];
  FlutterError.onError = (details) => errors.add(details.exceptionAsString());
  try {
    if (!kProfileMode) throw StateError('Run in profile mode.');
    runApp(
      MaterialApp(
        theme: AppTheme.light,
        home: DPageSurface(
          child: SingleChildScrollView(
            child: SizedBox(
              width: 500,
              child: ValueListenableBuilder<Widget>(
                valueListenable: _body,
                builder: (_, child, _) =>
                    SizedBox(key: _boundary, child: child),
              ),
            ),
          ),
        ),
      ),
    );
    await binding.endOfFrame;
    for (final (label, count) in [
      ('ordinary', 20),
      ('medium', 400),
      ('large', 1800),
    ]) {
      for (var repeat = -1; repeat < 5; repeat++) {
        final source = _source(count, repeat);
        final expected = List.generate(
          count,
          (i) =>
              'Paragraph $i revision $repeat needle with bold needle and italic needle text.',
        ).join();
        final microSource = source.replaceAll('revision ', 'baseline ');
        final baselineWork = Stopwatch()..start();
        final highlighted = highlightSearchHtml(microSource, 'needle');
        baselineWork.stop();
        if ('native-search-hit'.allMatches(highlighted).length != count * 3) {
          throw StateError('Incorrect highlight count.');
        }
        for (final cached in [false, true]) {
          final elapsed = Stopwatch()..start();
          final costs = <int>[];
          final gaps = <int>[];
          final gapWatch = Stopwatch()..start();
          final heartbeat = Timer.periodic(const Duration(milliseconds: 1), (
            _,
          ) {
            gaps.add(gapWatch.elapsedMicroseconds);
            gapWatch.reset();
          });
          var before = binding.uiMicroseconds;
          _body.value = SearchWords(
            query: 'needle',
            child: CookedHtml(
              key: UniqueKey(),
              html: source,
              renderMode: const ProgressiveHtmlMode(),
            ),
          );
          var complete = false;
          var textUnits = 0;
          var highlightedUnits = 0;
          var inspectionUs = 0;
          for (var frame = 0; frame < 500; frame++) {
            await binding.endOfFrame.timeout(const Duration(seconds: 60));
            costs.add(binding.uiMicroseconds - before);
            final inspection = Stopwatch()..start();
            final texts = _texts(_boundary.currentContext! as Element).toList();
            final text = texts.map((w) => w.text.toPlainText()).join();
            complete = text == expected;
            if (complete) {
              textUnits = text.length;
              highlightedUnits = texts.fold(0, (n, w) => n + _hits(w.text));
            }
            inspectionUs += inspection.elapsedMicroseconds;
            if (complete) break;
            before = binding.uiMicroseconds;
          }
          elapsed.stop();
          heartbeat.cancel();
          if (!complete || highlightedUnits != count * 18) {
            throw StateError(
              'Incomplete body or highlighting $label $repeat $highlightedUnits.',
            );
          }
          if (repeat >= 0) {
            rows.add({
              'label': label,
              'repeat': repeat,
              'remount': cached,
              'sourceUnits': source.length,
              'outputUnits': highlighted.length,
              'legacyPreprocessUs': baselineWork.elapsedMicroseconds,
              'endToEndUs': elapsed.elapsedMicroseconds - inspectionUs,
              'uiFramesUs': costs,
              'eventLoopGapsUs': gaps,
              'textUnits': textUnits,
              'highlightedUnits': highlightedUnits,
            });
          }
          _body.value = const SizedBox.shrink();
          await binding.endOfFrame;
        }
      }
    }
  } catch (error, stack) {
    errors.add('$error\n$stack');
  }
  stdout.writeln(
    'SEARCH_HTML_REPORT ${jsonEncode({'mode': kProfileMode ? 'profile' : 'other', 'dart': Platform.version, 'processors': Platform.numberOfProcessors, 'maxRss': ProcessInfo.maxRss, 'rows': rows, 'failures': errors})}',
  );
  await stdout.flush();
  exit(errors.isEmpty ? 0 : 1);
}

final class _Binding extends WidgetsFlutterBinding {
  int uiMicroseconds = 0;
  @override
  void drawFrame() {
    final watch = Stopwatch()..start();
    super.drawFrame();
    uiMicroseconds += watch.elapsedMicroseconds;
  }
}

Iterable<RichText> _texts(Element element) sync* {
  if (element.widget case final RichText text) yield text;
  final children = <Element>[];
  element.visitChildren(children.add);
  for (final child in children) {
    yield* _texts(child);
  }
}

int _hits(InlineSpan span, [bool highlighted = false]) {
  if (span is! TextSpan) return 0;
  final active =
      span.style?.backgroundColor != null ||
      span.style?.background != null ||
      highlighted;
  return (active ? span.text?.length ?? 0 : 0) +
      (span.children ?? []).fold<int>(
        0,
        (n, child) => n + _hits(child, active),
      );
}
