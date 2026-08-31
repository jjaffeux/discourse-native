import 'dart:convert';
import 'dart:typed_data';

import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:discourse_native/src/shell/markdown_highlight.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/media_pipeline.dart';

void main() {
  testWidgets('span cache follows same-brightness theme changes', (
    tester,
  ) async {
    final controller = MarkdownEditingController(
      text: '[label](https://example.com)',
    );
    controller.selection = const TextSelection.collapsed(offset: 2);
    addTearDown(controller.dispose);

    var theme = _themeWithPrimary(Colors.red);
    late BuildContext themedContext;
    late StateSetter rebuild;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return MaterialApp(
            theme: theme,
            themeAnimationDuration: Duration.zero,
            home: Builder(
              builder: (context) {
                themedContext = context;
                return const SizedBox();
              },
            ),
          );
        },
      ),
    );

    const base = TextStyle(fontSize: 14);
    TextSpan build() => controller.buildTextSpan(
      context: themedContext,
      style: base,
      withComposing: false,
    );

    expect(_textStyle(build(), 'label').color, Colors.red);

    rebuild(() => theme = _themeWithPrimary(Colors.green));
    await tester.pump();

    expect(_textStyle(build(), 'label').color, Colors.green);
  });

  testWidgets('transient emoji failures retry after the cache cooldown', (
    tester,
  ) async {
    var attempts = 0;
    installTestMediaPipeline(
      rateLimitCooldown: Duration.zero,
      client: MockClient((request) async {
        attempts++;
        return attempts == 1
            ? http.Response('temporarily unavailable', 500)
            : http.Response.bytes(_pngBytes, 200);
      }),
    );

    final controller = MarkdownEditingController(
      text: 'try :smile: again',
      resolveEmoji: (name) => 'https://example.com/$name.png',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: TextField(controller: controller)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byType(EmojiImage), findsOneWidget);
  });

  group('fenced blocks', () {
    test('a shorter delimiter does not close a longer fence', () {
      const source = '````dart\none\n```\ntwo\n````\nafter';
      final shortFence = source.indexOf('\n```\n') + 1;
      final matchingFence = source.lastIndexOf('````');

      expect(_runAt(source, shortFence).has(Md.codeBlock), isTrue);
      expect(_runAt(source, shortFence).has(Md.marker), isFalse);
      expect(_runAt(source, source.indexOf('two')).has(Md.codeBlock), isTrue);
      expect(_runAt(source, matchingFence).has(Md.marker), isTrue);
      expect(
        _runAt(source, source.indexOf('after')).has(Md.codeBlock),
        isFalse,
      );
    });

    test('a different delimiter does not close a fence', () {
      const source = '```dart\none\n~~~\ntwo\n```\nafter';
      final tildeFence = source.indexOf('~~~');
      final backtickFence = source.lastIndexOf('```');

      expect(_runAt(source, tildeFence).has(Md.codeBlock), isTrue);
      expect(_runAt(source, tildeFence).has(Md.marker), isFalse);
      expect(_runAt(source, source.indexOf('two')).has(Md.codeBlock), isTrue);
      expect(_runAt(source, backtickFence).has(Md.marker), isTrue);
      expect(
        _runAt(source, source.indexOf('after')).has(Md.codeBlock),
        isFalse,
      );
    });
  });
}

ThemeData _themeWithPrimary(Color primary) {
  final base = AppTheme.light;
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(primary: primary),
  );
}

TextStyle _textStyle(TextSpan root, String text) => root.children!
    .whereType<TextSpan>()
    .firstWhere((span) => span.text == text)
    .style!;

MarkdownRun _runAt(String source, int offset) =>
    scanMarkdown(source)
        .firstWhere((run) => run.start <= offset && offset < run.end);

final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
