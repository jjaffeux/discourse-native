import 'dart:convert';

String graphvizDocument(
  List<String> assets,
  String source,
  String? engine,
  bool dark,
) {
  // JSON strings are values, including literal HTML end tags in author text.
  String encode(Object value) => jsonEncode(value)
      .replaceAll('<', r'\u003c')
      .replaceAll('\u2028', r'\u2028')
      .replaceAll('\u2029', r'\u2029');
  final runtime = encode(assets[0]);
  final options = encode({'source': source, 'engine': engine ?? 'dot'});
  final renderer = assets[1].replaceAll(
    RegExp('</script', caseSensitive: false),
    r'<\/script',
  );
  return '''<!doctype html>
<html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-native-graphviz' 'wasm-unsafe-eval'; worker-src blob:; img-src blob:; base-uri 'none'; form-action 'none'">
</head><body>
<script nonce="native-graphviz">$renderer</script>
<script nonce="native-graphviz">renderNativeGraphviz($runtime, $options);</script>
</body></html>''';
}
