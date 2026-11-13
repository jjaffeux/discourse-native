import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/json.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_timeline.dart';
import 'package:flutter/foundation.dart';

void main() {
  const site = 'https://forum.example';
  const config = SiteConfig();
  const titles = [
    'Discussion about Flutter',
    'Une question sur le café',
    'タイトルについて',
  ];
  const excerpts = [
    '<p>Hello <img class="emoji" alt=":wave:"><br>World</p><p>More &amp; less</p>',
    '<blockquote><div>Quoted <em>words</em></div></blockquote><ul><li>First</li><li>Second</li></ul>',
  ];
  final names = ['heart', ':smile:', 'thumbsup:t4', ':wave:t6:'];
  final files = ['recording.MOV', 'clip.mp4', 'photo.png', 'foo.mp4.txt']
      .map(
        (name) => ComposerUploadFile(
          name: name,
          length: () async => 0,
          openRead: () => const Stream.empty(),
        ),
      )
      .toList();
  final ids = List.generate(1000, (i) => i + 1);
  final newest = _message(1000);
  final arrival = _message(1001);
  final snapshot = ChatTimelineSnapshot(ids: ids, messageById: (_) => newest);
  final expectedIds = [...ids, arrival.id];
  const colors = ['A2D', '#ea4', '19A3B9', 'oops'];
  const emojiTexts = [
    'Hello :wave: from the :earth_americas: team!',
    'Look :eyes: :smile: and :heart:',
    'Example `code :x:` then :rocket:',
  ];
  stdout.writeln(
    jsonEncode({
      'html_excerpt': _measure(700, (i) => jsonHtmlText(excerpts[i % 2]), [
        'Hello :wave: World More & less',
        'Quoted words First Second',
      ]),
      'localized_title': _measure(
        6000,
        (i) => jsonTitle('original', titles[i % 3], localized: true),
        titles,
      ),
      'category_color': _measure(
        13000,
        (i) => categoryColorValueOrNull(colors[i % 4]),
        [0xffaa22dd, 0xffeeaa44, 0xff19a3b9, null],
      ),
      'emoji_asset_url':
          _measure(12000, (i) => config.emojiUrl(names[i % 4], siteUrl: site), [
            '$site/images/emoji/twitter/heart.png',
            '$site/images/emoji/twitter/smile.png',
            '$site/images/emoji/twitter/thumbsup/4.png',
            '$site/images/emoji/twitter/wave/6.png',
          ]),
      'emoji_text_shortcodes': _measure(
        3500,
        (i) => siteEmojiShortcodeMatches(
          emojiTexts[i % 3],
        ).map((m) => m[1]).join(','),
        ['wave,earth_americas', 'eyes,smile,heart', 'rocket'],
      ),
      'composer_video_classification': _measure(
        15000,
        (i) => files[i % 4].isVideo,
        [true, true, false, false],
      ),
      'chat_live_append_1000': _measure(
        1300,
        (_) => ChatMessageTimeline.admitLive(held: snapshot, message: arrival),
        [expectedIds],
        compare: (a, b) => listEquals(a as List<int>?, b as List<int>?),
      ),
    }),
  );
  exit(0);
}

ChatMessage _message(int id) => ChatMessage(
  id: id,
  channelId: 1,
  cooked: '<p>Message</p>',
  author: const ChatMessageAuthor(id: 1, username: 'sam'),
  createdAt: DateTime.utc(2026, 11, 13, 0, 0, id),
);

double _measure(
  int count,
  Object? Function(int) run,
  List<Object?> expected, {
  bool Function(Object?, Object?)? compare,
}) {
  final samples = <double>[];
  final output = List<Object?>.filled(count, null);
  for (var batch = 0; batch < 10; batch++) {
    final watch = Stopwatch()..start();
    for (var i = 0; i < count; i++) {
      output[i] = run(i);
    }
    watch.stop();
    for (var i = 0; i < count; i++) {
      final wanted = expected[i % expected.length];
      if (!(compare?.call(output[i], wanted) ?? output[i] == wanted)) {
        throw StateError('Unexpected output: ${output[i]} expected $wanted');
      }
    }
    if (batch >= 3) samples.add(watch.elapsedMicroseconds / count);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}
