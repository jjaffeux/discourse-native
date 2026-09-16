import 'dart:typed_data';

import 'package:discourse_native/src/shell/composer_upload_picker.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('native pickers', () {
    late FileSelectorPlatform previous;
    late _FileSelector selector;

    setUp(() {
      previous = FileSelectorPlatform.instance;
      selector = _FileSelector();
      FileSelectorPlatform.instance = selector;
    });
    tearDown(() => FileSelectorPlatform.instance = previous);

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

    test('gallery selection remains limited to images', () async {
      await pickComposerImages();

      final types = selector.acceptedTypeGroups!.single;
      expect(types.extensions, contains('png'));
      expect(types.extensions, isNot(contains('pdf')));
      expect(types.uniformTypeIdentifiers, ['public.image']);
      expect(types.mimeTypes, ['image/*']);
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
