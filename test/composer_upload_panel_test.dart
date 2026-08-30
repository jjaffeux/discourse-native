import 'dart:async';

import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_image.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/composer_upload_picker.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
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
    expect(composer.text.selection, TextSelection.collapsed(offset: image.end));
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
    expect(composer.text.selection, TextSelection.collapsed(offset: image.end));
    expect(composer.text.keyboardSelectedImage, isNotNull);
    expect(find.byType(ComposerImagePreview), findsOneWidget);
    expect(
      tester
          .widget<ComposerImagePreview>(find.byType(ComposerImagePreview))
          .highlighted,
      isTrue,
    );
    expect(find.byTooltip('Decrease image size'), findsOneWidget);
    expect(find.byTooltip('Increase image size'), findsOneWidget);
    expect(find.byTooltip('Save alt text'), findsOneWidget);
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
    expect(composer.text.selection, TextSelection.collapsed(offset: image.end));
    expect(composer.text.keyboardSelectedImage, isNotNull);
    expect(
      tester
          .widget<ComposerImagePreview>(find.byType(ComposerImagePreview))
          .highlighted,
      isTrue,
    );
    expect(find.byTooltip('Decrease image size'), findsOneWidget);
    expect(find.byTooltip('Increase image size'), findsOneWidget);
    expect(find.byTooltip('Remove image'), findsNothing);
    expect(find.byTooltip('Save alt text'), findsOneWidget);
    composer.text.selection = TextSelection.collapsed(offset: image.end - 1);
    await tester.pump();
    expect(find.byType(ComposerImagePreview), findsOneWidget);

    await tester.tap(find.byTooltip('Decrease image size'));
    await tester.pump();
    expect(composer.text.text, '![old|640x480, 75%](upload://photo)');

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
    expect(composer.text.text, r'![new \[alt\]|640x480, 75%](upload://photo)');

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
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.dark,
    home: ShellScope(
      controller: shell,
      child: Scaffold(
        body: ComposerPanel(composer: composer, pickImages: pickImages),
      ),
    ),
  ),
);

Future<List<ComposerUploadFile>> _cancelImagePick() async => const [];

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
