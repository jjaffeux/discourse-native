import 'dart:math';

import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugins/chat/chat_preview.dart';
import 'package:discourse_native/src/plugins/chat/chat_preview_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = SiteConfig.unknown();
  final engine = ChatPreviewEngine();

  ChatPreviewResult project(
    String raw, {
    ChatPreviewEngine? withEngine,
    TrustedPreviewSeed? seed,
  }) => (withEngine ?? engine).project(
    ChatPreviewRequest(raw: raw, siteConfig: config, trustedSeed: seed),
  );

  group('safe chat dialect', () {
    test(
      'projects plain text and line breaks with complete source accounting',
      () {
        final result = project('hello 👋\nworld') as ProjectedPreview;

        expect(_visibleText(result.document), 'hello 👋\nworld');
        _expectFullyAccounted(result.document);
        expect(
          result.document.nodes.whereType<ChatPreviewLineBreak>(),
          hasLength(1),
        );
      },
    );

    test('accounts for a CRLF as one line-break node', () {
      final result = project('hello\r\nworld') as ProjectedPreview;

      expect(_visibleText(result.document), 'hello\nworld');
      expect(
        result.document.nodes.whereType<ChatPreviewLineBreak>().single.range,
        const SourceRange(5, 7),
      );
      _expectFullyAccounted(result.document);
    });

    test('projects nested bold, italic, and strikethrough', () {
      final result =
          project('***both*** and **bold _italic_** then ~~gone~~')
              as ProjectedPreview;

      expect(_visibleText(result.document), 'both and bold italic then gone');
      _expectFullyAccounted(result.document);

      final both = _textNode(result.document, 'both');
      expect(both.styles, {
        ChatPreviewTextStyle.bold,
        ChatPreviewTextStyle.italic,
      });
      expect(_textNode(result.document, 'bold ').styles, {
        ChatPreviewTextStyle.bold,
      });
      expect(_textNode(result.document, 'italic').styles, {
        ChatPreviewTextStyle.bold,
        ChatPreviewTextStyle.italic,
      });
      expect(_textNode(result.document, 'gone').styles, {
        ChatPreviewTextStyle.strikethrough,
      });
    });

    test('projects underscore spellings of bold and bold italic', () {
      final result = project('__bold__ and ___both___') as ProjectedPreview;

      expect(_visibleText(result.document), 'bold and both');
      expect(_textNode(result.document, 'bold').styles, {
        ChatPreviewTextStyle.bold,
      });
      expect(_textNode(result.document, 'both').styles, {
        ChatPreviewTextStyle.bold,
        ChatPreviewTextStyle.italic,
      });
      _expectFullyAccounted(result.document);
    });

    test('projects inline code without interpreting its contents', () {
      final result =
          project(r'Use `**raw** @sam :wave: <b>x</b>` now')
              as ProjectedPreview;

      expect(
        _visibleText(result.document),
        'Use **raw** @sam :wave: <b>x</b> now',
      );
      expect(
        _textNode(result.document, '**raw** @sam :wave: <b>x</b>').styles,
        {ChatPreviewTextStyle.code},
      );
      _expectFullyAccounted(result.document);
    });

    test('projects a closed fenced block as one typed node', () {
      const raw = 'before\n```dart\nfinal x = "@sam";\n```\nafter';
      final result = project(raw) as ProjectedPreview;
      final block =
          result.document.nodes.singleWhere(
                (node) => node is ChatPreviewCodeBlock,
              )
              as ChatPreviewCodeBlock;

      expect(block.code, 'final x = "@sam";\n');
      expect(block.language, 'dart');
      expect(
        raw.substring(block.range.start, block.range.end),
        contains('```'),
      );
      _expectFullyAccounted(result.document);
    });

    test('leaves unmatched Markdown punctuation visible as literal text', () {
      const raw = 'a * b **open ~~ spaced ~~ and `';
      final result = project(raw) as ProjectedPreview;

      expect(_visibleText(result.document), raw);
      expect(result.document.nodes.whereType<ChatPreviewSyntax>(), isEmpty);
      _expectFullyAccounted(result.document);
    });

    test('treats an unclosed code fence as ambiguous', () {
      final result = project('```dart\ncode') as SourceFallback;

      expect(result.reason, ChatPreviewFallbackReason.ambiguousSyntax);
      expect(result.raw, '```dart\ncode');
    });
  });

  group('whole-source fallback', () {
    final unsupported = <String>[
      '[label](https://example.com)',
      '![alt](https://example.com/a.png)',
      'https://example.com',
      '- item',
      '1. item',
      '> quote',
      '# heading',
      '| a | b |\n| --- | --- |',
      '<strong>html</strong>',
      '[wrap]bbcode[/wrap]',
      r'\*escaped marker*',
      '/shrug hello',
      '@someone hello',
      '#category hello',
      ':wave: hello',
      ':CUSTOM: hello',
      '{{server-widget}}',
      '    indented code',
      '\tindented code',
      '&copy; and &#169;',
      'wait...',
      '(tm) and a -- b',
      'person@example.com',
    ];

    for (final raw in unsupported) {
      test('falls back without rewriting ${raw.replaceAll('\n', r'\n')}', () {
        final result = project(raw) as SourceFallback;

        expect(result.reason, ChatPreviewFallbackReason.unsupportedSyntax);
        expect(result.raw, raw);
      });
    }

    test('does not reject unsupported-looking source inside fenced code', () {
      const raw =
          '```\n    indented\n- item\n@someone :wave: <tag>\n&copy; wait...\n```';
      final result = project(raw);

      expect(result, isA<ProjectedPreview>());
    });
  });

  group('plugin inspection boundary', () {
    test('inserts a valid claim and keeps all source accounted for', () {
      const raw = 'Meet **[date=tomorrow]**.';
      final plugin = _ClaimingPlugin('[date=tomorrow]');
      final result =
          project(raw, withEngine: ChatPreviewEngine(plugins: [plugin]))
              as ProjectedPreview;
      final node = result.document.nodes.whereType<PluginPreviewNode>().single;

      expect(node.featureId, 'test-date');
      expect(node.fallbackText, '[date=tomorrow]');
      expect(node.styles, {ChatPreviewTextStyle.bold});
      _expectFullyAccounted(result.document);
    });

    test('rebuilds an engine with active registry adapters', () {
      final rebuilt = engine.withPlugins([_ClaimingPlugin('[date=tomorrow]')]);

      expect(
        project('[date=tomorrow]', withEngine: rebuilt),
        isA<ProjectedPreview>(),
      );
    });

    test('a blocker forces raw fallback', () {
      final result =
          project(
                '[date=tomorrow]',
                withEngine: ChatPreviewEngine(plugins: [_BlockingPlugin()]),
              )
              as SourceFallback;

      expect(result.reason, ChatPreviewFallbackReason.pluginBlocked);
    });

    test('duplicate feature ids force raw fallback', () {
      final result =
          project(
                'plain',
                withEngine: ChatPreviewEngine(
                  plugins: [_EmptyPlugin('same'), _EmptyPlugin('same')],
                ),
              )
              as SourceFallback;

      expect(result.reason, ChatPreviewFallbackReason.duplicatePluginId);
    });

    test('overlapping claims force raw fallback', () {
      final result =
          project(
                'abcdef',
                withEngine: ChatPreviewEngine(
                  plugins: [
                    _RangePlugin('one', const SourceRange(0, 4)),
                    _RangePlugin('two', const SourceRange(3, 6)),
                  ],
                ),
              )
              as SourceFallback;

      expect(result.reason, ChatPreviewFallbackReason.overlappingPluginClaims);
    });

    test('invalid claims and adapter exceptions never escape', () {
      final invalid =
          project(
                'abc',
                withEngine: ChatPreviewEngine(
                  plugins: [_RangePlugin('bad', const SourceRange(0, 20))],
                ),
              )
              as SourceFallback;
      final throwing =
          project(
                'abc',
                withEngine: ChatPreviewEngine(plugins: [_ThrowingPlugin()]),
              )
              as SourceFallback;
      final rewrittenFallback =
          project(
                'abc',
                withEngine: ChatPreviewEngine(
                  plugins: [
                    _RangePlugin(
                      'rewritten',
                      const SourceRange(0, 3),
                      fallbackText: 'different',
                    ),
                  ],
                ),
              )
              as SourceFallback;

      expect(invalid.reason, ChatPreviewFallbackReason.invalidPluginClaim);
      expect(throwing.reason, ChatPreviewFallbackReason.pluginFailure);
      expect(
        rewrittenFallback.reason,
        ChatPreviewFallbackReason.invalidPluginClaim,
      );
    });
  });

  group('Chat-owned contribution rendering', () {
    testWidgets('renders the contribution which projected an opaque node', (
      tester,
    ) async {
      const plugin = _RenderingPlugin('date', '[date]');
      final renderer = ChatPreviewEngine(plugins: const [plugin]);
      final projected =
          project('[date]', withEngine: renderer) as ProjectedPreview;
      final node = projected.document.nodes
          .whereType<PluginPreviewNode>()
          .single;
      Widget? built;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              built = renderer.buildPreviewNode(context, node);
              return built!;
            },
          ),
        ),
      );

      expect((built as Text).data, 'date');
    });

    testWidgets(
      'a broken contribution renderer logs and falls back the whole source',
      (tester) async {
        final diagnostics = await _installDiagnostics('chat-preview-plugin');
        const raw = '**before** [date] after';
        final renderer = ChatPreviewEngine(
          plugins: const [
            _RenderingPlugin('date', '[date]', throwsWhileBuilding: true),
          ],
        );
        final projected =
            project(raw, withEngine: renderer) as ProjectedPreview;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChatPreviewBody(
                document: projected.document,
                textStyle: null,
                previewEngine: renderer,
              ),
            ),
          ),
        );

        expect(find.text(raw), findsOneWidget);
        expect(find.text('before'), findsNothing);
        expect(
          diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
          isA<ErrorDiagnosticEvent>()
              .having(
                (event) => event.operation,
                'operation',
                'chat.previewPlugin.render',
              )
              .having((event) => event.source, 'source', 'chat')
              .having(
                (event) => event.severity,
                'severity',
                DiagnosticSeverity.warning,
              )
              .having((event) => event.handled, 'handled', isTrue)
              .having((event) => event.degraded, 'degraded', isTrue),
        );
        await diagnostics.close();
      },
    );
  });

  group('trusted GIF seed', () {
    test('bypasses image-Markdown fallback with a typed image node', () {
      const raw = '![party](https://media.example/party.gif)';
      final result =
          project(
                raw,
                seed: TrustedGifPreviewSeed(
                  url: Uri.parse('https://media.example/party.gif'),
                  title: 'party',
                  width: 320,
                  height: 180,
                ),
              )
              as ProjectedPreview;
      final image = result.document.nodes.single as ChatPreviewImage;

      expect(image.url.toString(), 'https://media.example/party.gif');
      expect(image.title, 'party');
      expect(image.fallbackText, raw);
      expect(image.range, const SourceRange(0, raw.length));
    });

    test('rejects an invalid trusted seed without throwing', () {
      final result =
          project(
                '![x](javascript:alert(1))',
                seed: TrustedGifPreviewSeed(
                  url: Uri.parse('javascript:alert(1)'),
                  title: 'x',
                  width: 10,
                  height: 10,
                ),
              )
              as SourceFallback;

      expect(result.reason, ChatPreviewFallbackReason.invalidTrustedSeed);
    });

    test('the same image Markdown without a seed stays raw', () {
      expect(
        project('![party](https://media.example/party.gif)'),
        isA<SourceFallback>(),
      );
    });
  });

  test('resource limits produce raw fallback', () {
    final result =
        project('four', withEngine: ChatPreviewEngine(maxSourceLength: 3))
            as SourceFallback;

    expect(result.reason, ChatPreviewFallbackReason.resourceLimit);
    expect(result.raw, 'four');
  });

  test(
    'deterministic hostile-source sweep never throws or loses raw fallback',
    () {
      final random = Random(7319);
      const alphabet = 'abc XYZ012\n*_~`[]()<>/@#:\\\u{1f44b}\u{0301}|{}+-';

      for (var sample = 0; sample < 1000; sample++) {
        final length = random.nextInt(120);
        final raw = String.fromCharCodes([
          for (var index = 0; index < length; index++)
            alphabet.codeUnitAt(random.nextInt(alphabet.length)),
        ]);
        final result = project(raw);
        switch (result) {
          case ProjectedPreview(:final document):
            expect(document.source, raw);
            _expectFullyAccounted(document);
          case SourceFallback(raw: final fallbackRaw):
            expect(fallbackRaw, raw);
        }
      }
    },
  );
}

