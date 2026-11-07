import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

const _summaryBlocks = {
  'br',
  'p',
  'div',
  'li',
  'blockquote',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'tr',
  'th',
  'td',
};

/// Plain text for the inbox. The channel index already supplies an excerpt,
/// so rendering the channel list does not need to fetch each conversation.
String? chatMessageSummary({
  Object? excerpt,
  Object? cooked,
  Object? raw,
  bool deleted = false,
  bool hasUploads = false,
}) {
  if (deleted) return appL10n.messageDeleted;
  final source = jsonText(excerpt) ?? jsonText(cooked);
  String? text;
  if (source != null) {
    final buffer = StringBuffer();
    void visit(dom.Node node) {
      if (node is dom.Text) {
        buffer.write(node.data);
        return;
      }
      if (node is dom.Element) {
        if (const {'script', 'style'}.contains(node.localName)) return;
        if (_summaryBlocks.contains(node.localName)) buffer.write(' ');
        if (node.localName == 'img') {
          buffer.write(node.attributes['alt'] ?? '');
          return;
        }
      }
      for (final child in node.nodes) {
        visit(child);
      }
      if (node is dom.Element && _summaryBlocks.contains(node.localName)) {
        buffer.write(' ');
      }
    }

    // Chat's normal message ceiling is 20,000 characters. Bound parsing before
    // constructing a DOM for an unexpectedly large server response.
    visit(html.parseFragment(_boundedSummarySource(source)));
    text = jsonText(buffer.toString());
  }
  text ??= jsonText(raw);
  if (text == null) return hasUploads ? appL10n.attachment : null;
  final singleLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final characters = singleLine.characters.take(241);
  return characters.length > 240 ? '${characters.take(240)}…' : singleLine;
}

String _boundedSummarySource(String source) {
  const maximum = 20000;
  if (source.length <= maximum) return source;
  // One scalar beyond the budget reveals a cluster crossing its boundary.
  final prefix = source.substring(0, source.length.clamp(0, maximum + 2));
  var end = 0;
  for (final character in prefix.characters) {
    if (end + character.length > maximum) break;
    end += character.length;
  }
  return source.substring(0, end);
}

String? chatMessageSummaryFromJson(Map<String, dynamic> json) =>
    chatMessageSummary(
      excerpt: json['excerpt'],
      cooked: json['cooked'],
      raw: json['message'],
      deleted: json['deleted_at'] != null,
      hasUploads: jsonArray(json['uploads']).isNotEmpty,
    );
