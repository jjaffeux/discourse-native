import 'dart:typed_data';

import 'package:discourse_native/src/shell/composer_upload_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