String _visibleText(PreviewDocument document) {
  final buffer = StringBuffer();
  for (final node in document.nodes) {
    switch (node) {
      case ChatPreviewText(:final text):
        buffer.write(text);
      case ChatPreviewLineBreak():
        buffer.write('\n');
      case ChatPreviewCodeBlock(:final code):
        buffer.write(code);
      case PluginPreviewNode(:final fallbackText):
        buffer.write(fallbackText);
      case ChatPreviewImage(:final fallbackText):
        buffer.write(fallbackText);
      case ChatPreviewSyntax():
        break;
    }
  }
  return buffer.toString();
}

ChatPreviewText _textNode(PreviewDocument document, String text) => document
    .nodes
    .whereType<ChatPreviewText>()
    .singleWhere((node) => node.text == text);

void _expectFullyAccounted(PreviewDocument document) {
  var offset = 0;
  for (final node in document.nodes) {
    expect(node.range.start, offset);
    expect(node.range.end, greaterThan(offset));
    offset = node.range.end;
  }
  expect(offset, document.source.length);
}

final class _ClaimingPlugin implements ChatPreviewPluginAdapter {
  _ClaimingPlugin(this.markup);

  final String markup;

  @override
  String get previewFeatureId => 'test-date';

  @override
  ChatPreviewInspection inspect(ChatPreviewRequest request) {
    final start = request.raw.indexOf(markup);
    if (start == -1) return ChatPreviewInspection();
    final range = SourceRange(start, start + markup.length);
    return ChatPreviewInspection(
      claims: [
        ChatPreviewClaim(
          range: range,
          node: PluginPreviewNode(
            range: range,
            featureId: previewFeatureId,
            kind: 'date',
            fallbackText: markup,
          ),
        ),
      ],
    );
  }
}

