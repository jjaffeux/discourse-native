class ComposerDocumentBodyRange {
  const ComposerDocumentBodyRange({
    required this.start,
    required this.source,
    required this.bodyStart,
    required this.bodyEnd,
    this.serialize,
  });
  final int start;
  final String source;
  final int bodyStart;
  final int bodyEnd;
  final String Function(String body, {bool multiline})? serialize;
  int get end => start + source.length;
  String get body => source.substring(bodyStart, bodyEnd);
  String withBody(String value, {bool multiline = false}) {
    if (serialize case final render?) {
      return render(value, multiline: multiline);
    }
    final newline = source.contains('\r\n') ? '\r\n' : '\n';
    return source.replaceRange(
      bodyStart,
      bodyEnd,
      value.replaceAll(RegExp(r'\r\n?|\n'), newline),
    );
  }

  ComposerDocumentBodyRange replaced(String next) => ComposerDocumentBodyRange(
    start: start,
    source: next,
    bodyStart: bodyStart,
    bodyEnd: next.length - (source.length - bodyEnd),
  );
}
