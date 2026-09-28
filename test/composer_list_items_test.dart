import 'dart:async';
import 'dart:io';
import 'dart:ui' show BoxHeightStyle;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer_blocks.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_image.dart';
import 'package:discourse_native/src/shell/composer_list_editor.dart';
import 'package:discourse_native/src/shell/composer_list_source.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/composer_todos.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

const complexTask =
    '- [ ] First line\n  Continued\n\n  Second paragraph\n\n  ```text\n  [ ] literal\n  ```\n\n  - [ ] Child\n    - [x] Grandchild';

Finder editable(ComposerController composer) => find.byWidgetPredicate(
  (widget) =>
      widget is EditableText && identical(widget.controller, composer.text),
);

Future<ComposerController> pumpEditor(
  WidgetTester tester,
  String source, {
  TextStyle? textStyle,
  double scale = 1,
  double width = 350,
  TargetPlatform platform = TargetPlatform.android,
  ComposerImageUploader? imageUploader,
}) async {
  final composer = ComposerController(
    const ComposerTarget(
      siteUrl: 'https://example.test',
      topicId: 1,
      slug: 'topic',
      topicTitle: 'Topic',
    ),
    imageUploader: imageUploader,
  );
  composer.text.value = TextEditingValue(
    text: source,
    selection: TextSelection.collapsed(offset: source.length),
  );
  addTearDown(composer.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(platform: platform),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: SizedBox(
            width: width,
            height: 580,
            child: ComposerEditor(
              composer: composer,
              hintText: 'Reply',
              textStyle:
                  textStyle ?? const TextStyle(fontSize: 16, height: 1.5),
              hintStyle: null,
              showSelectionToolbar: false,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return composer;
}

List<ComposerListBodyController> bodies(WidgetTester tester) => tester
    .widgetList<ComposerRichBodyEditor>(find.byType(ComposerRichBodyEditor))
    .map((widget) => widget.composer)
    .whereType<ComposerListBodyController>()
    .toList();

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('nested todo sizes and edge taps on $platform at $scale', (
        tester,
      ) async {
        final composer = await pumpEditor(
          tester,
          '- [ ] Parent\n  - [ ] Child',
          platform: platform,
          scale: scale,
          width: 600,
        );
        final boxes = find.byType(DCheckbox);
        expect(boxes, findsNWidgets(2));
        final dimension = platform == TargetPlatform.macOS ? 16.0 : 24.0;
        for (var index = 0; index < 2; index++) {
          final artwork = find.descendant(
            of: boxes.at(index),
            matching: find.byType(AnimatedContainer),
          );
          final target = find.descendant(
            of: boxes.at(index),
            matching: find.byType(GestureDetector),
          );
          expect(tester.getSize(artwork), Size.square(dimension));
          expect(tester.getRect(target), tester.getRect(artwork));
          await tester.tapAt(
            tester.getRect(artwork).bottomRight - const Offset(1, 1),
          );
          await tester.pumpAndSettle();
        }
        expect(composer.text.text, '- [x] Parent\n  - [x] Child');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }

  for (final font in [
    'assets/fonts/OpenSans.ttf',
    if (Platform.isMacOS) '/System/Library/Fonts/SFNS.ttf',
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final marker in ['- [ ] ', '[ ] ']) {
        for (final label in [
          '',
          'dzadza',
          'A task that wraps onto several lines ' * 3,
        ]) {
          testWidgets('todo row parts align for $marker with $font '
              'at $scale and ${label.length} characters', (tester) async {
            await (FontLoader(font)..addFont(
                  font.startsWith('assets/')
                      ? rootBundle.load(font)
                      : Future.value(
                          ByteData.sublistView(File(font).readAsBytesSync()),
                        ),
                ))
                .load();
            final root = await pumpEditor(
              tester,
              '$marker$label',
              platform: TargetPlatform.macOS,
              scale: scale,
              textStyle: AppTheme.light.textTheme.bodyLarge!.copyWith(
                fontFamily: font,
              ),
            );
            final body = bodies(tester).firstOrNull ?? root;
            Rect line;
            if (label.isEmpty) {
              final hint = tester.renderObject<RenderParagraph>(
                find.text('To-do'),
              );
              line = MatrixUtils.transformRect(
                hint.getTransformTo(null),
                hint
                    .getBoxesForSelection(
                      const TextSelection(baseOffset: 0, extentOffset: 5),
                    )
                    .first
                    .toRect(),
              );
            } else {
              final start = identical(body, root) ? marker.length : 0;
              final render = tester
                  .state<EditableTextState>(editable(body))
                  .renderEditable;
              render.selectionHeightStyle = BoxHeightStyle.tight;
              line = MatrixUtils.transformRect(
                render.getTransformTo(null),
                render
                    .getBoxesForSelection(
                      TextSelection(
                        baseOffset: start,
                        extentOffset: start + label.length,
                      ),
                    )
                    .first
                    .toRect(),
              );
            }
            final add = tester.getRect(find.byTooltip('Add block'));
            final handle = tester.getRect(
              find.byTooltip('Drag to move or click to open menu'),
            );
            final artwork = tester.getRect(
              find.descendant(
                of: find.byType(DCheckbox),
                matching: find.byType(AnimatedContainer),
              ),
            );
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
            expect(
              add.center.dy,
              closeTo(line.center.dy, scale),
              reason: 'Add action and first text line',
            );
            expect(handle.center.dy, add.center.dy);
            expect(
              artwork.center.dy,
              closeTo(line.center.dy, scale),
              reason: 'Checkbox artwork and first text line',
            );
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }
  for (final font in [
    'assets/fonts/OpenSans.ttf',
    if (Platform.isMacOS) '/System/Library/Fonts/SFNS.ttf',
  ]) {
    for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'uploading an image preserves task text position and line spacing '
          'with $font on ${platform.name} at $scale',
          (tester) async {
            await (FontLoader(font)..addFont(
                  font.startsWith('assets/')
                      ? rootBundle.load(font)
                      : Future.value(
                          ByteData.sublistView(File(font).readAsBytesSync()),
                        ),
                ))
                .load();
            final upload = Completer<ComposerUploadResult>();
            final root = await pumpEditor(
              tester,
              '- [ ] Task',
              platform: platform,
              scale: scale,
              width: scale == 2 ? 600 : 350,
              textStyle: AppTheme.light.textTheme.bodyLarge!.copyWith(
                fontFamily: font,
              ),
              imageUploader:
                  (file, {required onProgress, required abortTrigger}) =>
                      upload.future,
            );
            Rect textRect() {
              final render = tester
                  .state<EditableTextState>(editable(bodies(tester).single))
                  .renderEditable;
              render.selectionHeightStyle = BoxHeightStyle.tight;
              final box = render
                  .getBoxesForSelection(
                    const TextSelection(baseOffset: 0, extentOffset: 4),
                  )
                  .first
                  .toRect();
              return MatrixUtils.transformRect(
                render.getTransformTo(null),
                box,
              );
            }

            final before = textRect();
            final checkboxBefore = tester.getRect(find.byType(DCheckbox));
            final body = bodies(tester).single;
            body.addImages([
              ComposerUploadFile(
                name: 'photo.png',
                length: () async => 1,
                openRead: () => Stream.value([1]),
              ),
            ], body.text.text.length);
            await tester.pump();
            final pending = textRect();
            upload.complete(
              const ComposerUploadResult(
                id: 1,
                originalFilename: 'photo.png',
                shortUrl: 'upload://photo',
                url: 'https://example.test/photo.png',
                width: 100,
                height: 80,
              ),
            );
            await tester.pumpAndSettle();
            final after = textRect();
            final image = tester.getRect(find.byType(ComposerImagePreview));
            final checkboxAfter = tester.getRect(find.byType(DCheckbox));
            await tester.pumpWidget(const SizedBox());
            expect(pending.top, closeTo(before.top, .1));
            expect(after.top, closeTo(before.top, .1));
            expect(after.left, closeTo(before.left, .1));
            expect(after.size, before.size);
            expect(checkboxAfter, checkboxBefore);
            expect(image.left, closeTo(after.left, .1));
            expect(image.top, greaterThanOrEqualTo(after.bottom));
            expect(image.top - after.top, lessThanOrEqualTo(24 * scale));
            expect(root.raw, '- [ ] Task\n  ![photo|100x80](upload://photo)');
          },
        );
      }
    }
  }

  testWidgets('task images retain explicitly authored blank lines', (
    tester,
  ) async {
    const image = '![photo|100x80](upload://photo)';
    final root = await pumpEditor(tester, '- [ ] Task\n  $image');
    final compact = tester.getRect(find.byType(ComposerImagePreview));
    root.text.text = '- [ ] Task\n\n  $image';
    await tester.pumpAndSettle();
    final separated = tester.getRect(find.byType(ComposerImagePreview));
    expect(separated.top - compact.top, closeTo(24, .1));
    expect(root.raw, '- [ ] Task\n\n  $image');
  });

  for (final newline in ['\n', '\r\n']) {
    for (final (label, suffix) in [
      ('no whitespace', ''),
      ('trailing spaces', '  '),
      ('trailing tab', '\t'),
      ('indented separator', '\n  '),
    ]) {
      testWidgets(
        'task image spacing stays compact with $label and ${newline.length}-character line endings',
        (tester) async {
          final source =
              ('- [ ] Task\n  ![photo|100x80](upload://photo)$suffix\n'
                      '- [ ] Next\n  - Child')
                  .replaceAll('\n', newline);
          final root = await pumpEditor(
            tester,
            source,
            platform: TargetPlatform.macOS,
          );
          final image = find.byType(ComposerImagePreview);
          final imageBefore = tester.getRect(image);
          final nextBefore = tester.getRect(find.byType(DCheckbox).last);
          final body = bodies(tester).first;
          final bodyBefore = tester.getRect(editable(body));
          expect(nextBefore.top, closeTo(imageBefore.bottom, .1));

          await tester.tap(image);
          await tester.pumpAndSettle();

          expect(body.text.keyboardSelectedImage, isNotNull);
          expect(tester.getRect(image), imageBefore);
          expect(tester.getRect(find.byType(DCheckbox).last), nextBefore);
          expect(bodyBefore.bottom, closeTo(imageBefore.bottom, .1));

          bodies(tester)[1].requestFocus();
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(DCheckbox).last), nextBefore);
          expect(root.raw, source);
        },
      );
    }
  }

  testWidgets('extra blank lines after a task image remain visible', (
    tester,
  ) async {
    const image = '![photo|100x80](upload://photo)';
    final root = await pumpEditor(tester, '- [ ] Task\n  $image\n- [ ] Next');
    double gap() =>
        tester.getRect(find.byType(DCheckbox).last).top -
        tester.getRect(find.byType(ComposerImagePreview)).bottom;
    final compact = gap();
    root.text.text = '- [ ] Task\n  $image\n  \n\n- [ ] Next';
    await tester.pumpAndSettle();
    expect(gap() - compact, closeTo(24, .1));
    expect(root.raw, '- [ ] Task\n  $image\n  \n\n- [ ] Next');
  });

  for (final prefix in ['- [x] ', '- ']) {
    testWidgets(
      'Return after an upload continues $prefix without an empty row',
      (tester) async {
        final root = await pumpEditor(
          tester,
          '${prefix}Task',
          platform: TargetPlatform.macOS,
          imageUploader:
              (file, {required onProgress, required abortTrigger}) async =>
                  const ComposerUploadResult(
                    id: 1,
                    originalFilename: 'photo.png',
                    shortUrl: 'upload://photo',
                    url: 'https://example.test/photo.png',
                    width: 100,
                    height: 80,
                  ),
        );
        final body = bodies(tester).single;
        body.text.selection = TextSelection.collapsed(
          offset: body.text.text.length,
        );
        body.requestFocus();
        body.addImages([
          ComposerUploadFile(
            name: 'photo.png',
            length: () async => 1,
            openRead: () => Stream.value([1]),
          ),
        ], body.text.text.length);
        await tester.pumpAndSettle();
        final beforeReturn = root.text.text;
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        final nextPrefix = prefix == '- [x] ' ? '- [ ] ' : prefix;
        expect(
          root.text.text,
          '${prefix}Task\n  ![photo|100x80](upload://photo)\n$nextPrefix',
        );
        expect(
          tester.getRect(editable(bodies(tester).last)).top -
              tester.getRect(find.byType(ComposerImagePreview)).bottom,
          lessThan(10),
        );
        root.history.undo();
        await tester.pumpAndSettle();
        expect(root.text.text, beforeReturn);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'vertical arrows keep editing the task after Return splits its text',
    (tester) async {
      final root = await pumpEditor(
        tester,
        'Before\n\n- [ ] FirstSecond\n  Continued\n\nAfter',
        platform: TargetPlatform.macOS,
      );
      final first = bodies(tester).single;
      first.text.selection = const TextSelection.collapsed(offset: 5);
      first.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      const source =
          'Before\n\n- [ ] First\n- [ ] Second\n  Continued\n\nAfter';
      expect(root.text.text, source);
      final second = bodies(tester).last;
      expect(second.text.text, 'Second\nContinued');
      expect(second.focus.hasPrimaryFocus, isTrue);
      expect(second.text.selection.extentOffset, 0);

      for (var repetition = 0; repetition < 2; repetition++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(second.text.selection, const TextSelection.collapsed(offset: 7));
        expect(second.focus.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(second.text.selection, const TextSelection.collapsed(offset: 0));
        expect(second.focus.hasPrimaryFocus, isTrue);
      }
      for (final (down, up) in [
        (LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowUp),
        (LogicalKeyboardKey.pageDown, LogicalKeyboardKey.pageUp),
      ]) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(down);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(second.text.selection.baseOffset, 0);
        expect(second.text.selection.extentOffset, 7);
        expect(second.focus.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(up);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(second.text.selection, const TextSelection.collapsed(offset: 0));
        expect(second.focus.hasPrimaryFocus, isTrue);
      }
      expect(root.text.text, source);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final newline in ['\n', '\r\n']) {
    for (final first in ['First', '']) {
      for (final nested in [false, true]) {
        testWidgets(
          'Right Arrow enters the next task text '
          '(newline ${newline.length}, empty ${first.isEmpty}, nested $nested)',
          (tester) async {
            final prefix = nested ? '- [ ] Parent$newline  ' : '';
            final indent = nested ? '  ' : '';
            final source = '$prefix- [ ] $first$newline$indent- [x] Second';
            final root = await pumpEditor(tester, source);
            final items = bodies(tester);
            final from = items[items.length - 2];
            final next = items.last;
            from.text.selection = TextSelection.collapsed(offset: first.length);
            from.requestFocus();
            await tester.pumpAndSettle();

            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await tester.pumpAndSettle();
            expect(next.focus.hasPrimaryFocus, isTrue);
            expect(
              next.text.selection,
              const TextSelection.collapsed(offset: 0),
            );
            expect(root.text.text, source);

            from.requestFocus();
            from.text.selection = const TextSelection.collapsed(offset: 0);
            await tester.pumpAndSettle();
            await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
            await tester.pumpAndSettle();
            for (var i = 0; i < first.length; i++) {
              await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
              await tester.pumpAndSettle();
            }
            await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
            expect(next.focus.hasPrimaryFocus, isTrue);
            expect(
              next.text.selection,
              const TextSelection.collapsed(offset: 0),
            );

            tester.testTextInput.updateEditingValue(
              const TextEditingValue(
                text: 'XSecond',
                selection: TextSelection.collapsed(offset: 1),
              ),
            );
            await tester.pumpAndSettle();
            expect(root.text.text, source.replaceFirst('Second', 'XSecond'));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final source in [
    '- [ ] ',
    '- [ ] Task',
    '- [ ] Task\n  - [ ] Nested',
    '- [ ] Task\n\n  Paragraph',
    '- [ ] Task\n  - Bullet',
  ]) {
    testWidgets('Arrow Right stays in final text block: $source', (
      tester,
    ) async {
      final root = await pumpEditor(
        tester,
        source,
        platform: TargetPlatform.macOS,
      );
      final body = bodies(tester).last;
      body.text.selection = TextSelection.collapsed(
        offset: body.text.text.length,
      );
      body.requestFocus();
      await tester.pumpAndSettle();
      final before = body.text.value;
      final focusChanges = <bool>[];
      body.focus.addListener(
        () => focusChanges.add(body.focus.hasPrimaryFocus),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(body.focus.hasPrimaryFocus, isTrue);
      expect(focusChanges, isEmpty);
      expect(body.text.value, before);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(focusChanges, isEmpty);
      expect(body.text.value, before);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(root.text.text, source);
    });
  }

  testWidgets('Arrow Right moves from a task to the following paragraph', (
    tester,
  ) async {
    const source = '- [ ] Task\n\nFollowing';
    final root = await pumpEditor(
      tester,
      source,
      platform: TargetPlatform.macOS,
    );
    final body = bodies(tester).single;
    body.text.selection = TextSelection.collapsed(
      offset: body.text.text.length,
    );
    body.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(root.focus.hasPrimaryFocus, isTrue);
    expect(root.text.selection.extentOffset, source.indexOf('Following'));
    expect(root.text.text, source);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final font in [
        'assets/fonts/OpenSans.ttf',
        if (Platform.isMacOS) '/System/Library/Fonts/SFNS.ttf',
      ]) {
        for (final marker in ['- [ ] ', '[ ] ']) {
          testWidgets('todo hint matches typed glyphs for $marker with $font '
              'on ${platform.name} at $scale', (tester) async {
            await (FontLoader(font)..addFont(
                  font.startsWith('assets/')
                      ? rootBundle.load(font)
                      : Future.value(
                          ByteData.sublistView(File(font).readAsBytesSync()),
                        ),
                ))
                .load();
            final root = await pumpEditor(
              tester,
              '${marker}Previous\n$marker',
              scale: scale,
              platform: platform,
              textStyle: AppTheme.light.textTheme.bodyLarge!.copyWith(
                fontFamily: font,
              ),
            );
            Rect hintRect() {
              final hint = tester.renderObject<RenderParagraph>(
                find.text('To-do'),
              );
              final box = hint
                  .getBoxesForSelection(
                    const TextSelection(baseOffset: 0, extentOffset: 5),
                  )
                  .first
                  .toRect();
              return MatrixUtils.transformRect(hint.getTransformTo(null), box);
            }

            final before = hintRect();
            final body = bodies(tester).lastOrNull ?? root;
            final prefix = identical(body, root)
                ? '${marker}Previous\n$marker'
                : '';
            await tester.enterText(editable(body), '${prefix}To-do');
            await tester.pumpAndSettle();
            final render = tester
                .state<EditableTextState>(
                  editable(bodies(tester).lastOrNull ?? root),
                )
                .renderEditable;
            render.selectionHeightStyle = BoxHeightStyle.tight;
            final box = render
                .getBoxesForSelection(
                  TextSelection(
                    baseOffset: prefix.length,
                    extentOffset: prefix.length + 5,
                  ),
                )
                .first
                .toRect();
            final after = MatrixUtils.transformRect(
              render.getTransformTo(null),
              box,
            );
            await tester.enterText(
              editable(bodies(tester).lastOrNull ?? root),
              prefix,
            );
            await tester.pumpAndSettle();
            final restored = hintRect();
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
            expect(after.left, closeTo(before.left, .1));
            expect(after.top, closeTo(before.top, .1));
            expect(after.width, closeTo(before.width, .1));
            expect(after.height, closeTo(before.height, .1));
            expect(restored, before);
          });
        }
      }
      for (final prefix in ['', 'Before\n\n']) {
        testWidgets(
          'converting ${prefix.isEmpty ? "first" : "later"} line to a task '
          'preserves text metrics on ${platform.name} at $scale',
          (tester) async {
            const label = 'Task';
            final root = await pumpEditor(
              tester,
              '$prefix$label',
              scale: scale,
              platform: platform,
            );
            Rect textRect(ComposerController composer, int start, int length) {
              final render = tester
                  .state<EditableTextState>(editable(composer))
                  .renderEditable;
              // EditableText's selection boxes include different leading at
              // paragraph boundaries. Compare the actual glyph bounds.
              final selectionHeightStyle = render.selectionHeightStyle;
              render.selectionHeightStyle = BoxHeightStyle.tight;
              final box = render
                  .getBoxesForSelection(
                    TextSelection(
                      baseOffset: start,
                      extentOffset: start + length,
                    ),
                  )
                  .first
                  .toRect();
              render.selectionHeightStyle = selectionHeightStyle;
              return MatrixUtils.transformRect(
                render.getTransformTo(null),
                box,
              );
            }

            final before = textRect(root, prefix.length, label.length);
            Rect precedingCaret() => tester
                .state<EditableTextState>(editable(root))
                .renderEditable
                .getLocalRectForCaret(const TextPosition(offset: 0));
            final preceding = prefix.isEmpty ? null : precedingCaret();
            root.text.value = insertComposerTodo(root.value);
            await tester.pumpAndSettle();
            final after = textRect(bodies(tester).single, 0, label.length);
            final precedingAfter = prefix.isEmpty ? null : precedingCaret();
            final checkboxWidth = tester.getSize(find.byType(DCheckbox)).width;
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();

            expect(after.width, closeTo(before.width, .1));
            expect(after.height, closeTo(before.height, .1));
            expect(after.top, closeTo(before.top, .1));
            expect(
              after.left - before.left,
              closeTo(checkboxWidth * scale, .1),
            );
            expect(precedingAfter, preceding);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  test(
    'task subtrees include paragraphs and fences and retain nested ownership',
    () {
      const source = '$complexTask\n- [x] Second\n\nAfter';
      final items = composerListItems(source);
      expect(items.map((item) => item.source), [complexTask, '- [x] Second']);
      expect(
        items.first.body.text,
        'First line\nContinued\n\nSecond paragraph\n\n```text\n[ ] literal\n```\n\n- [ ] Child\n  - [x] Grandchild',
      );
      final todos = composerTodos(source);
      expect(
        todos.map((todo) => source.substring(todo.contentStart, todo.end)),
        ['First line', 'Child', 'Grandchild', 'Second'],
      );
      expect(todos.first.itemEnd, complexTask.length);
      expect(todos[2].continuationIndent, '      ');
    },
  );

  test('code, rules and reference links retain their literal source', () {
    expect(
      composerListItems('```md\n- [ ] example\n```\n\n    - [ ] code\n\n---'),
      isEmpty,
    );
    expect(
      composerTodos('- [x] Reference\n\n[x]: https://example.test'),
      isEmpty,
    );
    expect(
      composerListItems('- [ ] Unclosed\n\n  ```\n  body').single.closed,
      isFalse,
    );
  });

  for (final newline in ['\n', '\r\n']) {
    test(
      'body patches preserve untouched indentation and map offsets (${newline.length})',
      () {
        final source = [
          '  * [x] Label',
          '    continued',
          '',
          '     extra space',
        ].join(newline);
        final item = composerListItems(source).single;
        expect(item.body.text, 'Label\ncontinued\n\n extra space');
        expect(item.body.replace(item.body.text), source);
        expect(
          item.body.replace('Label\ncontinued!\n\n extra space'),
          source.replaceFirst('continued', 'continued!'),
        );
        expect(
          item.body.replace('Label\nnew\ncontinued\n\n extra space'),
          source.replaceFirst('Label', 'Label$newline    new'),
        );
        for (var i = 0; i <= item.body.text.length; i++) {
          expect(item.body.localOffset(item.body.sourceOffset(i)), i);
        }
      },
    );
  }

  test('moving a task retains its descendants and exact source', () {
    final index = ComposerBlockIndex.parse('$complexTask\n- [x] Second');
    expect(index.blocks, hasLength(2));
    expect(index.blocks.first.kind, ComposerBlockKind.todo);
    final moved = index.move(index.blocks.first.id, 2)!;
    expect(moved.after.source, '- [x] Second\n$complexTask');
    expect(moved.after.blocks.last.source, complexTask);
  });

  test('uploads remain indented inside their task after completion', () async {
    final upload = Completer<ComposerUploadResult>();
    final root = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://example.test',
        topicId: 1,
        slug: 'topic',
        topicTitle: 'Topic',
      ),
      imageUploader: (file, {required onProgress, required abortTrigger}) =>
          upload.future,
    );
    root.text.text = '- [ ] Parent\n  - [ ] Child';
    final outer = ComposerListBodyController(
      root,
      composerListItems(root.text.text).single,
    );
    final child = ComposerListBodyController(
      outer,
      composerListItems(outer.text.text).single,
    );
    addTearDown(() {
      child.dispose();
      outer.dispose();
      root.dispose();
    });
    child.addImages([
      ComposerUploadFile(
        name: 'photo.png',
        length: () async => 1,
        openRead: () => Stream.value([1]),
      ),
    ], child.text.text.length);
    expect(root.hasActiveUploads, isTrue);
    expect(
      root.text.text,
      contains('Child\n    ${root.uploadPlaceholders.values.single}'),
    );
    upload.complete(
      const ComposerUploadResult(
        id: 1,
        originalFilename: 'photo.png',
        shortUrl: 'upload://photo',
        url: 'https://example.test/photo.png',
        width: 100,
        height: 80,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      root.text.text,
      contains('Child\n    ![photo|100x80](upload://photo)'),
    );
    expect(
      composerListItems(root.text.text).single.children.single.body.text,
      contains('![photo|100x80](upload://photo)'),
    );
    expect(root.hasActiveUploads, isFalse);
  });

  testWidgets('new tasks retain source and use a growing Native editor', (
    tester,
  ) async {
    final root = await pumpEditor(tester, '- [ ] First');
    expect(find.byType(DInput), findsNWidgets(2));
    expect(find.byType(DCheckbox), findsOneWidget);
    final body = bodies(tester).single;
    expect(body.text.text, 'First');
    expect(identical(body.history, root.history), isTrue);
    await tester.enterText(editable(body), 'First changed');
    await tester.pumpAndSettle();
    expect(root.text.text, '- [ ] First changed');
    root.history.undo();
    await tester.pumpAndSettle();
    expect(root.text.text, '- [ ] First');
    expect(bodies(tester).single.text.text, 'First');
    expect(tester.takeException(), isNull);
  });

  for (final newline in ['\n', '\r\n']) {
    for (final firstText in ['First', '', 'First\n  Continued']) {
      for (final nested in [false, true]) {
        testWidgets(
          'Left at a task start paints the previous text caret immediately '
          '(newline ${newline.length}, first "$firstText", nested $nested)',
          (tester) async {
            final prefix = nested ? '- [ ] Parent$newline  ' : '';
            final indent = nested ? '  ' : '';
            final firstSource = firstText.replaceAll('\n', '$newline$indent');
            final source =
                '$prefix- [x] $firstSource$newline$indent- [ ] Second';
            final root = await pumpEditor(
              tester,
              source,
              platform: TargetPlatform.macOS,
            );
            final items = bodies(tester);
            final first = items[items.length - 2];
            final second = items.last;
            second.text.selection = const TextSelection.collapsed(offset: 0);
            second.requestFocus();
            await tester.pumpAndSettle();

            await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
            await tester.pump();

            expect(first.focus.hasPrimaryFocus, isTrue);
            // Check the frame that just painted, before deferred focus changes
            // can hide a caret rendered beside the enclosing projection.
            for (final composer in [root, ...items]) {
              expect(
                tester
                    .state<EditableTextState>(editable(composer))
                    .renderEditable
                    .hasFocus,
                identical(composer, first),
              );
            }
            final textEnd = first.text.text.length;
            expect(
              first.text.selection,
              TextSelection.collapsed(offset: textEnd),
            );
            final sourceEnd = source.indexOf('$newline$indent- [ ] Second');
            expect(root.text.selection.extentOffset, sourceEnd);

            tester.testTextInput.updateEditingValue(
              TextEditingValue(
                text: '${first.text.text}!',
                selection: TextSelection.collapsed(offset: textEnd + 1),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              root.text.text,
              source.replaceRange(sourceEnd, sourceEnd, '!'),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'Return splits tasks and Shift Return stays in their content column',
    (tester) async {
      final root = await pumpEditor(tester, '- [x] First');
      var body = bodies(tester).single;
      body.text.selection = TextSelection.collapsed(
        offset: body.text.text.length,
      );
      body.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(root.text.text, '- [x] First\n- [ ] ');
      body = bodies(tester).last;
      expect(body.focus.hasPrimaryFocus, isTrue);
      await tester.enterText(editable(body), 'Second');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(root.text.text, '- [x] First\n- [ ] Second\n  ');
      await tester.enterText(
        editable(bodies(tester).last),
        'Second\ncontinued',
      );
      await tester.pumpAndSettle();
      expect(root.text.text, '- [x] First\n- [ ] Second\n  continued');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'nested tasks remain independent and code stays editable at narrow widths',
    (tester) async {
      final root = await pumpEditor(tester, complexTask, scale: 2);
      expect(find.byType(DCheckbox), findsNWidgets(3));
      expect(bodies(tester), hasLength(3));
      final child = bodies(tester)[1];
      child.toggle();
      await tester.pumpAndSettle();
      expect(
        root.text.text,
        complexTask.replaceFirst('- [ ] Child', '- [x] Child'),
      );
      root.history.undo();
      await tester.pumpAndSettle();
      expect(root.text.text, complexTask);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty nested tasks outdent, and document selection copies canonical Markdown',
    (tester) async {
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final root = await pumpEditor(tester, '- [ ] Parent\n  - [ ] ');
      final nested = bodies(tester).last;
      nested.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(root.text.text, '- [ ] Parent\n- [ ] ');
      root.history.undo();
      await tester.pumpAndSettle();
      expect(root.text.text, '- [ ] Parent\n  - [ ] ');
      bodies(tester).last.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        root.text.selection,
        TextSelection(baseOffset: 0, extentOffset: root.text.text.length),
      );
      expect(root.focus.hasPrimaryFocus, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(copied, root.text.text);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'composition remains mounted and committing preserves the task prefix',
    (tester) async {
      final root = await pumpEditor(tester, '- [ ] Task');
      final body = bodies(tester).single;
      body.requestFocus();
      await tester.pumpAndSettle();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Task 文',
          selection: TextSelection.collapsed(offset: 6),
          composing: TextRange(start: 5, end: 6),
        ),
      );
      await tester.pump();
      expect(identical(bodies(tester).single, body), isTrue);
      expect(root.text.text, '- [ ] Task 文');
      expect(root.history.composing, isTrue);
      final held = root.text.text;
      body.toggle();
      expect(root.text.text, held);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Task 文',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pumpAndSettle();
      expect(root.history.composing, isFalse);
      expect(root.text.text, held);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Return exits an empty top-level task and Backspace unwraps its whole body',
    (tester) async {
      final root = await pumpEditor(tester, '- [ ] ');
      bodies(tester).single.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(root.text.text, isEmpty);
      root.text.text = '- [ ] First\n  Continued\n\n  Second paragraph';
      await tester.pumpAndSettle();
      final body = bodies(tester).single;
      body.text.selection = const TextSelection.collapsed(offset: 0);
      body.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(root.text.text, 'First\nContinued\n\nSecond paragraph');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('removed task hosts cannot toggle or commit a stale edit', (
    tester,
  ) async {
    final root = await pumpEditor(tester, '- [ ] Task');
    final body = bodies(tester).single;
    root.text.text = 'Replacement';
    expect(body.isCurrent, isFalse);
    body.toggle();
    body.text.text = 'Stale task';
    expect(root.text.text, 'Replacement');
    await tester.pumpAndSettle();
    expect(find.byType(DCheckbox), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested reference links keep their document-level definitions', (
    tester,
  ) async {
    const source =
        '- [ ] Parent\n  - [x] Reference\n\n[x]: https://example.test';
    final root = await pumpEditor(tester, source);
    expect(find.byType(DCheckbox), findsOneWidget);
    expect(composerTodos(source), hasLength(1));
    expect(bodies(tester), hasLength(2));
    expect(bodies(tester).last.text.text, '[x] Reference');
    expect(bodies(tester).first.text.todos, isEmpty);
    expect(root.text.text, source);
    expect(tester.takeException(), isNull);
  });

  testWidgets('post tasks retain full content and mixed list bullets', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SizedBox(
            width: 350,
            child: CookedHtml(
              html:
                  '<ul><li><p><span class="chcklst-box checked"></span> Parent<br>continuation</p>'
                  '<p>Second paragraph</p><pre><code>sample code</code></pre>'
                  '<ul><li><span class="chcklst-box"></span> Child</li></ul></li><li>Ordinary bullet</li></ul>',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DCheckbox), findsNWidgets(2));
    expect(find.byType(HtmlListMarker), findsOneWidget);
    final paragraphs = tester.renderObjectList<RenderParagraph>(
      find.byType(RichText),
    );
    RenderParagraph paragraph(String text) =>
        paragraphs.firstWhere((p) => p.text.toPlainText().contains(text));
    final first = paragraph('Parent');
    final second = paragraph('Second paragraph');
    expect(
      first.localToGlobal(Offset.zero).dx,
      second.localToGlobal(Offset.zero).dx,
    );
    expect(
      paragraph('Child').text.style?.decoration,
      isNot(TextDecoration.lineThrough),
    );
    expect(
      paragraph('sample code').text.style?.decoration,
      isNot(TextDecoration.lineThrough),
    );
    expect(tester.takeException(), isNull);
  });
}
