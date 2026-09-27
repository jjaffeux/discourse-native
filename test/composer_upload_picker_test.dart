import 'dart:typed_data';

import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/shell/composer_upload_picker.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart'
    as images;

void main() {
  group('native pickers', () {
    late FileSelectorPlatform previous;
    late _FileSelector selector;
    late images.ImagePickerPlatform previousImagePicker;
    late _ImagePicker imagePicker;

    setUp(() {
      previous = FileSelectorPlatform.instance;
      selector = _FileSelector();
      FileSelectorPlatform.instance = selector;
      previousImagePicker = images.ImagePickerPlatform.instance;
      imagePicker = _ImagePicker();
      images.ImagePickerPlatform.instance = imagePicker;
    });
    tearDown(() {
      FileSelectorPlatform.instance = previous;
      images.ImagePickerPlatform.instance = previousImagePicker;
    });

    test('general uploads allow arbitrary native file types', () async {
      selector.files = [
        for (final name in [
          'photo.png',
          'notes.pdf',
          'video.mp4',
          'audio.mp3',
          'archive.tar.gz',
          'data.custom',
          'README',
        ])
          XFile.fromData(Uint8List.fromList([1, 2, 3]), path: name),
      ];

      final files = await pickComposerFiles();

      expect(selector.acceptedTypeGroups, isEmpty);
      expect(selector.confirmButtonText, 'Upload');
      expect(
        files.map((file) => file.name),
        selector.files.map((file) => file.name),
      );
      expect(await files.last.openRead().expand((chunk) => chunk).toList(), [
        1,
        2,
        3,
      ]);
    });

    test('cancelling the file picker returns no uploads', () async {
      expect(await pickComposerFiles(), isEmpty);
    });

    test('only mobile photo JPEGs bypass a second lossy encoding', () async {
      imagePicker.files = [
        for (final name in ['photo.jpg', 'photo.JPEG', 'alpha.png'])
          images.XFile.fromData(Uint8List.fromList([1, 2]), path: name),
      ];
      try {
        for (final platform in [
          TargetPlatform.iOS,
          TargetPlatform.android,
          TargetPlatform.macOS,
          TargetPlatform.linux,
        ]) {
          debugDefaultTargetPlatformOverride = platform;
          final files = await pickComposerImages();
          final mobile =
              platform == TargetPlatform.iOS ||
              platform == TargetPlatform.android;
          expect(files.map((file) => file.imageOptimizationApplied), [
            mobile,
            mobile,
            false,
          ]);
        }
        selector.files = [
          XFile.fromData(Uint8List.fromList([1]), path: 'photo.jpg'),
        ];
        expect(
          (await pickComposerFiles()).single.imageOptimizationApplied,
          isFalse,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test(
      'photo selection uses the native gallery and adapts its files',
      () async {
        imagePicker.files = [
          images.XFile.fromData(Uint8List.fromList([4, 5]), path: 'photo.png'),
        ];

        final files = await pickComposerImages();

        expect(imagePicker.options?.imageOptions.requestFullMetadata, isFalse);
        expect(selector.acceptedTypeGroups, isNull);
        expect(files.single.name, 'photo.png');
        expect(
          await files.single.openRead().expand((chunk) => chunk).toList(),
          [4, 5],
        );
      },
    );

    group('on iOS, where the photo library re-encodes every photo', () {
      setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
      tearDown(() => debugDefaultTargetPlatformOverride = null);

      test('photos leave at core defaults rather than full size', () async {
        await pickComposerImages();

        final options = imagePicker.options!.imageOptions;
        expect(options.maxWidth, 1920);
        expect(options.maxHeight, isNull);
        expect(options.imageQuality, 90);
      });

      test('the site sets the width, quality, and selection limit', () async {
        await pickComposerImages(
          optimization: ComposerImageOptimization.fromJson(const {
            'composer_media_optimization_image_resize_width_target': 1600,
            'composer_media_optimization_image_encode_quality': 80,
            'image_quality': 70,
          }),
          limit: 4,
        );

        final options = imagePicker.options!;
        expect(options.imageOptions.maxWidth, 1600);
        expect(options.imageOptions.imageQuality, 80);
        expect(options.limit, 4);
      });

      test('an unset encode quality falls back to image quality', () async {
        await pickComposerImages(
          optimization: ComposerImageOptimization.fromJson(const {
            'composer_media_optimization_image_encode_quality': 0,
            'image_quality': 70,
          }),
        );

        expect(imagePicker.options!.imageOptions.imageQuality, 70);
      });

      test(
        'a site that does not optimise keeps full size, not maximum quality',
        () async {
          for (final settings in [
            {'composer_media_optimization_image_enabled': false},
            {'composer_ios_media_optimisation_image_enabled': false},
          ]) {
            await pickComposerImages(
              optimization: ComposerImageOptimization.fromJson(settings),
            );

            final options = imagePicker.options!.imageOptions;
            expect(options.maxWidth, isNull, reason: '$settings');
            expect(options.imageQuality, 90, reason: '$settings');
          }
        },
      );

      test('a composer without a batch limit leaves selection open', () async {
        await pickComposerImages(limit: 0);

        expect(imagePicker.options!.limit, isNull);
      });
    });
  });

  test('adapts selected native file streams', () async {
    final selected = XFile.fromData(
      Uint8List.fromList([1, 2, 3]),
      path: 'photo.png',
    );

    final files = composerUploadFilesFromSelection([selected]);

    expect(files.single.name, 'photo.png');
    expect(await files.single.length(), 3);
    expect(await files.single.openRead().expand((chunk) => chunk).toList(), [
      1,
      2,
      3,
    ]);
  });
}

final class _ImagePicker extends images.ImagePickerPlatform {
  List<images.XFile> files = [];
  images.MultiImagePickerOptions? options;

  @override
  Future<List<images.XFile>> getMultiImageWithOptions({
    images.MultiImagePickerOptions options =
        const images.MultiImagePickerOptions(),
  }) async {
    this.options = options;
    return files;
  }
}

final class _FileSelector extends FileSelectorPlatform {
  List<XFile> files = [];
  List<XTypeGroup>? acceptedTypeGroups;
  String? confirmButtonText;

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    this.acceptedTypeGroups = acceptedTypeGroups;
    this.confirmButtonText = confirmButtonText;
    return files;
  }
}
