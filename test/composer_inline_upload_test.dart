import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_image.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a pending upload completes at its reordered block position', (
    tester,
  ) async {
    final request = Completer<ComposerUploadResult>();
    final composer = ComposerController(
      _target,
      imageUploader: (file, {required onProgress, required abortTrigger}) =>
          request.future,
    );
    addTearDown(composer.dispose);
    composer.text.text = 'Before\n\nAfter';
    await _pump(tester, composer);
    composer.addImages([_file], 8);
    await tester.pump();
    final upload = composer.blocks.index.blocks.singleWhere(
      (block) => block.label == 'Upload',
    );
    expect(
      composer.blocks.moveTo(
        composer.blocks.index.blocks.length,
        blockId: upload.id,
        expectedRevision: composer.blocks.revision,
      ),
      isTrue,
    );
    request.complete(_result);
    await tester.pumpAndSettle();
    expect(
      composer.raw.indexOf('After'),
      lessThan(composer.raw.indexOf('upload://photo')),
    );
    expect('upload://photo'.allMatches(composer.raw), hasLength(1));
    expect(composer.hasActiveUploads, isFalse);
  });

  for (final scrolled in [false, true]) {
    testWidgets('file drag keeps existing image rendered (scrolled: $scrolled)', (
      tester,
    ) async {
      final request = Completer<ComposerUploadResult>();
      final composer = ComposerController(
        _target,
        imageUploader: (file, {required onProgress, required abortTrigger}) =>
            request.future,
      );
      addTearDown(composer.dispose);
      const originalImage =
          '![Screenshot 2026-09-16 at 20.15.19|100x100](upload://existing.png)';
      final source = '${'Before\n' * 8}$originalImage\n${'After\n' * 30}';
      composer.text.value = TextEditingValue(
        text: source,
        selection: const TextSelection.collapsed(offset: 0),
      );
      await _pump(tester, composer);
      final editor = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      editor.offset.jumpTo(scrolled ? 120 : 0);
      await tester.pump();
      final existing = composer.text.imageBlocks.single;
      final rect = composer.text.collapsedImageGlobalRect(existing)!;
      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
      final position = rect.center;
      dropTarget.onDragEntered!(
        DropEventDetails(localPosition: position, globalPosition: position),
      );
      await tester.pump();
      expect(composer.text.isImageCollapsed(existing), isTrue);
      expect(composer.text.selection.extentOffset, existing.end);
      expect(composer.text.text, source);

      for (final point in [rect.topLeft + const Offset(2, 2), rect.center]) {
        dropTarget.onDragUpdated!(
          DropEventDetails(localPosition: point, globalPosition: point),
        );
        await tester.pump();
        expect(composer.text.isImageCollapsed(existing), isTrue);
        expect(composer.text.selection.extentOffset, existing.end);
      }
      dropTarget.onDragExited!(
        DropEventDetails(localPosition: position, globalPosition: position),
      );
      await tester.pump();
      expect(composer.text.isImageCollapsed(existing), isTrue);
      expect(composer.text.text, source);

      dropTarget.onDragEntered!(
        DropEventDetails(localPosition: position, globalPosition: position),
      );
      await tester.pump();
      dropTarget.onDragDone!(
        DropDoneDetails(
          files: [
            DropItemFile(
              '/tmp/dropped.png',
              bytes: Uint8List.fromList(const [1, 2, 3]),
            ),
          ],
          localPosition: position,
          globalPosition: position,
        ),
      );
      await tester.pump();
      expect(composer.text.isImageCollapsed(existing), isTrue);
      expect(find.byType(DAttachment), findsOneWidget);
      expect(
        composer.text.text.indexOf(composer.uploadPlaceholders.values.single),
        greaterThanOrEqualTo(existing.end),
      );
      request.complete(_result);
      await tester.pumpAndSettle();
      expect(composer.text.imageBlocks.map((image) => image.url), [
        'upload://existing.png',
        'upload://photo',
      ]);
      expect(composer.raw, contains(originalImage));
      expect(find.byType(ComposerImagePreview), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
      'upload occupies its slot while typing around it (${dark ? 'dark' : 'light'})',
      (tester) async {
        final upload = Completer<ComposerUploadResult>();
        late void Function(double) progress;
        final composer = ComposerController(
          _target,
          imageUploader: (file, {required onProgress, required abortTrigger}) {
            progress = onProgress;
            return upload.future;
          },
        );
        addTearDown(composer.dispose);
        composer.text.value = const TextEditingValue(
          text: 'Before\nAfter',
          selection: TextSelection.collapsed(offset: 6),
        );
        await _pump(tester, composer, dark: dark);
        composer.addImages([_file], 6);
        await tester.pump();
        final attachment = find.byType(DAttachment);
        expect(attachment, findsOneWidget);
        expect(
          find.descendant(of: find.byType(EditableText), matching: attachment),
          findsOneWidget,
        );
        expect(find.byType(ComposerUploadQueue), findsNothing);
        progress(.42);
        await tester.pump();
        expect(find.text('Uploading · 42%'), findsOneWidget);

        await _type(tester, composer, 'Caption ');
        composer.text.selection = const TextSelection.collapsed(offset: 0);
        await _type(tester, composer, 'Intro ');
        final render = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        final after = render.localToGlobal(
          render
              .getLocalRectForCaret(
                TextPosition(offset: composer.text.text.indexOf('Caption')),
              )
              .topLeft,
        );
        expect(
          after.dy,
          greaterThanOrEqualTo(tester.getRect(attachment).bottom),
        );
        expect(composer.raw, 'Intro Before\nCaption After');
        expect(composer.draft.reply, isNot(contains('upload-')));
        upload.complete(_result);
        await tester.pumpAndSettle();
        expect(attachment, findsNothing);
        expect(find.byType(ComposerImagePreview), findsOneWidget);
        expect(
          composer.raw,
          'Intro Before\n![photo|100x100](upload://photo)\nCaption After',
        );
        expect(composer.text.selection.extentOffset, 6);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('completion preserves selection of the upload component', (
    tester,
  ) async {
    final request = Completer<ComposerUploadResult>();
    final composer = ComposerController(
      _target,
      imageUploader: (file, {required onProgress, required abortTrigger}) =>
          request.future,
    );
    addTearDown(composer.dispose);
    await _pump(tester, composer);
    composer.addImages([_file], 0);
    await tester.pump();
    composer.text.selection = const TextSelection.collapsed(offset: 0);
    request.complete(_result);
    await tester.pumpAndSettle();
    final image = composer.text.imageBlocks.single;
    expect(
      composer.text.selection,
      TextSelection(baseOffset: image.start, extentOffset: image.end),
    );
    expect(composer.text.keyboardSelectedImage, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(composer.raw, isEmpty);
  });

  testWidgets('a new gallery preserves selection of its pending slot', (
    tester,
  ) async {
    final request = Completer<ComposerUploadResult>();
    final composer = ComposerController(
      _target,
      imageUploader: (file, {required onProgress, required abortTrigger}) =>
          request.future,
    );
    addTearDown(composer.dispose);
    await _pump(tester, composer);
    composer.addImages([_file, _file, _file], 0);
    await tester.pump();
    composer.text.selection = const TextSelection.collapsed(offset: 0);
    request.complete(_result);
    await tester.pumpAndSettle();
    final gallery = composer.text.galleryBlocks.single;
    expect(
      composer.text.selection,
      TextSelection(baseOffset: gallery.start, extentOffset: gallery.end),
    );
    expect(composer.text.keyboardSelectedProjection, isNotNull);
    expect(gallery.images, hasLength(3));
  });

  testWidgets('Backspace selects a pending upload before cancelling it', (
    tester,
  ) async {
    final request = Completer<ComposerUploadResult>();
    var cancelled = false;
    final composer = ComposerController(
      _target,
      imageUploader: (file, {required onProgress, required abortTrigger}) {
        unawaited(abortTrigger.then((_) => cancelled = true));
        return request.future;
      },
    );
    addTearDown(composer.dispose);
    await _pump(tester, composer);
    composer.addImages([_file], 0);
    await tester.pump();
    composer.text.value = TextEditingValue(
      text: '${composer.text.text.trimRight()}\n',
      selection: TextSelection.collapsed(
        offset: composer.text.text.trimRight().length + 1,
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(cancelled, isFalse);
    expect(composer.uploads, hasLength(1));
    expect(composer.text.text.endsWith('\n'), isFalse);
    expect(composer.text.keyboardSelectedSyntax?.kind.name, 'upload');
    expect(composer.text.selection.isCollapsed, isFalse);
    final rendered = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    expect(
      rendered
          .getLineAtOffset(TextPosition(offset: composer.text.text.length))
          .start,
      0,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(cancelled, isTrue);
    expect(composer.uploads, isEmpty);
    expect(composer.raw, isEmpty);
    request.complete(_result);
    await tester.pumpAndSettle();
    expect(composer.raw, isEmpty);
  });

  testWidgets('cancel targets the clicked row in a batch', (tester) async {
    final aborted = <String>[];
    final composer = ComposerController(
      _target,
      imageUploader: (file, {required onProgress, required abortTrigger}) {
        unawaited(abortTrigger.then((_) => aborted.add(file.name)));
        return Completer<ComposerUploadResult>().future;
      },
    );
    addTearDown(composer.dispose);
    await _pump(tester, composer);
    composer.addImages([
      _file,
      ComposerUploadFile(
        name: 'second.png',
        length: _file.length,
        openRead: _file.openRead,
      ),
    ], 0);
    await tester.pump();
    final first = composer.uploads.first.id;
    final cancel = find.descendant(
      of: find.byKey(ValueKey('composer-inline-upload-$first')),
      matching: find.byTooltip('Cancel upload'),
    );
    await tester.tap(cancel);
    await tester.pump();
    expect(aborted, ['photo.png']);
    expect(composer.uploads.single.file.name, 'second.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure retries in place and cancel removes the slot', (
    tester,
  ) async {
    final requests = <Completer<ComposerUploadResult>>[];
    var aborted = false;
    final composer = ComposerController(
      _target,
      imageUploader: (file, {required onProgress, required abortTrigger}) {
        final result = Completer<ComposerUploadResult>();
        requests.add(result);
        unawaited(abortTrigger.then((_) => aborted = true));
        return result.future;
      },
    );
    addTearDown(composer.dispose);
    await _pump(tester, composer);
    composer.addImages([_file], 0);
    await tester.pump();
    await _type(tester, composer, 'Keep typing');
    requests.first.completeError(
      const ComposerUploadException('Please try again.'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Please try again.'), findsOneWidget);
    await tester.tap(find.byTooltip('Retry upload'));
    await tester.pump();
    expect(requests, hasLength(2));
    expect(find.text('Retrying · 0%'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel upload'));
    await tester.pumpAndSettle();
    expect(aborted, isTrue);
    expect(composer.raw, 'Keep typing');
    expect(find.byType(DAttachment), findsNothing);
    requests.last.complete(_result);
    await tester.pumpAndSettle();
    expect(composer.raw, 'Keep typing');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'deleting a selected placeholder aborts it without deleting prose',
    (tester) async {
      var aborted = false;
      final composer = ComposerController(
        _target,
        imageUploader: (file, {required onProgress, required abortTrigger}) {
          unawaited(abortTrigger.then((_) => aborted = true));
          return Completer<ComposerUploadResult>().future;
        },
      );
      addTearDown(composer.dispose);
      await _pump(tester, composer);
      composer.addImages([_file], 0);
      await tester.pump();
      await _type(tester, composer, 'Keep');
      final marker = composer.uploadPlaceholders.values.single;
      composer.text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: marker.length,
      );
      await _type(tester, composer, '');
      expect(aborted, isTrue);
      expect(composer.raw, 'Keep');
      expect(find.byType(DAttachment), findsNothing);
    },
  );

  testWidgets('deleting a batch cannot flush a deleted ready upload', (
    tester,
  ) async {
    final requests = <Completer<ComposerUploadResult>>[];
    final composer = ComposerController(
      _target,
      imageUploader: (file, {required onProgress, required abortTrigger}) {
        final result = Completer<ComposerUploadResult>();
        requests.add(result);
        return result.future;
      },
    );
    addTearDown(composer.dispose);
    await _pump(tester, composer);
    composer.addImages([_file, _file], 0);
    requests.last.complete(_result);
    await tester.pump();
    composer.text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: composer.text.text.length,
    );
    await _type(tester, composer, 'Replacement');
    expect(composer.raw, 'Replacement');
    expect(composer.uploads, isEmpty);
    requests.first.complete(_result);
    await tester.pump();
    expect(composer.raw, 'Replacement');
  });

  testWidgets('undo after completion cannot resurrect an orphan upload', (
    tester,
  ) async {
    final request = Completer<ComposerUploadResult>();
    final composer = ComposerController(
      _target,
      imageUploader: (file, {required onProgress, required abortTrigger}) =>
          request.future,
    );
    addTearDown(composer.dispose);
    await _pump(tester, composer);
    composer.addImages([_file], 0);
    await tester.pump(const Duration(seconds: 1));
    await _type(tester, composer, 'Caption');
    await tester.pump(const Duration(seconds: 1));
    request.complete(_result);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(composer.text.text, isNot(contains('upload-')));
    expect(composer.uploads, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  ComposerController composer, {
  bool dark = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ComposerEditor(
            composer: composer,
            hintText: 'Write a reply',
            textStyle: const TextStyle(fontSize: 16, height: 1.5),
            hintStyle: null,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.showKeyboard(find.byType(EditableText));
}

Future<void> _type(
  WidgetTester tester,
  ComposerController composer,
  String insertion,
) async {
  final value = composer.text.value;
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: value.text.replaceRange(
        value.selection.start,
        value.selection.end,
        insertion,
      ),
      selection: TextSelection.collapsed(
        offset: value.selection.start + insertion.length,
      ),
    ),
  );
  await tester.pump();
}

const _target = ComposerTarget(
  siteUrl: 'https://example.test',
  topicId: 1,
  slug: 'test',
  topicTitle: 'Test',
);
final _file = ComposerUploadFile(
  name: 'photo.png',
  length: () async => 3,
  openRead: () => Stream.value([1, 2, 3]),
);
const _result = ComposerUploadResult(
  id: 1,
  originalFilename: 'photo.png',
  shortUrl: 'upload://photo',
  url: 'https://example.test/photo.png',
  width: 100,
  height: 100,
);
