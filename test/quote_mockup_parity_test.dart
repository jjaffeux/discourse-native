import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/src/shell/composer_quotes.dart';
import 'package:discourse_native/src/shell/quote.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureKey = ValueKey('quote-parity-capture');
const _body =
    'The first paragraph stays with its attribution.\n\n'
    'A second paragraph wraps within the same quote box.';
const _source =
    '[quote="A long source attribution, post:1, topic:2, username:reader"]\n'
    '$_body\n[/quote]';

void main() {
  setUpAll(() async {
    for (final (family, path) in [
      ('Lato', 'assets/fonts/Lato-Regular.ttf'),
      ('Open Sans', 'assets/fonts/OpenSans.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      for (final width in [320.0, 640.0]) {
        final name =
            '${dark ? 'dark' : 'light'}-${width.toInt()}-${scale.toInt()}x';
        testWidgets('post and composer quotes remain readable at $name', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(Size(width + 32, 2600));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final baseTheme = dark ? AppTheme.dark : AppTheme.light;
          final theme = baseTheme.copyWith(
            textTheme: baseTheme.textTheme.apply(fontFamily: 'Lato'),
          );
          final block = parseComposerQuotes(_source).single;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: RepaintBoundary(
                      key: _captureKey,
                      child: ColoredBox(
                        color: theme.scaffoldBackgroundColor,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                            width: width,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text('Post quote'),
                                const QuoteBlock(
                                  data: QuoteData(
                                    username: null,
                                    avatarUrl: null,
                                    title: 'A long source attribution',
                                    link: null,
                                    bodyHtml:
                                        '<p>The first paragraph stays with its attribution.</p>'
                                        '<p>A second paragraph wraps within the same quote box.</p>',
                                  ),
                                ),
                                const SizedBox(height: 20),
                                const Text('Composer quote'),
                                ComposerQuotePreview(
                                  block: block,
                                  onRemove: () {},
                                  contents: block.contents,
                                  baseStyle: theme.textTheme.bodyLarge!,
                                ),
                                const SizedBox(height: 20),
                                const Text('Unattributed composer quote'),
                                ComposerQuotePreview(
                                  block: parseComposerQuotes(
                                    '[quote]\nShort quoted text.\n[/quote]',
                                  ).single,
                                  contents: 'Short quoted text.',
                                  onRemove: () {},
                                  baseStyle: theme.textTheme.bodyLarge!,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text(_body), findsOneWidget);
          expect(find.text('Short quoted text.'), findsOneWidget);
          await _capture(tester, name);
        });
      }
    }
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['QUOTE_PARITY_RENDER_DIR'];
  if (output == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
