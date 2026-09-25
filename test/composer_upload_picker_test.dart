import 'dart:typed_data';

import 'package:discourse_native/src/shell/composer_upload_picker.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
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
