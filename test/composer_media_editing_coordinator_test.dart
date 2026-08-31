import 'dart:async';

import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_galleries.dart';
import 'package:discourse_native/src/shell/composer_media_editing_coordinator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ComposerMediaEditingCoordinator', () {
    test(
      'reconciles selected image and gallery identity after text changes',
      () {
        final composer = _composer()
          ..text.text =
              '![outside](upload://outside)\n'
              '[grid]\n'
              '![inside](upload://inside)\n'
              '[/grid]';
        final coordinator = ComposerMediaEditingCoordinator(composer);
        addTearDown(composer.dispose);
        addTearDown(coordinator.dispose);

        final image = composer.standaloneImages.single;
        composer.text.selection = TextSelection.collapsed(offset: image.start);
        coordinator.selectImageForKeyboard(image, moveCaretToEnd: false);
        expect(coordinator.value.selectedImage, isNotNull);
        expect(composer.text.keyboardSelectedImage, isNotNull);

        composer.text.text = 'prefix ${composer.text.text}';

        expect(coordinator.value.selectedImage?.start, image.start + 7);
        expect(coordinator.value.selectedImage?.url, 'upload://outside');
        expect(composer.text.keyboardSelectedImage?.url, 'upload://outside');

        coordinator.dismissImage(requestFocus: false);
        final gallery = composer.text.galleryBlocks.single;
        coordinator.selectGallery(gallery);
        composer.text.text = 'more ${composer.text.text}';

        expect(coordinator.value.selectedGallery?.start, gallery.start + 5);
        expect(
          coordinator.value.selectedGallery?.images.single.url,
          'upload://inside',
        );
        expect(composer.text.selectedProjectionHidesCursor, isTrue);

        coordinator.setSelectedGalleryMode(ComposerGalleryMode.carousel);

        expect(
          coordinator.value.selectedGallery?.mode,
          ComposerGalleryMode.carousel,
        );
        expect(composer.text.text, contains('[grid mode=carousel]'));
      },
    );

    test(
      'late gallery picker completion cannot enter a replacement composer',
      () async {
        final picker = Completer<List<ComposerUploadFile>>();
        var originalUploads = 0;
        var replacementUploads = 0;
        final original = _composer(
          onUpload: () {
            originalUploads++;
            return Completer<ComposerUploadResult>().future;
          },
        )..text.text = '[grid]\n![inside](upload://inside)\n[/grid]';
        final replacement = _composer(
          onUpload: () {
            replacementUploads++;
            return Completer<ComposerUploadResult>().future;
          },
        )..text.text = 'replacement';
        final coordinator = ComposerMediaEditingCoordinator(original);
        addTearDown(original.dispose);
        addTearDown(replacement.dispose);
        addTearDown(coordinator.dispose);
        coordinator.selectGallery(original.text.galleryBlocks.single);

        final operation = coordinator.pickImagesForSelectedGallery(
          () => picker.future,
        );
        expect(coordinator.value.pickingGalleryImages, isTrue);

        coordinator.replaceComposer(replacement);
        picker.complete([_file]);
        await operation;

        expect(coordinator.composer, same(replacement));
        expect(coordinator.value.pickingGalleryImages, isFalse);
        expect(originalUploads, 0);
        expect(replacementUploads, 0);
        expect(replacement.text.text, 'replacement');
      },
    );

    test(
      'late clipboard completion is consumed after composer replacement',
      () async {
        final clipboard = Completer<List<ComposerUploadFile>>();
        var originalUploads = 0;
        var replacementUploads = 0;
        final original = _composer(
          onUpload: () {
            originalUploads++;
            return Completer<ComposerUploadResult>().future;
          },
        );
        final replacement = _composer(
          onUpload: () {
            replacementUploads++;
            return Completer<ComposerUploadResult>().future;
          },
        )..text.text = 'replacement';
        final coordinator = ComposerMediaEditingCoordinator(original);
        addTearDown(original.dispose);
        addTearDown(replacement.dispose);
        addTearDown(coordinator.dispose);

        final operation = coordinator.pasteClipboardImages(
          () => clipboard.future,
        );
        coordinator.replaceComposer(replacement);
        clipboard.complete([_file]);

        expect(await operation, isTrue);
        expect(originalUploads, 0);
        expect(replacementUploads, 0);
        expect(replacement.text.text, 'replacement');
      },
    );

    test(
      'disposal invalidates a pending gallery picker without a binding',
      () async {
        final picker = Completer<List<ComposerUploadFile>>();
        var uploads = 0;
        final composer = _composer(
          onUpload: () {
            uploads++;
            return Completer<ComposerUploadResult>().future;
          },
        )..text.text = '[grid]\n![inside](upload://inside)\n[/grid]';
        final coordinator = ComposerMediaEditingCoordinator(composer);
        addTearDown(composer.dispose);
        addTearDown(coordinator.dispose);
        coordinator.selectGallery(composer.text.galleryBlocks.single);
        final operation = coordinator.pickImagesForSelectedGallery(
          () => picker.future,
        );

        coordinator.dispose();
        picker.complete([_file]);
        await operation;

        expect(uploads, 0);
        expect(composer.uploads, isEmpty);
      },
    );
  });
}

ComposerController _composer({
  Future<ComposerUploadResult> Function()? onUpload,
}) => ComposerController(
  _target,
  imageUploader: onUpload == null
      ? null
      : (_, {required onProgress, required abortTrigger}) => onUpload(),
);

const _target = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 7,
  slug: 'a-topic',
  topicTitle: 'A topic',
);

final _file = ComposerUploadFile(
  name: 'photo.png',
  length: () async => 3,
  openRead: () => Stream.value(const [1, 2, 3]),
);
