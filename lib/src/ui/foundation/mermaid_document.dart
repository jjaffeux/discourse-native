import 'dart:convert';

/// Offline document used only to render a diagram, never to browse a forum.
String mermaidDocument({
  required String runtime,
  required String renderer,
  required String source,
  required bool dark,
}) {
  // Author text must remain a JSON value, including literal HTML end tags.
  final options = jsonEncode({'source': source, 'dark': dark})
      .replaceAll('<', r'\u003c')
      .replaceAll('\u2028', r'\u2028')
      .replaceAll('\u2029', r'\u2029');
  String script(String value) =>
      value.replaceAll(RegExp('</script', caseSensitive: false), r'<\/script');
  return '''<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-native-mermaid'; style-src 'unsafe-inline'; img-src data: blob:; base-uri 'none'; form-action 'none'">
<style>html,body{margin:0;overflow:hidden}#diagram{width:1200px}*{animation:none!important;transition:none!important}</style>
</head><body><div id="diagram"></div>
<script nonce="native-mermaid">${script(runtime)}</script>
<script nonce="native-mermaid">${script(renderer)}</script>
<script nonce="native-mermaid">renderNativeMermaid($options);</script>
</body></html>''';
}
