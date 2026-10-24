import 'dart:convert';

import 'package:discourse_native/src/shell/download_filename.dart';
import 'package:flutter_test/flutter_test.dart';

const _images = {'png', 'jpg', 'jpeg'};

void main() {
  test('invalid UTF-8 in a URL cannot prevent using a valid upload title', () {
    expect(
      downloadFilename(
        title: 'Screenshot.png',
        url: 'https://example.com/uploads/%FF.png',
        fallback: 'image',
        mediaExtensions: _images,
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
        mediaExtensions: _images,
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
        mediaExtensions: _images,
      );

      expect(utf8.encode(filename).length, lessThanOrEqualTo(240));
      expect(filename, endsWith('.PNG'));
      expect(filename.substring(0, filename.length - 4), startsWith(unit));
      expect(utf8.decode(utf8.encode(filename)), filename);
    });
  }

  for (final unit in ['a', 'é', '中', '📷']) {
    for (final existingExtension in ['', '.jpg', '.command']) {
      test(
        'bounds a detected extension after $unit titles ending in $existingExtension',
        () {
          final filename = downloadFilename(
            title: '${unit * 300}$existingExtension',
            url: 'https://example.com/image.jpeg',
            fallback: 'image',
            mediaExtensions: _images,
            preferredExtensions: const ['png'],
          );
          expect(utf8.encode(filename).length, lessThanOrEqualTo(240));
          expect(filename, endsWith('.png'));
          expect(filename, startsWith(unit));
          expect(utf8.decode(utf8.encode(filename)), filename);
        },
      );
    }
  }

  test('a known type keeps its filename aliases', () {
    expect(
      downloadFilename(
        title: 'Scan.JPEG',
        url: 'https://example.com/image.png',
        fallback: 'image',
        mediaExtensions: _images,
        preferredExtensions: const ['jpg', 'jpeg'],
      ),
      'Scan.JPEG',
    );
  });

  test('a known type protects Windows device names', () {
    expect(
      downloadFilename(
        title: 'CON.jpg',
        url: 'https://example.com/image.jpg',
        fallback: 'image',
        mediaExtensions: _images,
        preferredExtensions: const ['png'],
      ),
      '_CON.png',
    );
  });

  test('bounds descriptive titles after inheriting the URL extension', () {
    final filename = downloadFilename(
      title: 'Long description ' * 50,
      url: 'https://example.com/uploads/movie.mp4?download=1',
      fallback: 'video',
      mediaExtensions: const {'mp4'},
    );

    expect(utf8.encode(filename).length, lessThanOrEqualTo(240));
    expect(filename, endsWith('.mp4'));
    expect(filename, startsWith('Long description'));
  });

  test('a title keeps only an extension naming its media or the file', () {
    String named(String title, String file) => downloadFilename(
      title: title,
      url: 'https://example.com/uploads/short-url/$file?dl=1',
      fallback: 'image',
      mediaExtensions: _images,
    );

    // The web composer's alt text is the upload's name without extension.
    expect(
      named('Screenshot 2024-01-02 at 10.45.12', 'abc123.png'),
      'Screenshot 2024-01-02 at 10.45.12.png',
    );
    expect(named('Release v2.0', 'abc123.png'), 'Release v2.0.png');
    expect(named('Invoice.command', 'abc123.png'), 'Invoice.command.png');
    expect(named('Scan.JPEG', 'abc123.png'), 'Scan.JPEG');
    expect(named('Scan.jxl', 'abc123.jxl'), 'Scan.jxl');
  });
}
