import 'dart:math';

import 'package:discourse_native/src/shell/composer_galleries.dart';
import 'package:discourse_native/src/shell/composer_images.dart';
import 'package:discourse_native/src/shell/markdown_highlight.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('gallery parser', () {
    test('retains outer/content offsets, mode, source, and member order', () {
      const source = '''before
[grid mode=carousel]
![one|640x480](upload://one)

![two](https://cdn.example/two.png)
[/grid]
after''';

      final gallery = parseComposerImageGalleries(source).single;

      expect(gallery.start, source.indexOf('[grid'));
      expect(gallery.end, source.indexOf('[/grid]') + '[/grid]'.length);
      expect(gallery.contentStart, source.indexOf(']') + 1);
      expect(gallery.contentEnd, source.indexOf('[/grid]'));
      expect(gallery.source, source.substring(gallery.start, gallery.end));
      expect(gallery.mode, ComposerGalleryMode.carousel);
      expect(gallery.images.map((image) => image.alt), ['one', 'two']);
      expect(
        gallery.images.map((image) => source.substring(image.start, image.end)),
        gallery.images.map((image) => image.source),
      );
    });

    test('accepts default, explicit-grid, one-image, and empty galleries', () {
      const source = '''[grid]
![one](upload://one)
[/grid]
[GRID mode = GRID]	[/GRID]
[grid mode=carousel]
[/grid]''';

      final galleries = parseComposerImageGalleries(source);

      expect(galleries, hasLength(3));
      expect(galleries.map((gallery) => gallery.mode), [
        ComposerGalleryMode.grid,
        ComposerGalleryMode.grid,
        ComposerGalleryMode.carousel,
      ]);
      expect(galleries.map((gallery) => gallery.images.length), [1, 0, 0]);
    });

    test('finds multiple galleries but ignores inline and fenced code', () {
      const source = '''`[grid]![code](upload://one)[/grid]`

```
[grid]
![fenced](upload://two)
[/grid]
```

[grid] ![visible](upload://three) [/grid]

[grid mode=carousel] ![last](upload://four) [/grid]''';
      final code = CodeRanges.of(scanMarkdown(source));

      final direct = parseComposerImageGalleries(source);
      final shared = parseComposerImageGalleries(source, codeRanges: code);

      expect(direct, hasLength(2));
      expect(shared.map((gallery) => gallery.source), [
        direct.first.source,
        direct.last.source,
      ]);
      expect(
        direct.expand((gallery) => gallery.images).map((image) => image.alt),
        ['visible', 'last'],
      );
    });

    test('leaves malformed, nested, and mixed-content grids raw', () {
      const invalid = [
        '[grid]![one](upload://one)',
        '[grid mode=tiles]![one](upload://one)[/grid]',
        '[grid future=true]![one](upload://one)[/grid]',
        '[grid]text ![one](upload://one)[/grid]',
        '[grid]![one](upload://one) * [/grid]',
        '[grid][grid]![one](upload://one)[/grid][/grid]',
        '[grid]![one](upload://one)[grid]![two](upload://two)[/grid][/grid]',
      ];

      for (final source in invalid) {
        expect(parseComposerImageGalleries(source), isEmpty, reason: source);
      }
    });

    test('an unmatched outer opener suppresses ambiguous inner pairs', () {
      const source = '''[grid]
unfinished
[grid]![inner](upload://inner)[/grid]
[grid]![later](upload://later)[/grid]''';

      expect(parseComposerImageGalleries(source), isEmpty);
    });

    test('a long malformed outer opener suppresses inner pairs', () {
      final source =
          '[grid mode=${'x' * 80}]\n'
          '[grid]![inner](upload://inner)[/grid]\n'
          '[/grid]';

      expect(parseComposerImageGalleries(source), isEmpty);
    });

    test('escaped tags and grid-shaped text in an image URL are not tags', () {
      const escaped = r'\[grid]![one](upload://one)\[/grid]';
      expect(parseComposerImageGalleries(escaped), isEmpty);

      const evenBackslashes = r'\\[grid]![one](upload://one)[/grid]';
      expect(parseComposerImageGalleries(evenBackslashes), hasLength(1));

      const source =
          '[grid]![one](https://cdn.example/[grid]/asset.png)[/grid]';
      final gallery = parseComposerImageGalleries(source).single;
      expect(gallery.images.single.url, contains('[grid]'));
    });

    test('looks up offsets through the complete outer token', () {
      const source = 'x [grid]![one](upload://one)[/grid] y';
      final gallery = parseComposerImageGalleries(source).single;

      expect(galleryAtComposerOffset([gallery], gallery.start), gallery);
      expect(galleryAtComposerOffset([gallery], gallery.contentStart), gallery);
      expect(galleryAtComposerOffset([gallery], gallery.end), gallery);
      expect(galleryAtComposerOffset([gallery], 0), isNull);
    });

    test('a long line of malformed openers remains linear', () {
      final small = _bestOf(
        () => parseComposerImageGalleries('[grid mode=' * 1000),
      );
      final large = _bestOf(
        () => parseComposerImageGalleries('[grid mode=' * 8000),
      );

      expect(
        large,
        lessThan(small * 30),
        reason: 'eight times the input took ${large / max(1, small)} times',
      );
    });
  });

  group('gallery raw transformations', () {
    test('wraps a whitespace-separated run in source order', () {
      const source =
          'before ![one](upload://one)\n\n![two](upload://two) after';
      final images = parseComposerImages(source);

      final result = wrapComposerImagesInGallery(source, images.reversed);

      expect(
        result,
        'before [grid]\n'
        '![one](upload://one)\n'
        '![two](upload://two)\n'
        '[/grid] after',
      );
      expect(
        parseComposerImageGalleries(
          result!,
        ).single.images.map((image) => image.alt),
        ['one', 'two'],
      );
    });

    test('does not wrap across prose or inside an existing gallery', () {
      const mixed = '![one](upload://one) words ![two](upload://two)';
      expect(
        wrapComposerImagesInGallery(mixed, parseComposerImages(mixed)),
        isNull,
      );

      const nested =
          '[grid]\n![one](upload://one)\n![two](upload://two)\n[/grid]';
      expect(
        wrapComposerImagesInGallery(nested, parseComposerImages(nested)),
        isNull,
      );
    });

    test('sets mode without rewriting member whitespace', () {
      const source = 'before [grid]\n\n![one](upload://one)  \n[/grid] after';
      final gallery = parseComposerImageGalleries(source).single;

      final carousel = setComposerImageGalleryMode(
        source,
        gallery,
        ComposerGalleryMode.carousel,
      )!;

      expect(
        carousel,
        'before [grid mode=carousel]\n\n'
        '![one](upload://one)  \n[/grid] after',
      );
      final updated = parseComposerImageGalleries(carousel).single;
      expect(
        setComposerImageGalleryMode(
          carousel,
          updated,
          ComposerGalleryMode.carousel,
        ),
        carousel,
      );
    });

    test('unwraps all members and removes an empty wrapper', () {
      const source =
          'x [grid]\n![one](upload://one)\n![two](upload://two)\n[/grid] y';
      final gallery = parseComposerImageGalleries(source).single;
      expect(
        unwrapComposerImageGallery(source, gallery),
        'x ![one](upload://one)\n![two](upload://two) y',
      );

      const empty = 'x [grid]\n\n[/grid] y';
      expect(
        unwrapComposerImageGallery(
          empty,
          parseComposerImageGalleries(empty).single,
        ),
        'x  y',
      );
    });

    test('appends an image to nonempty and empty galleries', () {
      const source = '[grid]\n![one](upload://one)\n[/grid]';
      final appended = appendComposerImageToGallery(
        source,
        parseComposerImageGalleries(source).single,
        '![two](upload://two)',
      )!;
      expect(
        appended,
        '[grid]\n![one](upload://one)\n![two](upload://two)\n[/grid]',
      );

      const empty = '[grid mode=carousel]\n[/grid]';
      expect(
        appendComposerImageToGallery(
          empty,
          parseComposerImageGalleries(empty).single,
          '![one](upload://one)',
        ),
        '[grid mode=carousel]\n![one](upload://one)\n[/grid]',
      );
      expect(
        appendComposerImageToGallery(
          source,
          parseComposerImageGalleries(source).single,
          'words ![two](upload://two)',
        ),
        isNull,
      );
    });

    test('moves adjacent images in while preserving document order', () {
      const left =
          '![zero](upload://zero)\n\n[grid]\n![one](upload://one)\n[/grid]';
      final leftImage = parseComposerImages(left).first;
      final leftGallery = parseComposerImageGalleries(left).single;
      expect(
        moveComposerImageIntoGallery(left, leftGallery, leftImage),
        '[grid]\n![zero](upload://zero)\n![one](upload://one)\n[/grid]',
      );

      const right =
          '[grid]\n![one](upload://one)\n[/grid]\n![two](upload://two)';
      final rightGallery = parseComposerImageGalleries(right).single;
      final rightImage = parseComposerImages(right).last;
      expect(
        moveComposerImageIntoGallery(right, rightGallery, rightImage),
        '[grid]\n![one](upload://one)\n![two](upload://two)\n[/grid]',
      );

      const separated =
          '[grid]![one](upload://one)[/grid] words ![two](upload://two)';
      expect(
        moveComposerImageIntoGallery(
          separated,
          parseComposerImageGalleries(separated).single,
          parseComposerImages(separated).last,
        ),
        isNull,
      );
    });

    test('moves a member after its gallery and dissolves a sole wrapper', () {
      const source =
          '[grid mode=carousel]\n![one](upload://one)\n![two](upload://two)\n[/grid]';
      final gallery = parseComposerImageGalleries(source).single;
      expect(
        moveComposerImageOutOfGallery(source, gallery, gallery.images.first),
        '[grid mode=carousel]\n![two](upload://two)\n[/grid]\n'
        '![one](upload://one)',
      );

      const sole = '[grid]\n![one](upload://one)\n[/grid]';
      final soleGallery = parseComposerImageGalleries(sole).single;
      expect(
        moveComposerImageOutOfGallery(
          sole,
          soleGallery,
          soleGallery.images.single,
        ),
        '![one](upload://one)',
      );
    });

    test('deletes a member and dissolves a sole wrapper', () {
      const source =
          '[grid]\n![one](upload://one)\n![two](upload://two)\n[/grid]';
      final gallery = parseComposerImageGalleries(source).single;
      expect(
        deleteComposerImageFromGallery(source, gallery, gallery.images.first),
        '[grid]\n![two](upload://two)\n[/grid]',
      );

      const sole = '[grid]\n![one](upload://one)\n[/grid]';
      final soleGallery = parseComposerImageGalleries(sole).single;
      expect(
        deleteComposerImageFromGallery(
          sole,
          soleGallery,
          soleGallery.images.single,
        ),
        isEmpty,
      );
    });

    test(
      'captured gallery and image blocks fail safely after source moves',
      () {
        const source =
            '[grid]\n![one](upload://one)\n![two](upload://two)\n[/grid]\n'
            '![three](upload://three)';
        final gallery = parseComposerImageGalleries(source).single;
        final member = gallery.images.first;
        final standalone = parseComposerImages(source).last;
        const changed = 'prefix $source';

        expect(
          setComposerImageGalleryMode(
            changed,
            gallery,
            ComposerGalleryMode.carousel,
          ),
          isNull,
        );
        expect(unwrapComposerImageGallery(changed, gallery), isNull);
        expect(
          appendComposerImageToGallery(
            changed,
            gallery,
            '![four](upload://four)',
          ),
          isNull,
        );
        expect(
          moveComposerImageIntoGallery(changed, gallery, standalone),
          isNull,
        );
        expect(moveComposerImageOutOfGallery(changed, gallery, member), isNull);
        expect(
          deleteComposerImageFromGallery(changed, gallery, member),
          isNull,
        );
        expect(wrapComposerImagesInGallery(changed, [standalone]), isNull);
      },
    );
  });

  group('gallery native input protection', () {
    const formatter = ComposerImageGalleryInputFormatter();
    const source = '[grid]\n![one](upload://one)\n[/grid]\ndog';

    test('relocates an insertion from hidden source after the gallery', () {
      final gallery = parseComposerImageGalleries(source).single;
      const oldValue = TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 2),
      );
      const newValue = TextEditingValue(
        text: '[g\nrid]\n![one](upload://one)\n[/grid]\ndog',
        selection: TextSelection.collapsed(offset: 3),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, source.replaceRange(gallery.end, gallery.end, '\n'));
      expect(
        result.selection,
        TextSelection.collapsed(offset: gallery.end + 1),
      );
      expect(parseComposerImageGalleries(result.text), hasLength(1));
    });

    test('rejects a partial replacement of gallery source', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(
          text: source,
          selection: TextSelection(baseOffset: 1, extentOffset: 5),
        ),
        const TextEditingValue(
          text: '[x]\n![one](upload://one)\n[/grid]\ndog',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );

      expect(result.text, source);
    });
  });
}

int _bestOf(void Function() body) {
  var best = -1;
  for (var run = 0; run < 3; run++) {
    final stopwatch = Stopwatch()..start();
    body();
    stopwatch.stop();
    if (best < 0 || stopwatch.elapsedMicroseconds < best) {
      best = stopwatch.elapsedMicroseconds;
    }
  }
  return best;
}
