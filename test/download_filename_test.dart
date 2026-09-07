import 'dart:convert';

import 'package:discourse_native/src/shell/download_filename.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invalid UTF-8 in a URL cannot prevent using a valid upload title', () {
    expect(
      downloadFilename(
        title: 'Screenshot.png',
        url: 'https://example.com/uploads/%FF.png',
        fallback: 'image',
      ),
      'Screenshot.png',
    );
  });

  test('an undecodable URL filename uses the fallback', () {
    expect(
      downloadFilename(
        title: null,
        url: 'https://example.com/uploads/%FF.png',
        fallback: 'image',
      ),
      'image',
    );
  });

  for (final unit in ['a', 'é', '中', '📷']) {
    test('bounds long $unit filenames without losing their extension', () {
      final title = '${unit * 300}.PNG';
      final filename = downloadFilename(
        title: title,
        url: 'https://example.com/uploads/image.jpg',
        fallback: 'image',
      );

      expect(utf8.encode(filename).length, lessThanOrEqualTo(240));
      expect(filename, endsWith('.PNG'));
      expect(filename.substring(0, filename.length - 4), startsWith(unit));
      expect(utf8.decode(utf8.encode(filename)), filename);
    });
  }

  test('bounds descriptive titles after inheriting the URL extension', () {
    final filename = downloadFilename(
      title: 'Long description ' * 50,
      url: 'https://example.com/uploads/movie.mp4?download=1',
      fallback: 'video',
    );

    expect(utf8.encode(filename).length, lessThanOrEqualTo(240));
    expect(filename, endsWith('.mp4'));
    expect(filename, startsWith('Long description'));
  });
}
