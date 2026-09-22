import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final embedExamples = ComponentExamples(
  description: 'Embedded web content with loading, retry and a browser link.',
  status: ComponentStatus.implemented,
  notes:
      'These examples use self-contained HTML and make no network requests. '
      'The embedded provider owns its content and appearance; Native owns the '
      'card, loading indicator and controls. Trusted resize messages adjust the '
      'viewport between 120 and 2000 pixels. Unsupported platforms keep the '
      'browser action. The application validates remote provider URLs.',
  examples: [
    StyleguideExample(
      title: 'Embedded content',
      description:
          'The offline frame resizes after loading. Its link reports a local '
          'action instead of leaving the styleguide.',
      code: '''DEmbed(
  uri: embedUri,
  origins: {'https://embed.example.com'},
  title: 'Embedded post',
  externalUri: originalUri,
  height: 300,
  resizeMessageType: 'resize.embed',
  onOpenLink: openLink,
)''',
      builder: (_) => const _EmbedExample(),
    ),
    StyleguideExample(
      title: 'Unavailable embed',
      description:
          'An invalid embed URL never creates a web view; the original link '
          'remains accessible.',
      code: 'DEmbed(uri: invalidUri, ...)',
      builder: (_) => const _EmbedExample(unavailable: true),
    ),
  ],
);

class _EmbedExample extends StatefulWidget {
  const _EmbedExample({this.unavailable = false});
  final bool unavailable;

  @override
  State<_EmbedExample> createState() => _EmbedExampleState();
}

class _EmbedExampleState extends State<_EmbedExample> {
  String? _opened;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DEmbed(
        uri: widget.unavailable
            ? Uri.parse('about:blank')
            : Uri.dataFromString(
                _sample,
                mimeType: 'text/html',
                encoding: utf8,
              ),
        origins: const {'null'},
        title: 'Embedded post',
        externalUri: Uri.https('example.com', '/post'),
        height: 300,
        resizeMessageType: 'resize.embed',
        onOpenLink: (uri) => setState(() => _opened = uri.toString()),
      ),
      if (_opened != null) Text('Opened $_opened'),
    ],
  );
}

const _sample = '''<!doctype html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body { margin:0; padding:20px; font:16px/1.5 system-ui; color:#222; background:#f5f5f5; }
h2 { font-size:18px; margin:0 0 12px; }
a { color:#175cd3; }
</style></head><body><h2>A self-contained embed</h2>
<p>External content keeps its own typography inside the Native card.</p>
<a href="https://example.com/post">Read the post</a>
<script>
const resize = () => parent.postMessage(
  {type:'resize.embed',data:Math.ceil(document.body.getBoundingClientRect().height)}, '*');
window.addEventListener('load', resize);
new ResizeObserver(resize).observe(document.body);
</script></body></html>''';
