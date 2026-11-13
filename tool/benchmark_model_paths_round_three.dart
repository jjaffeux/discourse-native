import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/emoji_picker_store.dart';
import 'package:discourse_native/src/data/retry_after.dart';
import 'package:discourse_native/src/models/emoji_usage.dart';
import 'package:discourse_native/src/models/post_checklist.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/user_draft.dart';

Future<void> main() async {
  final reply = List.filled(
    30,
    'A paragraph about the next release.',
  ).join(' ');
  final draft = <String, dynamic>{
    'draft_key': 'topic_1',
    'data': <String, dynamic>{'reply': reply},
  };
  final plain = List.filled(
    5,
    'Discuss the release schedule and next steps.',
  ).join('  ');
  final raw = List.filled(
    30,
    '- [x] Review this part and leave a note',
  ).join('\n');
  final expectedRaw = raw.replaceAll('[x]', '[ ]');
  final checklist = PostChecklistDocument(
    List.generate(
      30,
      (i) =>
          '<p><span class="chcklst-box" data-chk-src="$i:0"></span> Review this part</p>',
    ).join(),
  );
  final catalog = SiteEmojiCatalog(
    groups: [
      SiteEmojiGroup(
        id: 'standard',
        emojis: const [
          SiteEmoji(
            name: 'wave',
            url: '/images/emoji/twitter/wave.png',
            tonable: true,
            animated: true,
          ),
          SiteEmoji(
            name: 'heart',
            url: '/images/emoji/twitter/heart.png',
            animated: true,
          ),
        ],
      ),
    ],
  );
  const site = 'https://forum.example';
  final store = EmojiPickerStore(persistence: _Preferences());
  await store.ensureLoaded(siteUrl: site);
  final now = DateTime.utc(2026, 11, 13);
  stdout.writeln(
    jsonEncode({
      'draft_list_excerpt': _measure(
        1300,
        (_) => UserDraft.fromJson(draft).excerpt,
        [reply.substring(0, 512).trimRight()],
      ),
      'plain_search_excerpt': _measure(
        3500,
        (_) => SearchExcerpt.fromHtml(plain).plainText,
        [plain.replaceAll('  ', ' ')],
      ),
      'checklist_source_fingerprint': _measure(
        1000,
        (_) => checklist.rawFingerprint(raw),
        [expectedRaw],
      ),
      'favorite_emoji_history': _measure(
        2300,
        (_) => store
            .favoriteEmojiCodesFor(
              siteUrl: site,
              context: CoreEmojiUsageContexts.topic,
              catalog: catalog,
            )
            .join(','),
        ['wave:t4,heart'],
      ),
      'animated_emoji_asset': _measure(
        5500,
        (i) => catalog.animatedUrlFor(i.isEven ? 'heart' : 'wave:t4'),
        [
          '/images/emoji/noto_animated/heart.avif',
          '/images/emoji/noto_animated/wave/4.avif',
        ],
      ),
      'retry_after_delta': _measure(
        10000,
        (i) => parseRetryAfter(
          i.isEven ? '30' : '0000031',
          maximum: const Duration(minutes: 1),
          now: now,
        ),
        [const Duration(seconds: 30), const Duration(seconds: 31)],
      ),
    }),
  );
  exit(0);
}

class _Preferences implements EmojiPickerPersistence {
  @override
  Future<String?> readPreferences({required String siteUrl}) async =>
      jsonEncode({
        'version': 2,
        'history': {
          CoreEmojiUsageContexts.topic.id: List.generate(
            40,
            (i) => i % 3 == 0 ? 'heart' : 'wave:t4',
          ),
        },
      });

  @override
  Future<bool> writePreferences({
    required String siteUrl,
    required String encoded,
  }) async => true;
}

double _measure(int count, Object? Function(int) run, List<Object?> expected) {
  final output = List<Object?>.filled(count, null);
  final samples = <double>[];
  for (var batch = 0; batch < 10; batch++) {
    final watch = Stopwatch()..start();
    for (var i = 0; i < count; i++) {
      output[i] = run(i);
    }
    watch.stop();
    for (var i = 0; i < count; i++) {
      if (output[i] != expected[i % expected.length]) {
        throw StateError(
          'Unexpected result ${output[i]} for operation $i; expected ${expected[i % expected.length]}',
        );
      }
    }
    if (batch >= 3) samples.add(watch.elapsedMicroseconds / count);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}