final class _BlockingPlugin implements ChatPreviewPluginAdapter {
  @override
  String get previewFeatureId => 'blocked-date';

  @override
  ChatPreviewInspection inspect(ChatPreviewRequest request) =>
      ChatPreviewInspection(blockers: const [ChatPreviewBlocker('disabled')]);
}

final class _EmptyPlugin implements ChatPreviewPluginAdapter {
  _EmptyPlugin(this.previewFeatureId);

  @override
  final String previewFeatureId;

  @override
  ChatPreviewInspection inspect(ChatPreviewRequest request) =>
      ChatPreviewInspection();
}

final class _RangePlugin implements ChatPreviewPluginAdapter {
  _RangePlugin(this.previewFeatureId, this.range, {this.fallbackText});

  @override
  final String previewFeatureId;
  final SourceRange range;
  final String? fallbackText;

  @override
  ChatPreviewInspection inspect(ChatPreviewRequest request) {
    final exactSource = range.isValidFor(request.raw)
        ? request.raw.substring(range.start, range.end)
        : '';
    return ChatPreviewInspection(
      claims: [
        ChatPreviewClaim(
          range: range,
          node: PluginPreviewNode(
            range: range,
            featureId: previewFeatureId,
            kind: 'range',
            fallbackText: fallbackText ?? exactSource,
          ),
        ),
      ],
    );
  }
}

