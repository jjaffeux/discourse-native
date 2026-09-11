/// Removes comments and strings so examples and nested labels cannot affect
/// the source boundary check. Newlines and offsets are preserved for diagnostics.
String controlCode(String source) => source.replaceAllMapped(
  RegExp(
    r'''//[^\n]*|/\*[\s\S]*?\*/|r?"""[\s\S]*?"""|r?\x27\x27\x27[\s\S]*?\x27\x27\x27|r?"(?:\\.|[^"\\])*"|r?\x27(?:\\.|[^\x27\\])*\x27''',
  ),
  (match) => match[0]!.replaceAll(RegExp(r'[^\n]'), ' '),
);

/// Counts only DButton's own named styling arguments, excluding arguments in
/// child widgets. Keying by property keeps a new override visible in review.
Map<String, int> buttonStyleOverrides(String source) {
  final code = controlCode(source);
  final result = <String, int>{};
  for (final constructor in RegExp(
    r'\bDButton(?:\.iconOnly)?\s*\(',
  ).allMatches(code)) {
    var depth = 1;
    var end = constructor.end;
    final arguments = StringBuffer();
    while (end < code.length && depth > 0) {
      final character = code[end++];
      if ('([{'.contains(character)) depth++;
      if (')]}'.contains(character)) depth--;
      arguments.write(depth == 1 ? character : ' ');
    }
    for (final argument in RegExp(
      r'\b(backgroundColor|borderColor|interactiveBackgroundColor|borderRadius|padding)\s*:',
    ).allMatches(arguments.toString())) {
      final name = argument[1]!;
      result.update(name, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  return result;
}
