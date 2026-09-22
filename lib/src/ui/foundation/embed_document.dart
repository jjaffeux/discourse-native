import 'dart:convert';

/// A minimal host for an iframe; only its own trusted messages reach Flutter.
String embedDocument({
  required Uri uri,
  required String title,
  required Set<String> origins,
  required String? resizeMessageType,
}) {
  const escape = HtmlEscape();
  // JSON embedded in a script must not be able to terminate that script.
  String scriptValue(Object? value) =>
      jsonEncode(value).replaceAll('<', r'\u003c');

  return '''<!doctype html>
<html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
html,body { margin:0; width:100%; height:100%; overflow:hidden; }
iframe { display:block; width:100%; height:100%; border:0; }
</style></head><body>
<iframe id="embed" title="${escape.convert(title)}" allowfullscreen></iframe>
<script>
const frame = document.getElementById('embed');
const origins = ${scriptValue(origins.toList())};
const resizeType = ${scriptValue(resizeMessageType)};
frame.addEventListener('load', () => NativeEmbed.postMessage('loaded'));
window.addEventListener('message', (event) => {
  if (event.source !== frame.contentWindow || !origins.includes(event.origin)) return;
  let message = event.data;
  if (typeof message === 'string') {
    try { message = JSON.parse(message); } catch { return; }
  }
  if (!resizeType || message?.type !== resizeType) return;
  const height = Number(message.data);
  if (Number.isFinite(height) && height > 0) {
    NativeEmbed.postMessage(JSON.stringify({height}));
  }
});
frame.src = ${scriptValue(uri.toString())};
</script></body></html>''';
}
