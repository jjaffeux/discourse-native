import 'dart:ui' as ui;

import 'package:discourse_native/src/shell/composer_blockquote.dart';
import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _boundaryKey = ValueKey('quote-decoration-capture');
const _plainBackground = Color(0xFF112233);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('JetBrains Mono')
      ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'));
    await font.load();
  });
  late MarkdownEditingController controller;
  late ScrollController scroll;
  late ComposerBlockquoteInputFormatter formatter;

  setUp(() {
    controller = MarkdownEditingController();
    scroll = ScrollController();
    formatter = ComposerBlockquoteInputFormatter();
  });
  tearDown(() {
    controller.dispose();
    scroll.dispose();
  });

  Future<void> pumpEditor(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: _boundaryKey,
            child: ColoredBox(
              color: _plainBackground,
              child: SizedBox(
                width: 280,
                height: 240,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: ComposerBlockquoteDecoration.gutter,
                  ),
                  child: ComposerBlockquoteDecoration(
                    repaint: Listenable.merge([controller, scroll]),
                    child: TextField(
                      controller: controller,
                      scrollController: scroll,
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 18,
                        height: 1.5,
                      ),
                      decoration: null,
                      expands: true,
                      maxLines: null,
                      strutStyle: const StrutStyle(forceStrutHeight: false),
                      inputFormatters: [formatter],
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

  RenderEditable editable(WidgetTester tester) =>
      tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;

  testWidgets('leaving a quote restores the normal left edge', (tester) async {
    await pumpEditor(tester);
    final field = find.byType(TextField);
    final editorLeft = tester
        .getTopLeft(find.byType(ComposerBlockquoteDecoration))
        .dx;

    double caretLeft() {
      final render = editable(tester);
      final caret = render.getLocalRectForCaret(
        TextPosition(offset: controller.selection.extentOffset),
      );
      return render.localToGlobal(caret.topLeft).dx;
    }

    await tester.enterText(field, '');
    await tester.pump();
    final normalLeft = caretLeft();
    expect(normalLeft, closeTo(editorLeft, 1));

    await tester.enterText(field, '> quote');
    await tester.pump();
    await tester.enterText(field, '> quote\n');
    await tester.pump();
    expect(controller.text, '> quote\n> ');

    await tester.enterText(field, '> quote\n> \n');
    await tester.pump();
    expect(controller.text, '> quote\n');
    expect(caretLeft(), closeTo(normalLeft, 0.01));
    expect(caretLeft(), closeTo(editorLeft, 1));

    await tester.enterText(field, '> quote\nNormal');
    controller.selection = const TextSelection.collapsed(
      offset: '> quote\n'.length,
    );
    await tester.pump();
    expect(caretLeft(), closeTo(editorLeft, 1));
  });

  testWidgets('quote background contains typed text and every wrapped line', (
    tester,
  ) async {
    await pumpEditor(tester);
    for (final source in [
      '> ',
      '> testdazdzada',
      '> ${'quoted text ' * 5}\n> continued',
    ]) {
      await tester.enterText(find.byType(TextField), source);
      await tester.pump();
      final capture = await _capture(tester);
      final render = editable(tester);
      final boxes = render.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: source.length),
      );
      for (final box in boxes.where((box) => box.bottom > box.top)) {
        final y = capture.boundary
            .globalToLocal(render.localToGlobal(box.toRect().center))
            .dy
            .floor();
        expect(
          capture.colorAt(274, y),
          AppTheme.dark.shell.panel,
          reason:
              'The quote background must reach past the text on every line.',
        );
        expect(
          capture.colorAt(1, y),
          AppTheme.dark.colorScheme.primary,
          reason: 'The quote bar must span wrapped lines too.',
        );
      }
      expect(controller.text, source);
      expect(render.plainText.length, source.length);
    }

    const after = '> quote\nNormal text';
    await tester.enterText(find.byType(TextField), after);
    await tester.pump();
    final capture = await _capture(tester);
    final render = editable(tester);
    final caret = render.getLocalRectForCaret(
      const TextPosition(offset: after.length),
    );
    final y = capture.boundary
        .globalToLocal(render.localToGlobal(caret.center))
        .dy
        .floor();
    expect(capture.colorAt(274, y), _plainBackground);
    expect(capture.colorAt(1, y), _plainBackground);
  });

  testWidgets(
    'quote decoration follows scrolling and disappears with its prefix',
    (tester) async {
      await pumpEditor(tester);
      final source = '${'normal\n' * 15}> quote';
      await tester.enterText(find.byType(TextField), source);
      await tester.pumpAndSettle();
      scroll.jumpTo(0);
      await tester.pump();
      var capture = await _capture(tester);
      expect(capture.colorAt(1, 10), _plainBackground);

      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      capture = await _capture(tester);
      final render = editable(tester);
      final caret = render.getLocalRectForCaret(
        TextPosition(offset: source.length),
      );
      final y = capture.boundary
          .globalToLocal(render.localToGlobal(caret.center))
          .dy
          .floor();
      expect(capture.colorAt(274, y), AppTheme.dark.shell.panel);
      expect(capture.colorAt(1, y), AppTheme.dark.colorScheme.primary);

      await tester.enterText(find.byType(TextField), 'normal');
      await tester.pumpAndSettle();
      capture = await _capture(tester);
      expect(capture.colorAt(1, 10), _plainBackground);
      expect(capture.colorAt(274, 10), _plainBackground);
    },
  );
}

Future<_Capture> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      return _Capture(
        boundary,
        image.width,
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
      );
    } finally {
      image.dispose();
    }
  }))!;
}

class _Capture {
  const _Capture(this.boundary, this.width, this.bytes);

  final RenderRepaintBoundary boundary;
  final int width;
  final ByteData bytes;

  Color colorAt(int x, int y) {
    final offset = (y * width + x) * 4;
    return Color.fromARGB(
      bytes.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
  }
}
