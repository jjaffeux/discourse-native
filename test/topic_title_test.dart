import 'dart:convert';
import 'dart:typed_data';

import 'package:discourse_native/src/data/emoji_cache.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('keeps an ordinary title on the plain Text path', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTitle(controller: controller, title: 'An ordinary topic'),
    );

    expect(find.text('An ordinary topic'), findsOneWidget);
    expect(find.byType(SiteEmojiImage), findsNothing);
  });

  testWidgets('draws shortcodes using the site emoji artwork', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    EmojiCache.instance = EmojiCache(
      client: MockClient((_) async => http.Response.bytes(_emojiPng, 200)),
    );
    addTearDown(EmojiCache.instance.clear);

    await tester.pumpWidget(
      _TestTitle(
        controller: controller,
        title: 'Lightning :high_voltage: talks',
      ),
    );
    await tester.pumpAndSettle();

    final emoji = tester.widget<SiteEmojiImage>(find.byType(SiteEmojiImage));
    expect(emoji.name, 'high_voltage');
    expect(
      tester.widget<EmojiImage>(find.byType(EmojiImage)).url,
      'https://meta.example/images/emoji/twitter/high_voltage.png',
    );
    expect(find.byType(Image), findsOneWidget);
    expect(
      find.bySemanticsLabel('Lightning :high_voltage: talks'),
      findsOneWidget,
    );
  });

  testWidgets('recognizes adjacent emoji and skin tones', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    EmojiCache.instance = EmojiCache(
      client: MockClient((_) async => http.Response('', 404)),
    );
    addTearDown(EmojiCache.instance.clear);

    await tester.pumpWidget(
      _TestTitle(controller: controller, title: ':wave:t3::sparkles:'),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<SiteEmojiImage>(find.byType(SiteEmojiImage))
          .map((emoji) => emoji.name),
      ['wave:t3', 'sparkles'],
    );
  });
}

ShellController _controller() => ShellController(
  instanceStore: FakeInstanceStore([instance('meta.example')]),
  // Titles draw only what the site registers, so every shortcode these tests
  // expect as artwork has to be a name the catalog knows.
  api: FakeDiscourseApi(
    emojisBySite: {
      'https://meta.example': const [
        SiteEmoji(
          name: 'high_voltage',
          url: '/images/emoji/twitter/high_voltage.png',
        ),
        SiteEmoji(name: 'wave', url: '/images/emoji/wave.png', tonable: true),
        SiteEmoji(name: 'sparkles', url: '/images/emoji/sparkles.png'),
      ],
    },
  ),
  authenticator: FakeAuthenticator(),
  drafts: FakeDraftStore(),
  trackers: FakeSiteTracker.reset(),
);

class _TestTitle extends StatelessWidget {
  const _TestTitle({required this.controller, required this.title});

  final ShellController controller;
  final String title;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: controller,
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: TopicTitle(title, siteUrl: 'https://meta.example')),
    ),
  );
}

final Uint8List _emojiPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
