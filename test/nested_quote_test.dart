import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/quote.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _before = 'Half of this is a recommendation and half is a warning.';
const _inside =
    'Results hold up across three runs, while the final timings still vary.';
const _after = 'That distinction matters when comparing the results.';
const _captureKey = ValueKey('nested-quote-capture');

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Lato',
    )..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))).load();
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      for (final direction in TextDirection.values) {
        final name =
            '${dark ? 'dark' : 'light'}-${scale.toInt()}x-${direction.name}';
        testWidgets('nested quotes retain compact reading space at $name', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(const Size(392, 2000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final baseTheme = dark ? AppTheme.dark : AppTheme.light;
          final theme = baseTheme.copyWith(
            textTheme: baseTheme.textTheme.apply(fontFamily: 'Lato'),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Directionality(
                textDirection: direction,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: RepaintBoundary(
                        key: _captureKey,
                        child: ColoredBox(
                          color: theme.scaffoldBackgroundColor,
                          child: const Padding(
                            padding: EdgeInsets.all(16),
                            child: SizedBox(
                              width: 360,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text('Worth separating two things here.'),
                                  QuoteBlock(
                                    data: QuoteData(
                                      username: null,
                                      avatarUrl: null,
                                      title: 'aoife.brennan',
                                      link: null,
                                      bodyHtml:
                                          '<p>$_before</p>'
                                          '<aside class="quote" data-username="sam">'
                                          '<div class="title">sam:</div>'
                                          '<blockquote><p>$_inside</p></blockquote>'
                                          '</aside><p>$_after</p>',
                                    ),
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
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final before = tester.getRect(find.text(_before, findRichText: true));
          final inside = tester.getRect(find.text(_inside, findRichText: true));
          final after = tester.getRect(find.text(_after, findRichText: true));
          final nested = tester.getRect(find.byType(DQuote).last);
          final indent = direction == TextDirection.ltr
              ? inside.left - before.left
              : before.right - inside.right;
          expect(indent, closeTo(12, .1));
          expect(nested.top - before.bottom, inInclusiveRange(0, 16 * scale));
          expect(after.top - nested.bottom, inInclusiveRange(0, 16 * scale));
          await _capture(tester, name);
        });
      }
    }
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['NESTED_QUOTE_RENDER_DIR'];
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
