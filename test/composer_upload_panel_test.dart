import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer_clipboard.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_galleries.dart';
import 'package:discourse_native/src/shell/composer_image.dart';
import 'package:discourse_native/src/shell/composer_image_gallery.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/composer_upload_picker.dart';
import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  group('upload lifecycle', () {
    testWidgets('native clipboard images become retryable PNG uploads', (
      tester,
    ) async {
      const channel = MethodChannel('pasteboard');
      final messenger = tester.binding.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return switch (call.method) {
          'files' => const <String>[],
          'image' => Uint8List.fromList(const [1, 2, 3]),
          _ => fail('Unexpected pasteboard method: ${call.method}'),
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final files = await readComposerClipboardImages();

      expect(files, hasLength(1));
      expect(files.single.name, 'pasted-image.png');
      expect(await files.single.length(), 3);
      expect(await files.single.openRead().expand((chunk) => chunk).toList(), [
        1,
        2,
        3,
      ]);
      expect(await files.single.openRead().expand((chunk) => chunk).toList(), [
        1,
        2,
        3,
      ]);
      expect(calls, ['files', 'image']);
    });

    testWidgets(
      'copied image files use their pixels instead of the file icon',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'discourse-native-clipboard-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final copiedImage = File('${directory.path}/copied screenshot.png');
        copiedImage.writeAsBytesSync(const [4, 5, 6, 7]);

        const channel = MethodChannel('pasteboard');
        final messenger = tester.binding.defaultBinaryMessenger;
        final calls = <String>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return switch (call.method) {
            'files' => <String>[copiedImage.path],
            'image' => Uint8List.fromList(const [80, 78, 71]),
            _ => fail('Unexpected pasteboard method: ${call.method}'),
          };
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

        final files = await readComposerClipboardImages();

        expect(files, hasLength(1));
        expect(files.single.name, 'copied screenshot.png');
        final upload = await tester.runAsync(
          () async => (
            await files.single.length(),
            await files.single.openRead().expand((chunk) => chunk).toList(),
          ),
        );
        expect(upload?.$1, 4);
        expect(upload?.$2, [4, 5, 6, 7]);
        expect(calls, ['files']);
      },
    );

    testWidgets('the paste shortcut uploads an image at the captured caret', (
      tester,
    ) async {
      final clipboardResult = Completer<List<ComposerUploadFile>>();
      final calls = <_PanelUploadCall>[];
      var clipboardReads = 0;
      final composer = ComposerController(
        _target,
        imageUploader: (file, {required onProgress, required abortTrigger}) {
          final call = _PanelUploadCall(onProgress);
          calls.add(call);
          return call.result.future;
        },
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.value = const TextEditingValue(
        text: 'BeforeAfter',
        selection: TextSelection.collapsed(offset: 6),
      );
      await _pumpPanel(
        tester,
        shell,
        composer,
        readClipboardImages: () {
          clipboardReads++;
          return clipboardResult.future;
        },
      );

      await _pasteShortcut(tester);
      expect(clipboardReads, 1);

      // The native read is asynchronous. A later selection does not move the
      // image away from the caret where Paste was invoked.
      composer.text.selection = const TextSelection.collapsed(offset: 11);
      clipboardResult.complete([_file]);
      await tester.pump();
      expect(calls, hasLength(1));

      calls.single.result.complete(
        const ComposerUploadResult(
          id: 1,
          originalFilename: 'photo.png',
          shortUrl: 'upload://photo',
          url: 'https://meta.discourse.org/uploads/photo.png',
          thumbnailWidth: 640,
          thumbnailHeight: 480,
        ),
      );
      await tester.pump();

      expect(
        composer.text.text,
        'Before\n![photo|640x480](upload://photo)\nAfter',
      );
    });

    testWidgets('a late clipboard read cannot paste into a new composer', (
      tester,
    ) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        return switch (call.method) {
          'Clipboard.getData' => {'text': 'stale paste'},
          'Clipboard.hasStrings' => {'value': true},
          _ => null,
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final clipboardResult = Completer<List<ComposerUploadFile>>();
      final original = ComposerController(
        _target,
        imageUploader: (_, {required onProgress, required abortTrigger}) =>
            Completer<ComposerUploadResult>().future,
      );
      final replacement = ComposerController(
        _target,
        imageUploader: (_, {required onProgress, required abortTrigger}) =>
            Completer<ComposerUploadResult>().future,
      )..text.text = 'New draft';
      final shell = await _shell();
      addTearDown(original.dispose);
      addTearDown(replacement.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(
        tester,
        shell,
        original,
        readClipboardImages: () => clipboardResult.future,
      );

      await _pasteShortcut(tester);
      await _pumpPanel(
        tester,
        shell,
        replacement,
        readClipboardImages: () async => const [],
      );
      clipboardResult.complete(const []);
      await tester.pump();

      expect(replacement.text.text, 'New draft');
      expect(replacement.uploads, isEmpty);
    });

    testWidgets('plain text paste keeps Flutter clipboard behavior', (
      tester,
    ) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        return switch (call.method) {
          'Clipboard.getData' => {'text': ' pasted '},
          'Clipboard.hasStrings' => {'value': true},
          _ => null,
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final composer = ComposerController(
        _target,
        imageUploader: (_, {required onProgress, required abortTrigger}) =>
            Completer<ComposerUploadResult>().future,
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.value = const TextEditingValue(
        text: 'BeforeAfter',
        selection: TextSelection.collapsed(offset: 6),
      );
      await _pumpPanel(
        tester,
        shell,
        composer,
        readClipboardImages: () async => const [],
      );

      await _pasteShortcut(tester);

      expect(composer.text.text, 'Before pasted After');
      expect(composer.uploads, isEmpty);
    });

    testWidgets('the context menu offers image paste without clipboard text', (
      tester,
    ) async {
      final calls = <_PanelUploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: (file, {required onProgress, required abortTrigger}) {
          final call = _PanelUploadCall(onProgress);
          calls.add(call);
          return call.result.future;
        },
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(
        tester,
        shell,
        composer,
        readClipboardImages: () async => [_file],
      );

      final textField = tester.widget<TextField>(find.byType(TextField).last);
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText).last,
      );
      final toolbar =
          textField.contextMenuBuilder!(editable.context, editable)
              as AdaptiveTextSelectionToolbar;
      final paste = toolbar.buttonItems!.singleWhere(
        (item) => item.type == ContextMenuButtonType.paste,
      );
      paste.onPressed!();
      await tester.pump();

      expect(calls, hasLength(1));
    });

    testWidgets('the upload button picks images at the captured caret', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      final pickerResult = Completer<List<ComposerUploadFile>>();
      final calls = <_PanelUploadCall>[];
      var pickerCalls = 0;
      final composer = ComposerController(
        _target,
        imageUploader: (file, {required onProgress, required abortTrigger}) {
          final call = _PanelUploadCall(onProgress);
          calls.add(call);
          return call.result.future;
        },
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.value = const TextEditingValue(
        text: 'BeforeAfter',
        selection: TextSelection.collapsed(offset: 6),
      );
      await _pumpPanel(
        tester,
        shell,
        composer,
        pickImages: () {
          pickerCalls++;
          return pickerResult.future;
        },
      );

      expect(find.byTooltip('Upload images'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('composer-upload')));
      await tester.pump();
      expect(pickerCalls, 1);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('composer-upload')))
            .onPressed,
        isNull,
      );

      // Crossing the compact footer breakpoint while the platform dialog owns
      // the window must not replace the button state that is awaiting it.
      final pixelRatio = tester.view.devicePixelRatio;
      tester.view.physicalSize = Size(390 * pixelRatio, 844 * pixelRatio);
      await tester.pump();

      // The native dialog owns focus while it is open. Its result still belongs
      // at the caret from when the user pressed Upload.
      composer.text.selection = const TextSelection.collapsed(offset: 11);
      pickerResult.complete([_file]);
      await tester.pump();
      expect(calls, hasLength(1));

      calls.single.result.complete(
        const ComposerUploadResult(
          id: 1,
          originalFilename: 'photo.png',
          shortUrl: 'upload://photo',
          url: 'https://meta.discourse.org/uploads/photo.png',
          thumbnailWidth: 640,
          thumbnailHeight: 480,
        ),
      );
      await tester.pump();

      expect(
        composer.text.text,
        'Before\n![photo|640x480](upload://photo)\nAfter',
      );
      expect(composer.focus.hasFocus, isTrue);
    });

    testWidgets('the upload button follows composer availability', (
      tester,
    ) async {
      final shell = await _shell();
      final unavailable = ComposerController(_target);
      addTearDown(shell.dispose);
      addTearDown(unavailable.dispose);
      await _pumpPanel(tester, shell, unavailable);
      expect(find.byKey(const ValueKey('composer-upload')), findsNothing);

      final available = ComposerController(
        _target,
        imageUploader: (_, {required onProgress, required abortTrigger}) =>
            Completer<ComposerUploadResult>().future,
      )..beginLoadingBody();
      addTearDown(available.dispose);
      await _pumpPanel(tester, shell, available);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('composer-upload')))
            .onPressed,
        isNull,
      );

      available.loadedBody('Existing body');
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('composer-upload')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('the panel shows progress and failed upload actions', (
      tester,
    ) async {
      final calls = <_PanelUploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: (file, {required onProgress, required abortTrigger}) {
          final call = _PanelUploadCall(onProgress);
          calls.add(call);
          return call.result.future;
        },
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(tester, shell, composer);

      expect(find.text('Write a reply…'), findsOneWidget);
      composer.text.text = 'body';
      composer.addImages([_file], 4);
      calls.single.onProgress(0.37);
      await tester.pump();

      expect(find.text('Write a reply…'), findsNothing);
      expect(find.text('photo.png'), findsOneWidget);
      expect(find.text('37%'), findsOneWidget);
      expect(find.byTooltip('Cancel upload'), findsOneWidget);
      calls.single.result.completeError(
        const ComposerUploadException('The image is too large.'),
      );
      await tester.pump();

      expect(find.text('The image is too large.'), findsOneWidget);
      expect(find.byTooltip('Retry upload'), findsOneWidget);
      expect(find.byTooltip('Remove upload'), findsOneWidget);

      await tester.tap(find.byTooltip('Retry upload'));
      await tester.pump();
      expect(calls, hasLength(2));
      expect(find.text('0%'), findsOneWidget);

      await tester.tap(find.byTooltip('Cancel upload'));
      await tester.pump();
      expect(find.text('photo.png'), findsNothing);
    });
  });

  group('image selection and editing', () {
    testWidgets('arrow up after an upload selects the projected image', (
      tester,
    ) async {
      final calls = <_PanelUploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: (file, {required onProgress, required abortTrigger}) {
          final call = _PanelUploadCall(onProgress);
          calls.add(call);
          return call.result.future;
        },
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(tester, shell, composer);

      composer.addImages([_file], 0);
      calls.single.result.complete(
        const ComposerUploadResult(
          id: 42,
          originalFilename: 'photo.png',
          shortUrl: 'upload://photo',
          url: 'https://meta.discourse.org/uploads/photo.png',
          width: 640,
          height: 480,
        ),
      );
      await tester.pump();

      final image = composer.text.imageBlocks.single;
      final source = composer.text.text;
      expect(
        composer.text.selection,
        TextSelection.collapsed(offset: image.end),
      );
      expect(composer.text.keyboardSelectedImage, isNull);
      expect(find.byTooltip('Save alt text'), findsNothing);
      expect(
        tester
            .widget<ComposerImagePreview>(find.byType(ComposerImagePreview))
            .highlighted,
        isFalse,
      );

      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      expect(composer.text.text, source);
      expect(
        composer.text.selection,
        TextSelection.collapsed(offset: image.end),
      );
      expect(composer.text.keyboardSelectedImage, isNotNull);
      expect(find.byType(ComposerImagePreview), findsOneWidget);
      expect(
        tester
            .widget<ComposerImagePreview>(find.byType(ComposerImagePreview))
            .highlighted,
        isTrue,
      );
      expect(_composerEditable(tester).showCursor, isFalse);
      expect(find.byTooltip('Decrease image size'), findsOneWidget);
      expect(find.byTooltip('Increase image size'), findsOneWidget);
      expect(find.byTooltip('Save alt text'), findsOneWidget);
      expect(
        tester.getSize(find.byTooltip('Save alt text')),
        const Size.square(44),
      );
    });

    testWidgets('escape unselects an upload before closing the composer', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        onSaveDraft: (save) async => save.sequence + 1,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _InteractionTrackingShellController.create();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text = '![old|640x480](upload://photo)';
      await _pumpPanel(tester, shell, composer);

      final image = composer.text.imageBlocks.single;
      composer.text.selection = TextSelection.collapsed(offset: image.end);
      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      expect(composer.text.keyboardSelectedImage, isNotNull);
      expect(find.byTooltip('Save alt text'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(composer.text.keyboardSelectedImage, isNull);
      expect(find.byTooltip('Save alt text'), findsNothing);
      expect(find.byKey(const ValueKey('composer-frame')), findsOneWidget);
      expect(shell.closeCalls, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(shell.closeCalls, 1);
      composer.draftSettled();
    });

    testWidgets('selecting a projected image shows its editing controls', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text = '![old|640x480](upload://photo)';
      await _pumpPanel(tester, shell, composer);

      expect(find.byType(ComposerImagePreview), findsOneWidget);
      final previewRect = tester.getRect(find.byType(ComposerImagePreview));
      final editorRect = tester.getRect(find.byType(EditableText));
      expect(previewRect.top, greaterThanOrEqualTo(editorRect.top));
      Future<void> tapPreview({bool redrawBeforeUp = false}) async {
        final position =
            tester.getTopLeft(find.byType(ComposerImagePreview)) +
            const Offset(8, 8);
        final gesture = await tester.startGesture(position);
        if (redrawBeforeUp) {
          final image = composer.text.imageBlocks.single;
          composer.text.selection = TextSelection.collapsed(
            offset: image.start + 1,
          );
          await tester.pump();
          expect(find.byType(ComposerImagePreview), findsOneWidget);
        }
        await gesture.up();
      }

      await tapPreview(redrawBeforeUp: true);
      await tester.pump();
      await tester.pump();

      final image = composer.text.imageBlocks.single;
      expect(
        composer.text.selection,
        TextSelection.collapsed(offset: image.end),
      );
      expect(composer.text.keyboardSelectedImage, isNotNull);
      expect(
        tester
            .widget<ComposerImagePreview>(find.byType(ComposerImagePreview))
            .highlighted,
        isTrue,
      );
      expect(find.byTooltip('Decrease image size'), findsOneWidget);
      expect(find.byTooltip('Increase image size'), findsOneWidget);
      expect(find.byTooltip('Delete image'), findsOneWidget);
      expect(find.byTooltip('Save alt text'), findsOneWidget);
      composer.text.selection = TextSelection.collapsed(offset: image.end - 1);
      await tester.pump();
      expect(find.byType(ComposerImagePreview), findsOneWidget);
      final altField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Add image description',
      );
      await tester.enterText(altField, 'draft alt');

      await tester.tap(find.byTooltip('Decrease image size'));
      await tester.pump();
      await tester.pump();
      expect(composer.text.text, '![old|640x480, 75%](upload://photo)');
      expect(composer.text.keyboardSelectedImage, isNotNull);
      expect(
        tester
            .widget<ComposerImagePreview>(find.byType(ComposerImagePreview))
            .highlighted,
        isTrue,
      );
      expect(find.byTooltip('Save alt text'), findsOneWidget);
      expect(tester.widget<TextField>(altField).controller!.text, 'draft alt');

      await tester.tap(find.byTooltip('Decrease image size'));
      await tester.pump();
      await tester.pump();
      expect(composer.text.text, '![old|640x480, 50%](upload://photo)');
      expect(composer.text.keyboardSelectedImage, isNotNull);
      expect(find.byTooltip('Save alt text'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(composer.text.keyboardSelectedImage, isNull);
      expect(_composerEditable(tester).showCursor, isTrue);
      expect(find.byTooltip('Save alt text'), findsNothing);

      final resizedImage = composer.text.imageBlocks.single;
      composer.text.selection = TextSelection.collapsed(
        offset: resizedImage.start,
      );
      composer.focus.requestFocus();
      await tester.pump();
      expect(
        tester
            .widget<ComposerImagePreview>(find.byType(ComposerImagePreview))
            .highlighted,
        isFalse,
      );
      expect(find.byTooltip('Save alt text'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(composer.text.selection.extentOffset, resizedImage.start);
      expect(find.byTooltip('Save alt text'), findsOneWidget);
      expect(
        tester
            .widget<ComposerImagePreview>(find.byType(ComposerImagePreview))
            .highlighted,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(composer.text.selection.extentOffset, resizedImage.end);
      expect(composer.text.keyboardSelectedImage, isNull);
      expect(find.byTooltip('Save alt text'), findsNothing);
      expect(
        tester
            .widget<ComposerImagePreview>(find.byType(ComposerImagePreview))
            .highlighted,
        isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(composer.text.keyboardSelectedImage, isNotNull);
      expect(find.byTooltip('Save alt text'), findsOneWidget);
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'Add image description',
        ),
        'new [alt]',
      );
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Save alt text'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed!();
      await tester.pump();
      expect(
        composer.text.text,
        r'![new \[alt\]|640x480, 50%](upload://photo)',
      );

      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(composer.text.text, isEmpty);
    });

    testWidgets('an image taller than the editor scrolls inside it', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text = '![tall|640x480](upload://photo)';
      await _pumpPanel(tester, shell, composer);
      await tester.pumpAndSettle();

      final editor = find.byType(EditableText);
      final scrollable = find.descendant(
        of: editor,
        matching: find.byType(Scrollable),
      );
      final scrollState = tester.state<ScrollableState>(scrollable);
      expect(scrollState.position.maxScrollExtent, greaterThan(0));
      scrollState.position.jumpTo(0);
      await tester.pump();

      final preview = find.byType(ComposerImagePreview);
      final oldTop = tester.getTopLeft(preview).dy;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getRect(find.byType(TextField)).center,
          scrollDelta: const Offset(0, 80),
        ),
      );
      await tester.pumpAndSettle();

      expect(scrollState.position.pixels, greaterThan(0));
      expect(tester.getTopLeft(preview).dy, lessThan(oldTop));
    });
  });

  group('gallery editing', () {
    testWidgets('gallery and member toolbars edit mode and membership', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text =
          '[grid]\n'
          '![one|640x480](upload://one)\n'
          '![two|640x480](upload://two)\n'
          '[/grid]';
      composer.text.selection = const TextSelection.collapsed(offset: 0);
      await _pumpPanel(tester, shell, composer);
      await tester.pumpAndSettle();

      final preview = find.byType(ComposerImageGalleryPreview);
      expect(preview, findsOneWidget);
      final parsedGallery = composer.text.galleryBlocks.single;
      final projectedRect = composer.text.collapsedGalleryGlobalRect(
        parsedGallery,
      )!;
      final galleryTap = Offset(projectedRect.right - 8, projectedRect.top + 8);
      expect(
        tester.getRect(find.byType(EditableText)).contains(galleryTap),
        isTrue,
        reason: 'the gallery control should be inside the editor viewport',
      );
      expect(
        projectedRect.contains(galleryTap),
        isTrue,
        reason: 'the visible gallery control should be hit-testable',
      );
      expect(
        composer.text.collapsedGalleryAtGlobalPosition(galleryTap),
        isNotNull,
      );
      await tester.tapAt(galleryTap);
      await tester.pump();
      await tester.pump();

      expect(
        composer.text.selection.extentOffset,
        composer.text.galleryBlocks.single.end,
        reason: 'a gallery background tap should select the gallery',
      );
      expect(
        composer.text.collapsedGalleryGlobalRect(
          composer.text.galleryBlocks.single,
        ),
        isNotNull,
      );
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsOneWidget,
      );
      expect(
        tester.widget<ComposerImageGalleryPreview>(preview).highlighted,
        isTrue,
      );
      expect(find.byTooltip('Add images to gallery'), findsOneWidget);
      expect(find.byTooltip('Remove gallery, keep images'), findsOneWidget);
      expect(find.byTooltip('Close gallery controls'), findsNothing);
      await tester.tap(find.byTooltip('Carousel gallery mode'));
      await tester.pump();
      expect(composer.text.text, contains('[grid mode=carousel]'));
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsOneWidget,
      );

      final currentGallery = parseComposerImageGalleries(
        composer.text.text,
      ).single;
      final firstImageRect = composer.text.collapsedImageGlobalRect(
        currentGallery.images.first,
      )!;
      final imageTap = Offset(
        firstImageRect.center.dx,
        firstImageRect.top + 22,
      );
      expect(composer.text.collapsedImageAtGlobalPosition(imageTap), isNotNull);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('composer-gallery-toolbar')))
            .contains(imageTap),
        isFalse,
        reason: 'an image member must retain a 44px interaction target',
      );
      await tester.tapAt(imageTap);
      await tester.pump();
      await tester.pump();
      expect(composer.text.keyboardSelectedImage?.url, 'upload://one');
      expect(
        tester.widget<ComposerImageGalleryPreview>(preview).highlighted,
        isFalse,
      );
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsNothing,
      );
      expect(find.byTooltip('Move image outside gallery'), findsOneWidget);
      expect(find.byTooltip('Delete image'), findsOneWidget);
      expect(find.byTooltip('Decrease image size'), findsNothing);

      await tester.tap(find.byTooltip('Move image outside gallery'));
      await tester.pump();
      final gallery = parseComposerImageGalleries(composer.text.text).single;
      expect(gallery.images.single.url, 'upload://two');
      expect(composer.standaloneImages.single.url, 'upload://one');

      final remainingRect = composer.text.collapsedImageGlobalRect(
        gallery.images.single,
      )!;
      await tester.tapAt(remainingRect.center);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Delete image'));
      await tester.pump();
      expect(composer.text.galleryBlocks, isEmpty);
      expect(composer.text.imageBlocks.map((image) => image.url), [
        'upload://one',
      ]);
    });

    testWidgets('gallery toolbar fits its controls in a narrow composer', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        addTearDown(tester.view.resetPhysicalSize);
        final pixelRatio = tester.view.devicePixelRatio;
        tester.view.physicalSize = Size(280 * pixelRatio, 700 * pixelRatio);
        final composer = ComposerController(
          _target,
          resolveUploadUrls: (_) async => const {},
        );
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        composer.text.value = const TextEditingValue(
          text:
              '[grid]\n'
              '![one](upload://one)\n'
              '![two](upload://two)\n'
              '![three](upload://three)\n'
              '[/grid]',
          selection: TextSelection.collapsed(offset: 0),
        );

        await _pumpPanel(tester, shell, composer);
        await tester.pumpAndSettle();
        final editableRect = tester.getRect(find.byType(EditableText));
        final previewRect = tester.getRect(
          find.byType(ComposerImageGalleryPreview),
        );
        expect(previewRect.left, greaterThanOrEqualTo(editableRect.left));
        expect(previewRect.right, lessThanOrEqualTo(editableRect.right));
        await tester.tapAt(Offset(previewRect.right - 8, previewRect.top + 8));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final toolbar = find.byKey(const ValueKey('composer-gallery-toolbar'));
        expect(toolbar, findsOneWidget);
        final toolbarRect = tester.getRect(toolbar);
        expect(toolbarRect.size, const Size(44 * 4, 44));
        final viewport = Rect.fromLTWH(
          0,
          0,
          tester.view.physicalSize.width / pixelRatio,
          tester.view.physicalSize.height / pixelRatio,
        );
        expect(viewport.contains(toolbarRect.topLeft), isTrue);
        expect(viewport.contains(toolbarRect.bottomRight), isTrue);

        final iconButtons = find.descendant(
          of: toolbar,
          matching: find.byType(IconButton),
        );
        expect(iconButtons, findsNWidgets(4));
        for (final button in iconButtons.evaluate()) {
          final size = tester.getSize(find.byWidget(button.widget));
          final tooltip = (button.widget as IconButton).tooltip;
          expect(size.width, greaterThanOrEqualTo(44), reason: tooltip);
          expect(size.height, greaterThanOrEqualTo(44), reason: tooltip);
        }

        Finder modeButton(String tooltip) => find
            .ancestor(
              of: find.byTooltip(tooltip),
              matching: find.byType(IconButton),
            )
            .first;
        expect(
          tester.getSemantics(modeButton('Grid gallery mode')),
          isSemantics(
            tooltip: 'Grid gallery mode',
            isButton: true,
            hasSelectedState: true,
            isSelected: true,
          ),
        );
        expect(
          tester.getSemantics(modeButton('Carousel gallery mode')),
          isSemantics(
            tooltip: 'Carousel gallery mode',
            isButton: true,
            hasSelectedState: true,
            isSelected: false,
          ),
        );
        await tester.tap(find.byTooltip('Carousel gallery mode'));
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(modeButton('Grid gallery mode')),
          isSemantics(hasSelectedState: true, isSelected: false),
        );
        expect(
          tester.getSemantics(modeButton('Carousel gallery mode')),
          isSemantics(hasSelectedState: true, isSelected: true),
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('gallery tiles can be reordered by drag and drop', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text =
          '[grid]\n'
          '![one](upload://one)\n'
          '![two](upload://two)\n'
          '![three](upload://three)\n'
          '[/grid]';

      await _pumpPanel(tester, shell, composer);
      await tester.pumpAndSettle();

      final tiles = find.byType(ComposerImageGalleryTile);
      final first = tester.getCenter(tiles.at(0));
      final last = tester.getCenter(tiles.at(2));
      final drag = await tester.startGesture(
        first,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      for (var step = 1; step <= 10; step++) {
        await drag.moveTo(Offset.lerp(first, last, step / 10)!);
        if (step == 3) {
          final draggedImage = composer.text.galleryBlocks.single.images.first;
          composer.text.selection = TextSelection.collapsed(
            offset: draggedImage.start + 1,
          );
        }
        await tester.pump();
        expect(
          find.byType(ComposerImageGalleryPreview),
          findsOneWidget,
          reason: 'reordering must not expose the gallery Markdown',
        );
      }

      await drag.up();
      await tester.pumpAndSettle();

      expect(
        parseComposerImageGalleries(
          composer.text.text,
        ).single.images.map((image) => image.url),
        ['upload://two', 'upload://three', 'upload://one'],
      );
    });

    testWidgets('a cancelled gallery reorder keeps the gallery projected', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text =
          '[grid]\n'
          '![one](upload://one)\n'
          '![two](upload://two)\n'
          '[/grid]';

      await _pumpPanel(tester, shell, composer);
      await tester.pumpAndSettle();

      final source = composer.text.text;
      final first = tester.getCenter(
        find.byType(ComposerImageGalleryTile).first,
      );
      final outsideTarget = tester.getCenter(
        find.byType(ComposerImageGalleryControl),
      );
      final drag = await tester.startGesture(
        first,
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveTo(outsideTarget);
      final draggedImage = composer.text.galleryBlocks.single.images.first;
      composer.text.selection = TextSelection.collapsed(
        offset: draggedImage.start + 1,
      );
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      expect(composer.text.text, source);
      expect(find.byType(ComposerImageGalleryPreview), findsOneWidget);
    });

    testWidgets('a gallery can import multiple standalone draft images', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text =
          '![outside one](upload://outside-one)\n'
          '![outside two](upload://outside-two)\n'
          '[grid]\n'
          '![inside](upload://inside)\n'
          '[/grid]';
      composer.text.selection = TextSelection.collapsed(
        offset: parseComposerImageGalleries(composer.text.text).single.end,
      );
      await _pumpPanel(tester, shell, composer);
      await tester.pumpAndSettle();

      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Add images to gallery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add existing draft images'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CheckboxListTile).at(0));
      await tester.tap(find.byType(CheckboxListTile).at(1));
      await tester.pump();
      await tester.tap(find.text('Add selected'));
      await tester.pumpAndSettle();

      final gallery = parseComposerImageGalleries(composer.text.text).single;
      expect(gallery.images.map((image) => image.url), [
        'upload://inside',
        'upload://outside-one',
        'upload://outside-two',
      ]);
      expect(composer.standaloneImages, isEmpty);
    });

    testWidgets('removing a gallery keeps its images in order', (tester) async {
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text =
          '[grid]\n'
          '![one](upload://one)\n'
          '![two](upload://two)\n'
          '[/grid]';
      composer.text.selection = TextSelection.collapsed(
        offset: composer.text.galleryBlocks.single.end,
      );
      await _pumpPanel(tester, shell, composer);
      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      await tester.tap(find.byTooltip('Remove gallery, keep images'));
      await tester.pump();

      expect(composer.text.galleryBlocks, isEmpty);
      expect(composer.text.imageBlocks.map((image) => image.url), [
        'upload://one',
        'upload://two',
      ]);
      expect(composer.text.text, isNot(contains('[grid')));
    });

    testWidgets('gallery controls survive changes while its picker is open', (
      tester,
    ) async {
      final picker = Completer<List<ComposerUploadFile>>();
      final calls = <_PanelUploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: (file, {required onProgress, required abortTrigger}) {
          final call = _PanelUploadCall(onProgress);
          calls.add(call);
          return call.result.future;
        },
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text =
          '[grid]\n'
          '![inside](upload://inside)\n'
          '[/grid]';
      composer.text.selection = TextSelection.collapsed(
        offset: composer.text.galleryBlocks.single.end,
      );
      await _pumpPanel(
        tester,
        shell,
        composer,
        pickImages: () => picker.future,
      );
      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      await tester.tap(find.byTooltip('Add images to gallery'));
      await tester.pumpAndSettle();
      final editorField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller == composer.text,
      );
      final fieldBeforePicker = tester.widget<TextField>(editorField);
      await tester.tap(find.text('Upload new images'));
      await tester.pump();
      expect(
        tester.widget<TextField>(editorField),
        same(fieldBeforePicker),
        reason: 'picker progress should rebuild only the media overlay',
      );

      final captured = composer.text.galleryBlocks.single;
      composer.setGalleryMode(captured, ComposerGalleryMode.carousel);
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is IconButton &&
              widget.tooltip == 'Carousel gallery mode' &&
              widget.isSelected == true,
        ),
        findsOneWidget,
      );

      picker.complete([_file]);
      await tester.pump();
      expect(calls, hasLength(1));
      calls.single.result.complete(
        const ComposerUploadResult(
          id: 73,
          originalFilename: 'photo.png',
          shortUrl: 'upload://picked',
          url: 'https://meta.discourse.org/uploads/picked.png',
          width: 640,
          height: 480,
        ),
      );
      await tester.pump();
      await tester.pump();

      final gallery = composer.text.galleryBlocks.single;
      expect(gallery.mode, ComposerGalleryMode.carousel);
      expect(gallery.images.map((image) => image.url), [
        'upload://inside',
        'upload://picked',
      ]);
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsOneWidget,
      );
    });

    testWidgets(
      'a late gallery picker cannot upload into a replacement composer',
      (tester) async {
        final picker = Completer<List<ComposerUploadFile>>();
        final originalCalls = <_PanelUploadCall>[];
        final replacementCalls = <_PanelUploadCall>[];
        final original = ComposerController(
          _target,
          imageUploader: (file, {required onProgress, required abortTrigger}) {
            final call = _PanelUploadCall(onProgress);
            originalCalls.add(call);
            return call.result.future;
          },
        )..text.text = '[grid]\n![inside](upload://inside)\n[/grid]';
        final replacement = ComposerController(
          _target,
          imageUploader: (file, {required onProgress, required abortTrigger}) {
            final call = _PanelUploadCall(onProgress);
            replacementCalls.add(call);
            return call.result.future;
          },
        )..text.text = 'Replacement draft';
        final shell = await _shell();
        addTearDown(original.dispose);
        addTearDown(replacement.dispose);
        addTearDown(shell.dispose);
        original.text.selection = TextSelection.collapsed(
          offset: original.text.galleryBlocks.single.end,
        );
        await _pumpPanel(
          tester,
          shell,
          original,
          pickImages: () => picker.future,
        );
        original.focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        await tester.tap(find.byTooltip('Add images to gallery'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Upload new images'));
        await tester.pump();
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is PopupMenuButton &&
                widget.tooltip == 'Add images to gallery' &&
                !widget.enabled,
          ),
          findsOneWidget,
        );

        await _pumpPanel(tester, shell, replacement);
        picker.complete([_file]);
        await tester.pump();

        expect(originalCalls, isEmpty);
        expect(replacementCalls, isEmpty);
        expect(replacement.text.text, 'Replacement draft');
        expect(
          find.byKey(const ValueKey('composer-gallery-toolbar')),
          findsNothing,
        );
      },
    );

    testWidgets('Ctrl+Enter submits while gallery controls are selected', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        onSaveDraft: (save) async => save.sequence + 1,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _InteractionTrackingShellController.create();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text =
          '[grid]\n'
          '![inside](upload://inside)\n'
          '[/grid]';
      composer.text.selection = TextSelection.collapsed(
        offset: composer.text.galleryBlocks.single.end,
      );
      await _pumpPanel(tester, shell, composer);
      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsOneWidget,
      );

      final selectedValue = composer.text.value;
      final caret = selectedValue.selection.extentOffset;
      tester.testTextInput.updateEditingValue(
        selectedValue.copyWith(
          text: selectedValue.text.replaceRange(caret, caret, 'pasted text'),
          selection: TextSelection.collapsed(
            offset: caret + 'pasted text'.length,
          ),
        ),
      );
      await tester.pump();
      expect(composer.text.value, selectedValue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(shell.submitCalls, 1);
      expect(composer.text.galleryBlocks, hasLength(1));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsNothing,
      );
      expect(shell.closeCalls, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(shell.closeCalls, 1);
      composer.draftSettled();
    });

    testWidgets('dropping an image over a gallery appends it there', (
      tester,
    ) async {
      final calls = <_PanelUploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: (file, {required onProgress, required abortTrigger}) {
          final call = _PanelUploadCall(onProgress);
          calls.add(call);
          return call.result.future;
        },
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text =
          '[grid]\n'
          '![inside](upload://inside)\n'
          '[/grid]';
      await _pumpPanel(tester, shell, composer);
      await tester.pumpAndSettle();

      final position = tester
          .getRect(find.byType(ComposerImageGalleryControl))
          .center;
      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
      dropTarget.onDragEntered!(
        DropEventDetails(localPosition: position, globalPosition: position),
      );
      await tester.pump();
      expect(find.text('Drop images into this gallery'), findsOneWidget);

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
      expect(calls, hasLength(1));
      calls.single.result.complete(
        const ComposerUploadResult(
          id: 74,
          originalFilename: 'dropped.png',
          shortUrl: 'upload://dropped',
          url: 'https://meta.discourse.org/uploads/dropped.png',
          width: 640,
          height: 480,
        ),
      );
      await tester.pump();

      expect(
        composer.text.galleryBlocks.single.images.map((image) => image.url),
        ['upload://inside', 'upload://dropped'],
      );
      expect(composer.standaloneImages, isEmpty);
    });
  });
}

