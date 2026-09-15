import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/ui/foundation/mermaid_document.dart';

/// Generates an offline browser check using the exact production runtime,
/// security policy and image renderer. Serve the output directory locally.
void main(List<String> args) {
  const assets = 'lib/src/ui/assets/mermaid';
  final fixtures =
      jsonDecode(
            File(
              'test/plugins/discourse_mermaid/fixtures/diagrams.json',
            ).readAsStringSync(),
          )
          as List<dynamic>;
  final cases = [
    for (final dark in [false, true])
      for (final fixture in fixtures.cast<Map<String, dynamic>>())
        {...fixture, 'dark': dark},
  ];
  final data = jsonEncode(cases).replaceAll('<', r'\u003c');
  final document = mermaidDocument(
    runtime: File('$assets/mermaid-11.15.0.min.js').readAsStringSync(),
    renderer: '''const NativeMermaid = {
  postMessage(message) { parent.postMessage(message, '*'); }
};
${File('$assets/render.js').readAsStringSync()}''',
    source: cases.first['source'] as String,
    dark: false,
  );
  final workerDocument = jsonEncode(document).replaceAll('<', r'\u003c');
  final harness =
      '''
<!doctype html><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-native-mermaid'; style-src 'unsafe-inline'; img-src data: blob:; frame-src 'self'">
<script nonce="native-mermaid">
const cases = $data;
const worker = document.createElement('iframe');
worker.style.cssText = 'position:fixed;width:1px;height:1px;border:0;opacity:0;pointer-events:none';
let next = 0;
let failures = 0;
const results = document.createElement('section');
document.documentElement.append(results);
window.addEventListener('message', (event) => {
  if (event.source !== worker.contentWindow) return;
  const value = JSON.parse(event.data);
  const test = cases[next];
  const success = value.type === test.expected && !worker.contentWindow.mermaidInjected &&
    (value.type !== 'rendered' || (value.width > 10 && value.height > 10));
  if (!success) failures++;
  const row = document.createElement('section');
  const label = document.createElement('h2');
  label.textContent = (success ? 'PASS ' : 'FAIL ') + test.name + (test.dark ? ' dark' : ' light') + (value.message ? ': ' + value.message : '');
  row.append(label);
  if (value.png) {
    const image = new Image();
    image.src = 'data:image/png;base64,' + value.png;
    image.style.cssText = 'width:320px;max-height:300px;object-fit:contain;background:' + (test.dark ? '#111' : '#fff');
    row.append(image);
  }
  results.append(row);
  next++;
  if (next < cases.length) {
    setTimeout(() => worker.contentWindow.renderNativeMermaid(cases[next]), 0);
  } else {
    const summary = document.createElement('h1');
    summary.textContent = next + ' cases completed; ' + failures + ' failures';
    document.documentElement.prepend(summary);
  }
});
worker.srcdoc = $workerDocument;
document.documentElement.append(worker);
</script>
''';
  final path = args.isEmpty ? '/tmp/mermaid-check/index.html' : args.single;
  File(path).parent.createSync(recursive: true);
  File(path).writeAsStringSync(harness);
  stdout.writeln(path);
}
