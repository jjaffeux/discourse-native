import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/ui/foundation/mermaid_document.dart';

/// Generates a browser fixture using the production document and PNG adapter.
void main(List<String> args) {
  final output = Directory(args.firstOrNull ?? '/tmp/pele-check')
    ..createSync(recursive: true);
  const assets = 'lib/src/ui/assets/pele';
  final runtime = File('$assets/pele-1.10.0.global.js').readAsStringSync();
  final renderer = File('$assets/render.js').readAsStringSync();
  final fixtures =
      jsonDecode(
            File(
              'test/plugins/discourse_mermaid/fixtures/diagrams.json',
            ).readAsStringSync(),
          )
          as List;
  fixtures.addAll([
    {
      'name': 'source-limit',
      'source': 'flowchart LR\n${' ' * 50000}',
      'expected': 'error',
      'errorContains': '50000',
    },
    {
      'name': 'edge-limit-frontmatter',
      'source':
          '---\nconfig:\n  maxEdges: 99999\n---\nflowchart LR\n'
          '${List.generate(501, (i) => 'A$i --> A${i + 1}').join('\n')}',
      'expected': 'error',
      'errorContains': '500',
    },
  ]);
  final cases = <Map<String, Object?>>[];
  for (final fixture in fixtures.cast<Map<String, dynamic>>()) {
    for (final dark in [false, true]) {
      final file = 'case-${cases.length}.html';
      File('${output.path}/$file').writeAsStringSync(
        mermaidDocument(
          runtime:
              'window.NativeMermaid = {postMessage: value => '
              'parent.postMessage(value, "*")};\n$runtime',
          renderer: renderer,
          source: fixture['source'] as String,
          dark: dark,
        ),
      );
      cases.add({
        'file': file,
        'name': fixture['name'],
        'dark': dark,
        'expected': fixture['expected'],
        if (fixture['errorContains'] != null)
          'errorContains': fixture['errorContains'],
      });
    }
  }
  File('${output.path}/index.html').writeAsStringSync('''<!doctype html>
<meta charset="utf-8"><title>Native Pele renderer verification</title>
<style>
body{font:14px system-ui;margin:24px;background:#ddd}
main{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
section{padding:16px;background:white;overflow:auto}
section.dark{background:#202020;color:#eee}img{max-width:100%}
iframe{position:absolute;width:1px;height:1px;border:0}
</style><h1>Native Pele renderer verification</h1><p id="status">Running…</p>
<main></main><iframe></iframe><script>
const cases = ${jsonEncode(cases)};
window.results = [];
const frame = document.querySelector('iframe');
let timeout;
function next() {
  if (results.length === cases.length) {
    const failures = results.filter(r => !r.pass);
    document.querySelector('#status').textContent =
      results.length + ' cases, ' + failures.length + ' failures';
    window.done = true;
    frame.remove();
    return;
  }
  frame.src = cases[results.length].file;
  timeout = setTimeout(() => record({type:'timeout'}), 25000);
}
async function record(value) {
  clearTimeout(timeout);
  const fixture = cases[results.length];
  const section = document.createElement('section');
  section.className = fixture.dark ? 'dark' : '';
  const title = document.createElement('h2');
  title.textContent = fixture.name + (fixture.dark ? ' (dark)' : ' (light)');
  section.append(title);
  const result = {...fixture, type:value.type, message:value.message,
    pass: value.type === fixture.expected};
  if (fixture.errorContains) {
    result.pass &&= (value.message || '').includes(fixture.errorContains);
  }
  if (value.type === 'rendered') {
    const image = new Image();
    image.src = 'data:image/png;base64,' + value.png;
    await image.decode();
    const canvas = document.createElement('canvas');
    canvas.width = image.width; canvas.height = image.height;
    const ctx = canvas.getContext('2d'); ctx.drawImage(image,0,0);
    const pixels = ctx.getImageData(0,0,image.width,image.height).data;
    let painted = 0;
    for (let i=3;i<pixels.length;i+=4) if (pixels[i]) painted++;
    result.width = image.width; result.height = image.height;
    result.painted = painted;
    result.pass &&= painted > 0 && image.width <= 4096 &&
      image.height <= 4096 && image.width*image.height <= 4000000;
    section.append(image);
  } else {
    section.append(document.createTextNode(value.message || value.type));
  }
  document.querySelector('main').append(section);
  results.push(result);
  next();
}
window.addEventListener('message', event => {
  if (event.source === frame.contentWindow) record(JSON.parse(event.data));
});
next();
</script>''');
  stdout.writeln('${output.path}/index.html (${cases.length} cases)');
}
