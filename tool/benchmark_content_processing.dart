import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/models/post_checklist.dart';
import 'package:discourse_native/src/shell/composer/html_comments.dart';
import 'package:discourse_native/src/shell/composer/markdown_tokens.dart';

void main() {
  final results = {
    'post_checklist_30_boxes_us': _measure(300, _checklistWork()),
    'composer_literals_80_paragraphs_us': _measure(800, _literalWork()),
    'composer_links_40_links_us': _measure(800, _linkWork()),
  };
  stdout.writeln(jsonEncode(results));
  exit(0);
}

double _measure(int iterations, int Function(int) process) {
  final expected = process(0);
  final samples = <double>[];
  for (var batch = 0; batch < 10; batch++) {
    var checksum = 0;
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      checksum += process(i);
    }
    watch.stop();
    if (checksum != expected * iterations) {
      throw StateError('Timed output checksum changed');
    }
    if (batch >= 3) {
      samples.add(watch.elapsedMicroseconds / iterations);
    }
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

int Function(int) _checklistWork() {
  final source = [
    '<p>Tasks and setup notes</p>',
    for (var i = 0; i < 30; i++)
      '<p><span class="chcklst-box fa-square-o" data-chk-src="$i:0" '
          'aria-checked="false"></span> Task $i &amp; notes '
          '<em>Verify this before release</em></p>',
    '<aside class="quote" data-post="10" data-native-checklist-index="90">'
        '<span class="chcklst-box checked" data-native-checklist-index="91"></span> Quoted</aside>',
  ].join();
  final annotated = source
      .replaceAll(RegExp(r' data-native-checklist-index="9[01]"'), '')
      .replaceAllMapped(
        RegExp(r'data-chk-src="(\d+):0" aria-checked="false"'),
        (match) => '${match[0]} data-native-checklist-index="${match[1]}"',
      );
  return (_) {
    final document = PostChecklistDocument(source);
    final targets = document.targets;
    final result = document.annotatedHtml;
    if (result != annotated ||
        targets.length != 30 ||
        targets.first.source != '0:0' ||
        targets.last.source != '29:0') {
      throw StateError('Displayed checklist changed');
    }
    return result.length + targets.length;
  };
}

int Function(int) _literalWork() {
  final source = List.generate(
    80,
    (i) =>
        'Paragraph $i describes the topic, provides a concrete '
        'example, and ends with a question about the next step.\n\n',
  ).join();
  return (i) {
    final draft = i.isEven ? '${source}x' : '${source}y';
    final result = ComposerLiteralContainers(draft);
    if (!result.isEmpty || !identical(draft, result.mask(draft))) {
      throw StateError('Prose unexpectedly contains a literal container');
    }
    return draft.length;
  };
}

int Function(int) _linkWork() {
  final paragraphs = List.generate(
    40,
    (i) =>
        'Paragraph $i describes the topic and provides several notes. '
        'See [the related discussion](https://example.test/topic/$i) '
        'for another example and follow-up questions.\n\n',
  );
  final source = paragraphs.join();
  final expected = <int, ComposerMarkdownTokenBoundary>{};
  var offset = 0;
  for (final paragraph in paragraphs) {
    final open = offset + paragraph.indexOf('[');
    final close = offset + paragraph.indexOf(']');
    expected[open] = (
      openerStart: open,
      labelStart: open + 1,
      labelEnd: close,
      destinationStart: close + 2,
      tokenEnd: offset + paragraph.indexOf(')') + 1,
    );
    offset += paragraph.length;
  }
  return (i) {
    final result = composerMarkdownLinkCandidates(
      i.isEven ? '${source}x' : '${source}y',
    );
    if (result.length != expected.length) {
      throw StateError('Markdown link count changed');
    }
    var checksum = 0;
    for (final entry in expected.entries) {
      final token = result[entry.key];
      if (token != entry.value) throw StateError('Link boundaries changed');
      checksum += token!.tokenEnd;
    }
    return checksum;
  };
}
