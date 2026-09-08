import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../models/json.dart';

/// Plain text for the inbox. The channel index already supplies an excerpt,
/// so rendering the drawer does not need to fetch each conversation.
String? chatMessageSummary({
  Object? excerpt,
  Object? cooked,
  Object? raw,
  bool deleted = false,
  bool hasUploads = false,
}) {
  if (deleted) return 'Message deleted';
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
        if (node.localName == 'img') {
          buffer.write(node.attributes['alt'] ?? '');
          return;
        }
      }
      for (final child in node.nodes) {
        visit(child);
      }
      if (node is dom.Element &&
          const {
            'br',
            'p',
            'div',
            'li',
            'blockquote',
          }.contains(node.localName)) {
        buffer.write(' ');
      }
    }

    // Chat's normal message ceiling is 20,000 characters. Bound parsing before
    // constructing a DOM for an unexpectedly large server response.
    visit(
      html.parseFragment(source.substring(0, source.length.clamp(0, 20000))),
    );
    text = jsonText(buffer.toString());
  }
  text ??= jsonText(raw);
  if (text == null) return hasUploads ? 'Attachment' : null;
  final singleLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final runes = singleLine.runes.take(241).toList(growable: false);
  return runes.length > 240
      ? '${String.fromCharCodes(runes.take(240))}…'
      : singleLine;
}

String? chatMessageSummaryFromJson(Map<String, dynamic> json) =>
    chatMessageSummary(
      excerpt: json['excerpt'],
      cooked: json['cooked'],
      raw: json['message'],
      deleted: json['deleted_at'] != null,
      hasUploads: jsonArray(json['uploads']).isNotEmpty,
    );
