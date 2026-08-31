import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EmojiSkinTone', () {
    test('maps the web picker t1 sentinel to an empty suffix', () {
      expect(EmojiSkinTone.fromCode('t1'), EmojiSkinTone.neutral);
      expect(EmojiSkinTone.neutral.shortcodeSuffix, isEmpty);
    });

    test('keeps non-neutral web codes and shortcode suffixes', () {
      expect(EmojiSkinTone.t2.shortcodeSuffix, ':t2');
      expect(EmojiSkinTone.t6.code, 't6');
    });
  });

  group('SiteEmoji', () {
    test(
      'applies a tone to shortcode and artwork without losing URL state',
      () {
        const emoji = SiteEmoji(
          name: 'wave',
          url: 'https://cdn.example/emoji/wave.png?v=12#art',
          tonable: true,
        );

        expect(emoji.codeFor(EmojiSkinTone.t3), 'wave:t3');
        expect(
          emoji.urlFor(EmojiSkinTone.t3),
          'https://cdn.example/emoji/wave/3.png?v=12#art',
        );
      },
    );

    test('never tones custom artwork', () {
      const emoji = SiteEmoji(
        name: 'party_blob',
        url: '/uploads/party.png?optimized=true',
      );

      expect(emoji.codeFor(EmojiSkinTone.t5), 'party_blob');
      expect(emoji.urlFor(EmojiSkinTone.t5), emoji.url);
    });
  });

  test('catalog freezes groups and retains first duplicate lookup', () {
    final source = <SiteEmoji>[
      const SiteEmoji(name: 'wave', url: 'first.png'),
      const SiteEmoji(name: 'wave', url: 'second.png'),
    ];
    final catalog = SiteEmojiCatalog(
      groups: [SiteEmojiGroup(id: 'opaque/group', emojis: source)],
    );
    source.clear();

    expect(catalog.groups.single.id, 'opaque/group');
    expect(catalog.all, hasLength(2));
    expect(catalog.emojiNamed('wave')?.url, 'first.png');
    expect(
      () => catalog.all.add(const SiteEmoji(name: 'x', url: 'x')),
      throwsUnsupportedError,
    );
  });
}