final class _ThrowingPlugin implements ChatPreviewPluginAdapter {
  @override
  String get previewFeatureId => 'throwing';

  @override
  ChatPreviewInspection inspect(ChatPreviewRequest request) =>
      throw StateError('plugin bug');
}

final class _RenderingPlugin implements ChatPreviewContribution {
  const _RenderingPlugin(
    this.previewFeatureId,
    this.markup, {
    this.throwsWhileBuilding = false,
  });

  @override
  final String previewFeatureId;

  final String markup;
  final bool throwsWhileBuilding;

  @override
  ChatPreviewInspection inspect(ChatPreviewRequest request) {
    final start = request.raw.indexOf(markup);
    if (start < 0) return ChatPreviewInspection();
    final range = SourceRange(start, start + markup.length);
    return ChatPreviewInspection(
      claims: [
        ChatPreviewClaim(
          range: range,
          node: PluginPreviewNode(
            range: range,
            featureId: previewFeatureId,
            kind: 'test',
            fallbackText: markup,
          ),
        ),
      ],
    );
  }

  @override
  Widget? buildPreviewNode(BuildContext context, PluginPreviewNode node) {
    if (throwsWhileBuilding) throw StateError('test renderer failed');
    return Text(previewFeatureId);
  }
}

Future<DiagnosticsController> _installDiagnostics(String sessionId) async {
  final diagnostics = await DiagnosticsController.create(
    persistence: MemoryDiagnosticsPersistence(),
    sessionId: sessionId,
  );
  final binding = DiagnosticsSink.install(diagnostics);
  addTearDown(() async {
    binding.close();
    await diagnostics.close();
  });
  return diagnostics;
}
