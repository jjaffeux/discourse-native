import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
// ignore: implementation_imports
import 'package:flutter_widget_from_html_core/src/internal/core_build_tree.dart';
import 'package:html/dom.dart' as dom;

List<(String, String)> bits(String text) {
  final tree = CoreBuildTree.root(
    inheritanceResolvers: InheritanceResolvers(),
    wf: WidgetFactory(),
  );
  final fragment = dom.DocumentFragment()..nodes.add(dom.Text(text));
  tree.addBitsFromNodes(fragment.nodes);
  return [
    for (final bit in tree.children)
      switch (bit) {
        TextBit(:final data) => ('text', data),
        WhitespaceBit(:final data) => ('space', data),
        _ => throw StateError('Unexpected ${bit.runtimeType}'),
      },
  ];
}

// Independent character scanner for the existing bit contract: boundary ASCII
// whitespace and internal runs are separate bits, except isolated internal U+0020.
List<(String, String)> reference(String text) {
  bool space(int i) => [9, 10, 12, 13, 32].contains(text.codeUnitAt(i));
  final result = <(String, String)>[];
  var start = 0;
  var i = 0;
  while (i < text.length) {
    if (!space(i)) {
      i++;
      continue;
    }
    final first = i;
    while (i < text.length && space(i)) {
      i++;
    }
    if (first > 0 && i < text.length && i == first + 1 && text[first] == ' ') {
      continue;
    }
    if (first > start) {
      result.add(('text', text.substring(start, first)));
    }
    result.add(('space', text.substring(first, i)));
    start = i;
  }
  if (start < text.length) {
    result.add(('text', text.substring(start)));
  }
  // The upstream empty-text behavior produces an empty whitespace bit.
  if (text.isEmpty) {
    result.add(('space', ''));
  }
  return result;
}

void main() {
  test('ASCII runs preserve boundaries and isolated ordinary spaces', () {
    for (final text in [
      '',
      ' ',
      '\t\r\n\f  ',
      'one two three',
      ' one two ',
      'one  two',
      'one\ttwo',
      'one \n two\rthree\ffour',
      'café\u00a0日本語 😀 words',
      'a\u000bb\u2003c',
      'a \t b  c\n d ',
      '\u00a0 one \u00a0',
      'a \u2028',
      'a \u2029',
      ' مرحبا بالعالم שלום עולם ',
      'a${List.filled(4096, ' ').join()}b',
      List.filled(4096, ' ').join(),
    ]) {
      expect(bits(text), reference(text), reason: text);
    }
  });

  test('mixed Unicode and whitespace produce the same build-bit stream', () {
    final random = Random(391616);
    const alphabet = [
      'a',
      'é',
      '日',
      '😀',
      ' ',
      '\t',
      '\n',
      '\r',
      '\f',
      '\u00a0',
      '\u2003',
      '\u000b',
      '\ud800',
      '\udfff',
      '\u2028',
      '\u2029'
    ];
    for (var i = 0; i < 1000; i++) {
      final text = List.generate(random.nextInt(100),
          (_) => alphabet[random.nextInt(alphabet.length)]).join();
      expect(bits(text), reference(text), reason: 'sample $i');
    }
  });

  test('long ordinary prose stays one text bit with every space intact', () {
    final text = List.generate(2000, (i) => 'word$i').join(' ');
    expect(bits(text), [('text', text)]);
  });
}
