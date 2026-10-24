import 'markdown_tokens.dart';

/// Block admission follows the cooker, independently of editable table cells.
bool composerMarkdownTableHeader(
  String header,
  String delimiter, {
  Iterable<ComposerMarkdownTokenBoundary> tokens = const [],
  int offset = 0,
}) {
  final rule = delimiter.trim();
  if (rule.length < 2 ||
      !_tableDelimiterCharacters.hasMatch(rule) ||
      rule.startsWith('- ') ||
      rule.startsWith('-\t')) {
    return false;
  }
  final columns = rule.split('|');
  if (columns.first.trim().isEmpty) columns.removeAt(0);
  if (columns.isNotEmpty && columns.last.trim().isEmpty) columns.removeLast();
  if (columns.isEmpty ||
      !columns.every((cell) => _tableDelimiterCell.hasMatch(cell.trim()))) {
    return false;
  }
  final text = header.trim();
  if (!text.contains('|')) return false;
  final from = header.indexOf(text);
  final protected = tokens.toList()
    ..sort((left, right) => left.openerStart.compareTo(right.openerStart));
  var token = 0;
  var hasPipe = false;
  final pipes = <int>[];
  for (var at = 0; at < text.length; at++) {
    final position = offset + from + at;
    while (token < protected.length && position >= protected[token].tokenEnd) {
      token++;
    }
    if (text[at] == '|' &&
        !(token < protected.length &&
            position >= protected[token].openerStart)) {
      hasPipe = true;
      if (at == 0 || text[at - 1] != r'\') pipes.add(at);
    }
  }
  if (!hasPipe) return false;
  final count =
      pipes.length +
      1 -
      (pipes.firstOrNull == 0 ? 1 : 0) -
      (pipes.lastOrNull == text.length - 1 ? 1 : 0);
  return count == columns.length;
}

final _tableDelimiterCharacters = RegExp(r'^[|:\- \t]+$');
final _tableDelimiterCell = RegExp(r'^:?-+:?$');