Future<ShellController> _shell() async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  return shell;
}

Future<void> _pumpPanel(
  WidgetTester tester,
  ShellController shell,
  ComposerController composer, {
  ComposerImagePicker pickImages = _cancelImagePick,
  ComposerClipboardImageReader readClipboardImages =
      readComposerClipboardImages,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.dark,
    home: ShellScope(
      controller: shell,
      child: Scaffold(
        body: ComposerPanel(
          composer: composer,
          pickImages: pickImages,
          readClipboardImages: readClipboardImages,
        ),
      ),
    ),
  ),
);

Future<List<ComposerUploadFile>> _cancelImagePick() async => const [];

Future<void> _pasteShortcut(WidgetTester tester) async {
  final modifier = switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => LogicalKeyboardKey.metaLeft,
    _ => LogicalKeyboardKey.controlLeft,
  };
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

EditableText _composerEditable(WidgetTester tester) =>
    tester.widget<EditableText>(
      find.descendant(
        of: find.byType(ComposerEditor),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is EditableText &&
              widget.controller is MarkdownEditingController,
        ),
      ),
    );

const _target = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 7,
  slug: 'a-topic',
  topicTitle: 'A topic',
);

final _file = ComposerUploadFile(
  name: 'photo.png',
  length: () => Future.value(3),
  openRead: () => Stream.value([1, 2, 3]),
);

class _PanelUploadCall {
  _PanelUploadCall(this.onProgress);

  final void Function(double) onProgress;
  final Completer<ComposerUploadResult> result = Completer();
}

final class _InteractionTrackingShellController extends ShellController {
  _InteractionTrackingShellController()
    : super(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );

  int closeCalls = 0;
  int submitCalls = 0;

  static Future<_InteractionTrackingShellController> create() async {
    final shell = _InteractionTrackingShellController();
    await shell.load();
    return shell;
  }

  @override
  void closeComposer() => closeCalls++;

  @override
  Future<bool> finishComposerDraftRestore(ComposerController composer) async =>
      true;

  @override
  Future<void> submitComposer() async => submitCalls++;
}
