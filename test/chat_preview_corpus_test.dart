import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugins/chat/chat_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// A small checked-in differential corpus copied from Discourse chat cooking
/// expectations (`plugins/chat/spec/models/chat/message_spec.rb`). Comparing a
/// semantic stream keeps harmless HTML wrapper changes out of this contract.
void main() {
  final fixtures =
      (jsonDecode(
                File(
                  'test/fixtures/chat_preview_corpus.json',
                ).readAsStringSync(),
              )
              as List<dynamic>)
          .cast<Map<String, dynamic>>();
  final engine = ChatPreviewEngine();

  for (final fixture in fixtures) {
    test('${fixture['name']} matches the cooked semantic presentation', () {
      final raw = fixture['raw'] as String;
      final cooked = fixture['cooked'] as String;
      final result = engine.project(
        ChatPreviewRequest(raw: raw, siteConfig: const SiteConfig.unknown()),
      );

      expect(
        result,
        isA<ProjectedPreview>(),
        reason: fixture['name'] as String,
      );
      final document = (result as ProjectedPreview).document;
      expect(
        _previewSemantics(document),
        _cookedSemantics(cooked),
        reason: fixture['name'] as String,
      );
    });
  }
}

List<String> _previewSemantics(PreviewDocument document) {
  final segments = <({String text, Set<String> styles})>[];
  for (final node in document.nodes) {
    switch (node) {
      case ChatPreviewText(:final text, :final styles):
        _add(segments, text, {
          for (final style in styles)
            switch (style) {
              ChatPreviewTextStyle.bold => 'bold',
              ChatPreviewTextStyle.italic => 'italic',
              ChatPreviewTextStyle.strikethrough => 'strike',
              ChatPreviewTextStyle.code => 'code',
            },
        });
      case ChatPreviewLineBreak():
        _add(segments, '\n', const {});
      case ChatPreviewCodeBlock(:final code):
        _add(segments, code, const {'code-block'});
      case ChatPreviewSyntax():
        break;
      case PluginPreviewNode(:final fallbackText) ||
          ChatPreviewImage(fallbackText: final fallbackText):
        _add(segments, fallbackText, const {});
    }
  }
  return _serialize(segments);
}

List<String> _cookedSemantics(String cooked) {
  final segments = <({String text, Set<String> styles})>[];
  final fragment = html_parser.parseFragment(cooked);

  void visit(dom.Node node, Set<String> inherited) {
    if (node is dom.Text) {
      _add(segments, node.data, inherited);
      return;
    }
    if (node is! dom.Element) {
      for (final child in node.nodes) {
        visit(child, inherited);
      }
      return;
    }
    if (node.localName == 'pre') {
      _add(segments, node.text, const {'code-block'});
      return;
    }
    if (node.localName == 'br') {
      _add(segments, '\n', inherited);
      return;
    }
    final styles = {...inherited};
    switch (node.localName) {
      case 'strong' || 'b':
        styles.add('bold');
      case 'em' || 'i':
        styles.add('italic');
      case 's' || 'del':
        styles.add('strike');
      case 'code':
        styles.add('code');
    }
    for (final child in node.nodes) {
      visit(child, styles);
    }
  }

  for (final node in fragment.nodes) {
    visit(node, const {});
  }
  return _serialize(segments);
}

void _add(
  List<({String text, Set<String> styles})> segments,
  String text,
  Set<String> styles,
) {
  if (text.isEmpty) return;
  final immutableStyles = Set<String>.unmodifiable(styles);
  if (segments.isNotEmpty && setEquals(segments.last.styles, immutableStyles)) {
    final previous = segments.removeLast();
    segments.add((text: previous.text + text, styles: immutableStyles));
    return;
  }
  segments.add((text: text, styles: immutableStyles));
}

List<String> _serialize(List<({String text, Set<String> styles})> segments) => [
  for (final segment in segments)
    '${(segment.styles.toList()..sort()).join('+')}|${jsonEncode(segment.text)}',
];
