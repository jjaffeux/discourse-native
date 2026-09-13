import 'dart:async';

import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_image.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _intro =
    "Yeah so far we haven't done much in the way of discovery apart from adding "
    'a link to the global sidebar section as you say:';
const _middle =
    'Though it is an interesting idea I think to have something like the '
    'Categories sidebar block, which would let a user configure which boards '
    'they see over here easily:';
const _last =
    'Maybe even an "Add/remove to/from my sidebar..." entry in the board menu?';
const _image = '![pasted-image|340x500](upload://image.png)';
const _target = ComposerTarget(
  siteUrl: 'https://example.test',
  topicId: 7,
  slug: 'image-spacing',
  topicTitle: 'Image spacing',
);

void main() {
  testWidgets(
    'pasting images between paragraphs saves the visible line breaks',
    (tester) async {
      final uploads = <Completer<ComposerUploadResult>>[];
      final composer = ComposerController(
        _target,
        imageUploader: (file, {required onProgress, required abortTrigger}) {
          final completion = Completer<ComposerUploadResult>();
          uploads.add(completion);
          return completion.future;
        },
      );
      addTearDown(composer.dispose);
      await _pumpEditor(tester, composer);
      await tester.enterText(find.byType(EditableText), _intro);

      for (final paragraph in [_middle, _last]) {
        final count = uploads.length;
        await _pasteImage(tester);
        expect(uploads, hasLength(count + 1));
        uploads.last.complete(_result);
        await tester.pumpAndSettle();
        await _type(tester, composer, paragraph);
        if (count == 0) {
          final image = composer.text.imageBlocks.single;
          expect(composer.text.text[image.end], '\n');
          final render = tester
              .state<EditableTextState>(find.byType(EditableText))
              .renderEditable;
          final textRect = render.getLocalRectForCaret(
            TextPosition(offset: image.end + 1),
          );
          expect(
            render.localToGlobal(textRect.topLeft).dy,
            greaterThanOrEqualTo(
              tester.getRect(find.byType(ComposerImagePreview)).bottom,
            ),
          );
        }
      }
      await _type(tester, composer, '\n\n');
      await _pasteImage(tester);
      uploads.last.complete(_result);
      await tester.pumpAndSettle();

      expect(
        composer.raw,
        '$_intro\n$_image\n$_middle\n$_image\n$_last\n\n$_image',
      );
      expect(composer.text.imageBlocks, hasLength(3));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.macOS,
    }),
  );

  testWidgets('continued typing stays after an unfinished upload batch', (
    tester,
  ) async {
    final uploads = <Completer<ComposerUploadResult>>[];
    final composer = ComposerController(
      _target,
      imageUploader: (file, {required onProgress, required abortTrigger}) {
        final completion = Completer<ComposerUploadResult>();
        uploads.add(completion);
        return completion.future;
      },
    );
    addTearDown(composer.dispose);
    composer.text.value = const TextEditingValue(
      text: 'Before\nAfter',
      selection: TextSelection.collapsed(offset: 6),
    );
    await _pumpEditor(tester, composer);
    composer.addImages([_file, _file], 6);
    uploads.first.complete(_result);
    await tester.pumpAndSettle();
    await _type(tester, composer, 'Caption');
    uploads.last.complete(_result);
    await tester.pumpAndSettle();

    expect(composer.raw, 'Before\n$_image\n$_image\nCaptionAfter');
    expect(composer.text.selection.extentOffset, composer.raw.indexOf('After'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final gallery in [false, true]) {
    final block = gallery
        ? '[grid]\n$_image\n$_image\n$_image\n[/grid]'
        : _image;
    for (final (label, source, offset, expected) in [
      ('end of draft', 'Before', 6, 'Before\n$block\nTyped'),
      ('empty draft', '', 0, '$block\nTyped'),
      ('before existing text', 'BeforeAfter', 6, 'Before\n$block\nTypedAfter'),
      (
        'before existing newline',
        'Before\nAfter',
        6,
        'Before\n$block\nTypedAfter',
      ),
      (
        'before blank line',
        'Before\n\nAfter',
        6,
        'Before\n$block\nTyped\nAfter',
      ),
    ]) {
      testWidgets('typing after ${gallery ? 'gallery' : 'image'} at $label', (
        tester,
      ) async {
        final completion = Completer<ComposerUploadResult>();
        final composer = ComposerController(
          _target,
          imageUploader: (file, {required onProgress, required abortTrigger}) =>
              completion.future,
        );
        addTearDown(composer.dispose);
        composer.text.value = TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: offset),
        );
        await _pumpEditor(tester, composer);
        composer.addImages([
          _file,
          if (gallery) ...[_file, _file],
        ], offset);
        completion.complete(_result);
        await tester.pumpAndSettle();
        await _type(tester, composer, 'Typed');

        expect(composer.raw, expected);
        expect(composer.text.galleryBlocks, hasLength(gallery ? 1 : 0));
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

Future<void> _pumpEditor(
  WidgetTester tester,
  ComposerController composer,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ComposerEditor(
          composer: composer,
          hintText: 'Write a reply',
          textStyle: const TextStyle(fontSize: 16, height: 1.5),
          hintStyle: null,
          readClipboardImages: () async => [_file],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.showKeyboard(find.byType(EditableText));
}

Future<void> _pasteImage(WidgetTester tester) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

Future<void> _type(
  WidgetTester tester,
  ComposerController composer,
  String insertion,
) async {
  final old = composer.text.value;
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: old.text.replaceRange(
        old.selection.start,
        old.selection.end,
        insertion,
      ),
      selection: TextSelection.collapsed(
        offset: old.selection.start + insertion.length,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _file = ComposerUploadFile(
  name: 'pasted-image.png',
  length: () async => 3,
  openRead: () => Stream.value([1, 2, 3]),
);

const _result = ComposerUploadResult(
  id: 1,
  originalFilename: 'pasted-image.png',
  shortUrl: 'upload://image.png',
  url: 'https://example.test/image.png',
  thumbnailWidth: 340,
  thumbnailHeight: 500,
);
