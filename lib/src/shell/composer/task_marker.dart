import 'package:html/parser.dart' as html;

final _marker = RegExp(r'(\[[ xX]?\])[ \t]*');
final _referenceLabel = RegExp(r'\[((?:\\.|[^\[\]\\])*)\]');
final _referenceWhitespace = RegExp(r'\s+');
final _paragraphBreak = RegExp(r'\r?\n[ \t]*\r?\n');
final _blockedLinkScheme = RegExp(r'^(?:vbscript|javascript|file|data):');
final _imageDataScheme = RegExp(r'^data:image/(?:gif|png|jpeg|webp);');
final _linkEscape = RegExp(
  r'\\([!-/:-@\[-`{-~])|&(?:#[xX][\da-fA-F]+|#\d+|[a-zA-Z][a-zA-Z0-9]+);',
);

String composerTaskReferenceLabel(String label) =>
    '[${label.trim().replaceAll(_referenceWhitespace, ' ').toLowerCase()}]';

/// The checklist plugin runs after Markdown's link rule. A marker may touch
/// its body, but a valid inline or reference link still owns its brackets.
/// The match includes only the marker and its optional horizontal whitespace.
Match? composerTaskMarker(
  String source, {
  int start = 0,
  int? end,
  Set<String> referenceMarkers = const {},
}) {
  final marker = _marker.matchAsPrefix(source, start);
  if (marker == null) return null;
  final markerEnd = start + marker[1]!.length;
  if (_inlineLink(source, markerEnd, end ?? source.length)) return null;
  final reference = _referenceLabel.matchAsPrefix(source, markerEnd);
  final label = reference != null && reference[1]!.isNotEmpty
      ? composerTaskReferenceLabel(reference[1]!)
      : marker[1]!.toLowerCase();
  return referenceMarkers.contains(label) ? null : marker;
}

// Match the destination/title forms accepted by the bundled markdown-it link
// rule, including empty destinations, escapes and balanced parentheses. Merely
// seeing '(' is insufficient: '[x](unfinished' is still a valid checklist.
bool _inlineLink(String source, int offset, int end) {
  if (offset >= end || source[offset] != '(') return false;
  final paragraphEnd = source.indexOf(_paragraphBreak, offset);
  if (paragraphEnd >= 0 && paragraphEnd < end) end = paragraphEnd;
  var position = _skipSpace(source, offset + 1, end);
  final start = position;
  if (position >= end) return false;
  if (source[position] == ')') return true;
  if (source[position] == '<') {
    position++;
    while (position < end && source[position] != '>') {
      final char = source[position];
      if (char == '\n' || char == '\r' || char == '<') return false;
      position += char == '\\' && position + 1 < end ? 2 : 1;
    }
    if (position == end) return false;
    position++;
  } else {
    var depth = 0;
    while (position < end) {
      final char = source.codeUnitAt(position);
      if (char <= 32 || char == 127) break;
      if (char == 92 && position + 1 < end) {
        position += source[position + 1] == ' ' ? 1 : 2;
        continue;
      }
      if (char == 40 && ++depth > 32) return false;
      if (char == 41) {
        if (depth == 0) break;
        depth--;
      }
      position++;
    }
    if (position == start || depth != 0) return false;
  }
  final destination = source.substring(start, position);
  final url =
      (destination.startsWith('<')
              ? destination.substring(1, destination.length - 1)
              : destination)
          .replaceAllMapped(
            _linkEscape,
            (match) =>
                match[1] ?? html.parseFragment(match[0]!).text ?? match[0]!,
          )
          .trim()
          .toLowerCase();
  if (_blockedLinkScheme.hasMatch(url) && !_imageDataScheme.hasMatch(url)) {
    return false;
  }
  final destinationEnd = position;
  position = _skipSpace(source, position, end);
  if (position > destinationEnd && position < end) {
    final opening = source[position];
    if (opening == '"' || opening == "'" || opening == '(') {
      final closing = opening == '(' ? ')' : opening;
      position++;
      while (position < end && source[position] != closing) {
        final char = source[position];
        if (opening == '(' && char == '(') return false;
        position += char == '\\' && position + 1 < end ? 2 : 1;
      }
      if (position == end) return false;
      position = _skipSpace(source, position + 1, end);
    }
  }
  return position < end && source[position] == ')';
}

int _skipSpace(String source, int offset, int end) {
  while (offset < end && ' \t\r\n'.contains(source[offset])) {
    offset++;
  }
  return offset;
}
