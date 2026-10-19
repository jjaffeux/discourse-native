import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/progressive_html_mode.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('one giant styled paragraph keeps all selectable text', (
    tester,
  ) async {
    const output = String.fromEnvironment('GIANT_RENDER_OUTPUT');
    if (output.isNotEmpty) {
      await tester.runAsync(() async {
        final font = File('/System/Library/Fonts/SFNS.ttf').readAsBytesSync();
        for (final family in [
          '.AppleSystemUIFont',
          'Roboto',
          'SF Pro Text',
          'SF Pro Display',
        ]) {
          await (FontLoader(
            family,
          )..addFont(Future.value(ByteData.sublistView(font)))).load();
        }
      });
    }
    const count = 1024;
    final html =
        '<p>${List.generate(count, (i) => '<b>B$i </b><i>I$i </i>').join()}</p>';
    final expected = List.generate(count, (i) => 'B$i I$i').join(' ');
    String? selected;
    final capture = GlobalKey();
    for (final dark in [false, true]) {
      await tester.pumpWidget(const SizedBox.shrink());
      selected = null;
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: DPageSurface(
            child: RepaintBoundary(
              key: capture,
              child: SizedBox(
                width: 500,
                height: 600,
                child: SelectionArea(
                  onSelectionChanged: (content) =>
                      selected = content?.plainText,
                  child: SingleChildScrollView(
                    child: CookedHtml(
                      html: html,
                      buildAsync: false,
                      renderMode: const ProgressiveHtmlMode(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final text = tester.widget<RichText>(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText().startsWith('B0'),
        ),
      );
      expect(text.text.toPlainText().trimRight(), expected);
      if (output.isNotEmpty) {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File(
            '$output/${dark ? 'dark' : 'light'}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      tester
          .state<SelectionAreaState>(find.byType(SelectionArea))
          .selectableRegion
          .selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
      expect(selected?.trimRight(), expected);
      expect(tester.takeException(), isNull);
    }
  });
}
