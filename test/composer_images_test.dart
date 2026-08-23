import 'dart:convert';
import 'dart:math';

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

  test('a comma-scale suffix only counts after explicit dimensions', () {
    // Discourse only reads ", N%" after "|WxH"; without dimensions the
    // suffix is the author's alt text and must survive a round trip.
    const bare = '![photo, 50%](upload://x)';
    final image = parseComposerImages(bare).single;
    expect(image.alt, 'photo, 50%');
    expect((image.width, image.height, image.scale), (null, null, null));
    expect(image.toMarkdown(), bare);

    final sized = parseComposerImages(
      '![photo|690x388, 50%](upload://x)',
    ).single;
    expect(sized.alt, 'photo');
    expect((sized.width, sized.height, sized.scale), (690, 388, 50));
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

  test('an alt is written so that it parses back, whatever it contains', () {
    // The alt is the one part of an image the app does not choose: it comes
    // from a filename, a GIF's title, or what somebody typed into the image
    // editor. Two of the characters that can appear there have no spelling
    // inside an alt — a `|` opens the `|WxH` suffix, so everything after it
    // is read as dimensions and the rest of the alt is lost, and a line
    // ending stops the markdown being an image at all. `flattenImageAlt`
    // takes those out; everything else is escaped and survives.
    //
    // Stated as: writing an alt always produces something that parses, and
    // parsing it and writing it again says exactly the same thing.
    const pieces = [
      r'\',
      '[',
      ']',
      '|',
      'a',
      'b',
      ' ',
      '.',
      '(',
      ')',
      '!',
      '\u{1F600}',
      '\u{00e9}',
      '"',
      "'",
      '*',
      '#',
      '\n',
      '\r',
      ', 50%',
      'x',
    ];
    final random = Random(555);
    final base = parseComposerImages('![x|10x20](upload://abc)').single;
    var flattened = 0;

    for (var round = 0; round < 20000; round++) {
      final buffer = StringBuffer();
      for (var piece = 0; piece < 1 + random.nextInt(8); piece++) {
        buffer.write(pieces[random.nextInt(pieces.length)]);
      }
      final alt = buffer.toString();
      if (flattenImageAlt(alt) != alt) flattened++;

      final markdown = base.toMarkdown(alt: alt);
      final blocks = parseComposerImages(markdown);
      expect(
        blocks,
        hasLength(1),
        reason: '${jsonEncode(alt)} wrote ${jsonEncode(markdown)}',
      );
      expect(
        blocks.single.toMarkdown(),
        markdown,
        reason: 'writing ${jsonEncode(markdown)} again changed it',
      );
    }

    // A corpus of alts that never needed flattening would pass while testing
    // only the escaping. The seed is fixed, so this is not a race.
    expect(flattened, greaterThan(1000));
  });

  test(
    'a backtick in an alt is escaped, and the scan does not read it yet',
    () {
      // Backticks are escaped because Discourse needs them escaped: a bare one
      // in an alt opens a code span in the cooked post. `scanMarkdown` does not
      // honour backslash escapes when it looks for inline code, though, so a
      // pair of them still reads as code here and the image keeps its raw
      // markdown instead of collapsing to a preview.
      //
      // A divergence from CommonMark rather than a lost image — the site cooks
      // it correctly either way — and closing it means teaching escapes to the
      // one pattern on the composer's per-keystroke path that is still a
      // pattern. Written down rather than fixed.
      final base = parseComposerImages('![x|10x20](upload://abc)').single;
      final markdown = base.toMarkdown(alt: 'a `b` c');

      expect(markdown, r'![a \`b\` c|10x20](upload://abc)');
      expect(parseComposerImages(markdown), isEmpty);
    },
  );

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

  test('an escaped alt cannot be read two ways', () {
    // `\\.` and the alt class both used to accept a backslash, so a run of
    // them had one parse per backslash and the engine tried every one before
    // an alt with no `](` after it could fail. Forty backslashes took minutes,
    // in a scan the composer runs on every keystroke.
    final elapsed = Stopwatch()..start();
    expect(parseComposerImages('![${'\\' * 60} '), isEmpty);
    elapsed.stop();

    expect(elapsed.elapsedMilliseconds, lessThan(500));
  });

  test('a line of openers costs its length, not its square', () {
    // No `]` anywhere on the line, so no image can match — but the pattern
    // walked to the line's end at every `![` before agreeing.
    final small = _bestOf(() => parseComposerImages('![alt ' * 800));
    final large = _bestOf(() => parseComposerImages('![alt ' * 6400));

    expect(
      large,
      lessThan(small * 25),
      reason: 'eight times the openers took ${large / small} times as long',
    );
  });

  test('finds offsets through the complete raw token', () {
    const source = 'x ![photo](upload://abc) y';
    final image = parseComposerImages(source).single;

    expect(imageAtComposerOffset([image], image.start), image);
    expect(imageAtComposerOffset([image], image.end), image);
    expect(imageAtComposerOffset([image], 0), isNull);
  });
}

int _bestOf(void Function() body) {
  var best = -1;
  for (var run = 0; run < 3; run += 1) {
    final elapsed = Stopwatch()..start();
    body();
    elapsed.stop();
    if (best < 0 || elapsed.elapsedMicroseconds < best) {
      best = elapsed.elapsedMicroseconds;
    }
  }
  return best;
}
