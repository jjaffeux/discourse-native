import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer_images.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('writes core upload markdown with sanitized alt and thumbnail size', () {
    const upload = ComposerUploadResult(
      originalFilename: 'a [wide]| photo.png',
      shortUrl: 'upload://abc123',
      url: 'https://example.com/original.png',
      width: 2000,
      height: 1200,
      thumbnailWidth: 690,
      thumbnailHeight: 414,
    );

    expect(
      uploadImageMarkdown(upload),
      '![a wide photo|690x414](upload://abc123)',
    );
  });

  test('falls back to original dimensions and omits absent dimensions', () {
    expect(
      uploadImageMarkdown(
        const ComposerUploadResult(
          originalFilename: 'photo.jpeg',
          shortUrl: 'upload://one',
          url: 'https://example.com/photo.jpeg',
          width: 800,
          height: 600,
        ),
      ),
      '![photo|800x600](upload://one)',
    );
    expect(
      uploadImageMarkdown(
        const ComposerUploadResult(
          originalFilename: 'photo.jpeg',
          shortUrl: 'upload://two',
          url: 'https://example.com/photo.jpeg',
        ),
      ),
      '![photo](upload://two)',
    );
  });

  test('parses upload and remote images with dimensions and scale', () {
    final images = parseComposerImages(
      'before ![an image|800x600, 75%](upload://abc) and '
      '![remote](https://cdn.example/image.png) after',
    );

    expect(images, hasLength(2));
    expect(images.first.alt, 'an image');
    expect(images.first.width, 800);
    expect(images.first.height, 600);
    expect(images.first.scale, 75);
    expect(images.first.url, 'upload://abc');
    expect(images.last.url, 'https://cdn.example/image.png');
  });

  test('keeps only positive dimensions and scales from 1 through 100', () {
    const source =
        'before ![zero|0000x0480, 000%](upload://zero) '
        '![minimum|1x1, 1%](upload://minimum) '
        '![maximum|9999x9999, 100%](upload://maximum) '
        '![too large|640x480, 101%](upload://large) '
        '![hostile|640x480, 999%](upload://hostile) after';
    final images = parseComposerImages(source);

    expect(images, hasLength(5));
    expect(
      (images[0].width, images[0].height, images[0].scale),
      (null, null, null),
    );
    expect((images[1].width, images[1].height, images[1].scale), (1, 1, 1));
    expect(
      (images[2].width, images[2].height, images[2].scale),
      (9999, 9999, 100),
    );
    expect(images[3].scale, isNull);
    expect(images[4].scale, isNull);
    for (final image in images) {
      expect(image.source, source.substring(image.start, image.end));
    }
  });

  test('escaped alt text round trips through serialization', () {
    final image = parseComposerImages(
      r'![a \[label\] and \\ slash|640x480](upload://abc)',
    ).single;

    expect(image.alt, r'a [label] and \ slash');
    expect(
      image.toMarkdown(alt: r'new [alt] \ value'),
      r'![new \[alt\] \\ value|640x480](upload://abc)',
    );
  });

  test('does not project image syntax inside inline or fenced code', () {
    final images = parseComposerImages('''
`![inline](upload://one)`

```
![fenced](upload://two)
```

![visible](upload://three)
''');

    expect(images.map((image) => image.alt), ['visible']);
  });

  test('finds offsets through the complete raw token', () {
    const source = 'x ![photo](upload://abc) y';
    final image = parseComposerImages(source).single;

    expect(imageAtComposerOffset([image], image.start), image);
    expect(imageAtComposerOffset([image], image.end), image);
    expect(imageAtComposerOffset([image], 0), isNull);
  });
}
