import 'package:discourse_native/src/plugins/gifs/gif.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GifCategory', () {
    test('reads a complete featured category', () {
      expect(
        GifCategory.fromJson(const {
          'name': ' Reactions ',
          'image': 'https://cdn.example/reactions.webp',
          'searchterm': ' applause ',
        }),
        const GifCategory(
          title: 'Reactions',
          imageUrl: 'https://cdn.example/reactions.webp',
          searchTerm: 'applause',
        ),
      );
    });

    test('rejects incomplete categories and credential-bearing URLs', () {
      expect(
        GifCategory.fromJson(const {
          'name': 'Reactions',
          'image': 'https://secret@cdn.example/reactions.webp',
          'searchterm': 'applause',
        }),
        isNull,
      );
      expect(GifCategory.fromJson(const {'name': 'Reactions'}), isNull);
    });
  });

  group('GifResult', () {
    test(
      'selects the configured format and emits Discourse image markdown',
      () {
        final result = GifResult.fromJson(const {
          'title':
              r'a\[b]`'
              '\n'
              'c|d',
          'media_formats': {
            'webp': {
              'url': 'https://cdn.example/result.webp',
              'dims': [320, 180],
            },
            'gif': {
              'url': 'https://cdn.example/result.gif',
              'dims': [640, 360],
            },
          },
        }, fileDetail: 'webp');

        expect(result, isNotNull);
        expect(result!.title, r'a\[b]` c d');
        expect(result.url, 'https://cdn.example/result.webp');
        expect(result.aspectRatio, closeTo(16 / 9, 0.0001));
        expect(
          result.markdown,
          '\n!['
          r'a\\\[b\]\` c d'
          '|320x180](https://cdn.example/result.webp)\n',
        );
      },
    );

    test('normalizes an empty or newline-only title to GIF', () {
      final result = GifResult.fromJson(const {
        'title': '\r\n | \n',
        'media_formats': {
          'gif': {
            'url': 'https://cdn.example/result.gif',
            'dims': [24, 24],
          },
        },
      }, fileDetail: 'gif');

      expect(result!.title, 'GIF');
      expect(
        result.markdown,
        '\n![GIF|24x24](https://cdn.example/result.gif)\n',
      );
    });

    test(
      'rejects unusable URLs and dimensions outside native markup bounds',
      () {
        Map<String, Object> payload(Object url, Object dimensions) => {
          'title': 'Result',
          'media_formats': {
            'webp': {'url': url, 'dims': dimensions},
          },
        };

        expect(
          GifResult.fromJson(
            payload('javascript:alert(1)', [320, 180]),
            fileDetail: 'webp',
          ),
          isNull,
        );
        expect(
          GifResult.fromJson(
            payload('https://cdn.example/result.webp', [10000, 180]),
            fileDetail: 'webp',
          ),
          isNull,
        );
        expect(
          GifResult.fromJson(
            payload('https://cdn.example/result.webp', [320, 0]),
            fileDetail: 'webp',
          ),
          isNull,
        );
      },
    );
  });

  group('GifSearchPage', () {
    test('normalizes a blank continuation cursor to exhaustion', () {
      final page = GifSearchPage(
        results: const [
          GifResult(
            title: 'Result',
            url: 'https://cdn.example/result.webp',
            width: 320,
            height: 180,
          ),
        ],
        nextPosition: ' \n ',
      );

      expect(page.nextPosition, isNull);
      expect(page.hasMore, isFalse);
    });

    test('keeps a trimmed opaque continuation cursor', () {
      final page = GifSearchPage(results: const [], nextPosition: ' next/24 ');

      expect(page.nextPosition, 'next/24');
      expect(page.hasMore, isTrue);
    });
  });
}
