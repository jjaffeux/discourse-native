import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer_block_surface.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_image.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/composer_upload_placeholder.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scaling_benchmark.dart';

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

  for (final direction in TextDirection.values) {
    for (final dark in [false, true]) {
      testWidgets(
        'file drop follows the block insertion line ($direction, $dark)',
        (tester) async {
          final request = Completer<ComposerUploadResult>();
          final composer = ComposerController(
            _target,
            imageUploader:
                (file, {required onProgress, required abortTrigger}) =>
                    request.future,
          );
          addTearDown(composer.dispose);
          composer.text.text = 'Before\n\nAfter';
          await _pump(tester, composer, direction: direction, dark: dark);
          final surface = tester.widget<ComposerBlockSurface>(
            find.byType(ComposerBlockSurface),
          );
          final blocks = composer.blocks.index.blocks;
          final before = surface.blockRect(blocks.first)!;
          final after = surface.blockRect(blocks.last)!;
          final middle = (before.bottom + after.top) / 2;
          final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
          final editorRect = tester.getRect(find.byType(ComposerEditor));
          final line = find.byType(DDropIndicator);
          for (final y in [before.top, middle, after.bottom]) {
            final position = Offset(before.center.dx, y);
            dropTarget.onDragUpdated!(
              DropEventDetails(
                localPosition: position,
                globalPosition: position,
              ),
            );
            await tester.pump();
            expect(line, findsOneWidget);
            final rect = tester.getRect(line);
            expect(rect.center.dy, closeTo(y, .01));
            final handle = tester.getRect(
              find.byKey(
                ValueKey(
                  'composer-block-handle-${composer.blocks.selected!.id}',
                ),
              ),
            );
            final contentEdge = direction == TextDirection.ltr
                ? handle.right + DSpacing.controlGap
                : handle.left - DSpacing.controlGap;
            expect(
              direction == TextDirection.ltr ? rect.left : rect.right,
              closeTo(contentEdge, .01),
            );
            expect(
              direction == TextDirection.ltr ? rect.right : rect.left,
              closeTo(
                direction == TextDirection.ltr
                    ? editorRect.right
                    : editorRect.left,
                .01,
              ),
            );
            expect(composer.raw, 'Before\n\nAfter');
          }
          final position = Offset(before.center.dx, middle);
          dropTarget.onDragExited!(
            DropEventDetails(localPosition: position, globalPosition: position),
          );
          await tester.pump();
          expect(line, findsNothing);
          dropTarget.onDragEntered!(
            DropEventDetails(localPosition: position, globalPosition: position),
          );
          await tester.pump();
          expect(tester.getCenter(line).dy, closeTo(middle, .01));
          dropTarget.onDragDone!(
            DropDoneDetails(
              files: [
                DropItemFile('/tmp/photo.png', bytes: Uint8List.fromList([1])),
              ],
              localPosition: position,
              globalPosition: position,
            ),
          );
          await tester.pump();
          expect(line, findsNothing);
          request.complete(_result);
          await tester.pumpAndSettle();
          final imageOffset = composer.raw.indexOf('upload://photo');
          expect(imageOffset, greaterThan(composer.raw.indexOf('Before')));
          expect(imageOffset, lessThan(composer.raw.indexOf('After')));
          expect(tester.takeException(), isNull);
        },
        variant: const TargetPlatformVariant({TargetPlatform.macOS}),
      );
    }
  }

  testWidgets('empty composer shows and clears the file insertion line', (
    tester,
  ) async {
    final composer = ComposerController(_target);
    addTearDown(composer.dispose);
    await _pump(tester, composer);
    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    final position = tester.getCenter(find.byType(EditableText));
    dropTarget.onDragEntered!(
      DropEventDetails(localPosition: position, globalPosition: position),
    );
    await tester.pump();
    expect(find.byType(DDropIndicator), findsOneWidget);
    expect(composer.text.selection.extentOffset, 0);
    dropTarget.onDragExited!(
      DropEventDetails(localPosition: position, globalPosition: position),
    );
    await tester.pump();
    expect(find.byType(DDropIndicator), findsNothing);
    expect(composer.raw, isEmpty);
  });

  testWidgets('file drops use the boundary between individual empty lines', (
    tester,
  ) async {
    final request = Completer<ComposerUploadResult>();
    final composer = ComposerController(
      _target,
      imageUploader: (file, {required onProgress, required abortTrigger}) =>
          request.future,
    );
    addTearDown(composer.dispose);
    const source = 'Before\n\n\n\nAfter';
    composer.text.text = source;
    await _pump(tester, composer);
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final emptyLine = editable
        .getLocalRectForCaret(const TextPosition(offset: 8))
        .shift(editable.localToGlobal(Offset.zero));
    final position = Offset(emptyLine.left + 60, emptyLine.bottom - 2);
    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    dropTarget.onDragUpdated!(
      DropEventDetails(localPosition: position, globalPosition: position),
    );
    await tester.pump();
    expect(composer.text.selection.extentOffset, 9);
    expect(
      tester.getCenter(find.byType(DDropIndicator)).dy,
      closeTo(emptyLine.bottom, .01),
    );
    expect(composer.text.text, source);
    dropTarget.onDragDone!(
      DropDoneDetails(
        files: [
          DropItemFile('/tmp/photo.png', bytes: Uint8List.fromList([1])),
        ],
        localPosition: position,
        globalPosition: position,
      ),
    );
    await tester.pump();
    expect(find.byType(DDropIndicator), findsNothing);
    request.complete(_result);
    await tester.pumpAndSettle();
    final image = composer.text.imageBlocks.single;
    expect(composer.text.text.substring(0, image.start), 'Before\n\n\n');
    expect(composer.text.text.substring(image.end), '\nAfter');
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
      expect(find.byType(DDropIndicator), findsOneWidget);
      expect(composer.text.text, source);

      for (final point in [rect.topLeft + const Offset(2, 2), rect.center]) {
        dropTarget.onDragUpdated!(
          DropEventDetails(localPosition: point, globalPosition: point),
        );
        await tester.pump();
        expect(composer.text.isImageCollapsed(existing), isTrue);
        expect(
          composer.text.selection.extentOffset,
          point.dy < rect.center.dy
              ? composer.blocks.index.blocks.first.end
              : existing.end,
        );
      }
      dropTarget.onDragExited!(
        DropEventDetails(localPosition: position, globalPosition: position),
      );
      await tester.pump();
      expect(composer.text.isImageCollapsed(existing), isTrue);
      expect(composer.text.text, source);
      expect(find.byType(DDropIndicator), findsNothing);

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

  testWidgets('a pending upload separator stays removed after completion', (
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
    final token = composer.uploadPlaceholders.values.single;
    const second = '![Second|100x100](upload://second)';
    composer.text.value = TextEditingValue(
      text: '$token\n\n$second',
      selection: TextSelection.collapsed(offset: token.length + 1),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(composer.text.text, '$token\n$second');
    expect(composer.text.keyboardSelectedSyntax?.kind.name, 'upload');
    request.complete(_result);
    await tester.pumpAndSettle();
    expect(composer.text.imageBlocks, hasLength(2));
    final first = composer.text.imageBlocks.first;
    expect(composer.text.text.substring(first.end), '\n$second');
    final rendered = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    expect(
      '\n'.allMatches(
        rendered.text!
            .toPlainText(includeSemanticsLabels: false)
            .substring(0, composer.text.imageBlocks.last.start),
      ),
      hasLength(1),
    );
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

  group('upload placeholders', () {
    final owner = Object();
    final placeholders = ComposerUploadPlaceholders(owner);
    final one = placeholders.add(1);
    final two = placeholders.add(2);
    // Same composer prefix, but never registered with this registry.
    final twelve = ComposerUploadPlaceholders(owner).add(12);
    final source = '$two\nBefore $one$one\n$twelve\nAfter\n$one';

    test('find the first occurrence of each token in document order', () {
      expect(placeholders.find(source), [
        (id: 2, start: 0, token: two),
        (id: 1, start: two.length + 'Before '.length + 1, token: one),
      ]);
    });

    test('strip every token with the line break that follows it', () {
      expect(placeholders.strip(source), 'Before $twelve\nAfter\n');
    });
  });

  group('keystroke cost', () {
    // A composer keeps every slot it has minted so that an undo restoring a
    // settled one is still recognised. The per-keystroke scans must not pay
    // for that history: 8x the settled uploads should cost the same.
    for (final inFlight in [false, true]) {
      final condition = inFlight
          ? 'with an upload in flight'
          : 'with no slot in the document';
      test('does not grow with settled uploads $condition', () {
        for (final paragraphs in [60, 480]) {
          final document = List.filled(paragraphs, _paragraph).join('\n\n');
          final (:small, :large) = measureScaling(
            _keystrokes(document, settled: 16, inFlight: inFlight),
            _keystrokes(document, settled: 128, inFlight: inFlight),
          );
          expect(
            large,
            lessThan(small * 2),
            reason:
                'eight times the settled uploads took ${large / small} times '
                'as long over ${document.length} characters',
          );
        }
      });
    }
  });
}

const _paragraph =
    'The quick brown fox jumps over the **lazy** dog, then naps in the '
    '_shade_ of an old oak by the river.';

/// Types a character at the end of [document] and deletes it again the way
/// the editor applies an edit: input formatters, the new value, then the
/// microtasks the edit queued, so that everything a keystroke pays is timed.
int Function() _keystrokes(
  String document, {
  required int settled,
  required bool inFlight,
}) {
  final composer = ComposerController(
    _target,
    imageUploader: (file, {required onProgress, required abortTrigger}) =>
        Completer<ComposerUploadResult>().future,
  );
  addTearDown(composer.dispose);
  for (var i = 0; i < settled; i++) {
    composer.addImages([_file], 0);
    composer.cancelUpload(composer.uploads.single.id);
  }
  composer.text.text = document;
  if (inFlight) composer.addImages([_file], document.indexOf('\n\n'));
  expect(composer.uploads, hasLength(inFlight ? 1 : 0));

  final microtasks = <void Function()>[];
  final zone = Zone.current.fork(
    specification: ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, task) => microtasks.add(task),
    ),
  );
  void apply(TextEditingValue next) {
    final before = composer.text.value;
    for (final formatter in composer.text.syntaxInputFormatters) {
      next = formatter.formatEditUpdate(before, next);
    }
    composer.text.value = next;
    while (microtasks.isNotEmpty) {
      microtasks.removeAt(0)();
    }
  }

  return () => zone.run(() {
    final value = composer.text.value;
    apply(
      TextEditingValue(
        text: '${value.text}a',
        selection: TextSelection.collapsed(offset: value.text.length + 1),
      ),
    );
    apply(value);
    return composer.raw.length;
  });
}

Future<void> _pump(
  WidgetTester tester,
  ComposerController composer, {
  bool dark = false,
  TextDirection direction = TextDirection.ltr,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
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
