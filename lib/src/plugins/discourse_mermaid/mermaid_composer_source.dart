/// A complete top-level fence; original delimiters and whitespace stay intact.
class MermaidComposerBlock {
  const MermaidComposerBlock(
    this.start,
    this.end,
    this.source,
    this.bodyStart,
    this.bodyEnd,
  );
  final int start, end, bodyStart, bodyEnd;
  final String source;
  String get code => source.substring(bodyStart, bodyEnd);

  String replaceCode(String code) {
    var opening = source.substring(0, bodyStart);
    var closing = source.substring(bodyEnd);
    final fence = RegExp(r'`{3,}|~{3,}').firstMatch(opening)!.group(0)!;
    final candidates = RegExp(fence[0] == '`' ? r'`+' : r'~+').allMatches(code);
    var length = fence.length;
    for (final match in candidates) {
      if (match.group(0)!.length >= length) length = match.group(0)!.length + 1;
    }
    if (length != fence.length) {
      final replacement = fence[0] * length;
      opening = opening.replaceFirst(fence, replacement);
      closing = closing.replaceFirst(
        RegExp(fence[0] == '`' ? r'`{3,}' : r'~{3,}'),
        replacement,
      );
    }
    if (!closing.startsWith('\n') && !closing.startsWith('\r\n')) {
      closing = '${opening.endsWith('\r\n') ? '\r\n' : '\n'}$closing';
    }
    return '$opening$code$closing';
  }
}

/// Scan all fences so examples nested inside another code block stay literal.
List<MermaidComposerBlock> parseMermaidComposerBlocks(String source) {
  final lines = RegExp(
    r'[^\n]*(?:\n|$)',
  ).allMatches(source).where((m) => m.start < source.length).toList();
  final result = <MermaidComposerBlock>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final open = RegExp(
      r'^ {0,3}(`{3,}|~{3,})([^\r\n]*)\r?\n$',
    ).firstMatch(line.group(0)!);
    if (open == null) continue;
    final fence = open.group(1)!;
    final info = open.group(2)!.trim();
    if (fence[0] == '`' && info.contains('`')) continue;
    final close = RegExp(
      '^ {0,3}${fence[0]}{${fence.length},}[ \\t]*\\r?\\n?\$',
    );
    var j = i + 1;
    while (j < lines.length && !close.hasMatch(lines[j].group(0)!)) {
      j++;
    }
    if (j == lines.length) break;
    if (info == 'mermaid') {
      // The block ends with its closing fence. A CRLF belongs to the gap after
      // it, as it does for every other component.
      var end = lines[j].end;
      if (source[end - 1] == '\n') end--;
      if (end > lines[j].start && source[end - 1] == '\r') end--;
      var bodyEnd = lines[j].start;
      if (bodyEnd > line.end && source[bodyEnd - 1] == '\n') bodyEnd--;
      if (bodyEnd > line.end && source[bodyEnd - 1] == '\r') bodyEnd--;
      // Empty fences still need a separator when their first code is inserted.
      final blockSource = source.substring(line.start, end);
      result.add(
        MermaidComposerBlock(
          line.start,
          end,
          blockSource,
          line.end - line.start,
          bodyEnd - line.start,
        ),
      );
    }
    i = j;
  }
  return result;
}
