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
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

void _replaceEmojiCache(EmojiCache replacement) {
  final previous = EmojiCache.instance;
  EmojiCache.instance = replacement;
  addTearDown(() {
    replacement.clear();
    EmojiCache.instance = previous;
  });
}

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
    _replaceEmojiCache(
      EmojiCache(
        client: MockClient((_) async => http.Response.bytes(_emojiPng, 200)),
      ),
    );

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

  testWidgets('sizes inline emoji to the topic title text', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    _replaceEmojiCache(
      EmojiCache(client: MockClient((_) async => http.Response('', 404))),
    );

    await tester.pumpWidget(
      _TestTitle(
        controller: controller,
        title: 'Announcements :high_voltage:',
        style: const TextStyle(fontSize: 20),
      ),
    );
    await tester.pumpAndSettle();

    final emoji = tester.widget<SiteEmojiImage>(find.byType(SiteEmojiImage));
    expect(emoji.size, 20);
  });

  testWidgets('recognizes adjacent emoji and skin tones', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    _replaceEmojiCache(
      EmojiCache(client: MockClient((_) async => http.Response('', 404))),
    );

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

  testWidgets(
    'inline editor keeps its presentation and places the first caret by click',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final saved = <String>[];
      const style = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);

      await tester.pumpWidget(
        _TestEditor(
          controller: controller,
          title: 'An ordinary topic with a deliberately long title',
          width: 180,
          style: style,
          onSave: (title) async {
            saved.add(title);
            return null;
          },
        ),
      );

      final editor = find.byType(InlineTopicTitleEditor);
      final field = find.byKey(const ValueKey('topic-header-title-field'));
      final pointer = tester.widget<MouseRegion>(
        find.byKey(const ValueKey('topic-header-title-pointer')),
      );
      final textField = tester.widget<TextField>(field);
      final displayTitle = tester.widget<TopicTitle>(
        find.descendant(of: editor, matching: find.byType(TopicTitle)),
      );
      final idleSize = tester.getSize(editor);
      expect(pointer.cursor, SystemMouseCursors.text);
      expect(textField.style, style);
      expect(textField.decoration?.isCollapsed, isTrue);
      expect(textField.decoration?.border, InputBorder.none);
      expect(displayTitle.maxLines, 1);
      expect(displayTitle.overflow, TextOverflow.ellipsis);
      expect(idleSize.width, 180);

      final editorRect = tester.getRect(editor);
      await tester.tapAt(Offset(editorRect.left + 1, editorRect.center.dy));
      await tester.pump();

      expect(textField.focusNode?.hasFocus, isTrue);
      expect(textField.controller?.selection.isCollapsed, isTrue);
      expect(textField.controller?.selection.baseOffset, 0);
      expect(tester.getSize(editor), idleSize);

      await tester.enterText(field, 'A clearer topic title');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(saved, ['A clearer topic title']);
      expect(textField.focusNode?.hasFocus, isFalse);
      expect(
        tester
            .widget<TopicTitle>(
              find.descendant(of: editor, matching: find.byType(TopicTitle)),
            )
            .title,
        'A clearer topic title',
      );
    },
  );

  testWidgets('failed inline save keeps the edit focused and Escape cancels', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    final attempted = <String>[];

    await tester.pumpWidget(
      _TestEditor(
        controller: controller,
        title: 'Original title',
        onSave: (title) async {
          attempted.add(title);
          return 'The title could not be saved.';
        },
      ),
    );

    final field = find.byKey(const ValueKey('topic-header-title-field'));
    await tester.tap(field);
    await tester.enterText(field, 'Retained edit');
    await tester.tap(find.byKey(const ValueKey('outside-title-editor')));
    await tester.pumpAndSettle();

    var textField = tester.widget<TextField>(field);
    expect(attempted, ['Retained edit']);
    expect(textField.controller?.text, 'Retained edit');
    expect(textField.focusNode?.hasFocus, isTrue);
    expect(find.text('The title could not be saved.'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    textField = tester.widget<TextField>(field);
    expect(textField.controller?.text, 'Original title');
    expect(textField.focusNode?.hasFocus, isFalse);
    expect(attempted, ['Retained edit']);
  });

  testWidgets('inline editor preserves registered site emoji artwork', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    _replaceEmojiCache(
      EmojiCache(
        client: MockClient((_) async => http.Response.bytes(_emojiPng, 200)),
      ),
    );

    await tester.pumpWidget(
      _TestEditor(
        controller: controller,
        title: 'Lightning :high_voltage: talks',
        onSave: (_) async => null,
      ),
    );
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('topic-header-title-field'));
    await tester.tap(field);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: field, matching: find.byType(SiteEmojiImage)),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(field).controller?.text,
      'Lightning :high_voltage: talks',
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
  const _TestTitle({required this.controller, required this.title, this.style});

  final ShellController controller;
  final String title;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: controller,
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: TopicTitle(title, siteUrl: 'https://meta.example', style: style),
      ),
    ),
  );
}

class _TestEditor extends StatelessWidget {
  const _TestEditor({
    required this.controller,
    required this.title,
    required this.onSave,
    this.style,
    this.width,
  });

  final ShellController controller;
  final String title;
  final Future<String?> Function(String title) onSave;
  final TextStyle? style;
  final double? width;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: controller,
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: width,
              child: InlineTopicTitleEditor(
                title: title,
                siteUrl: 'https://meta.example',
                style: style,
                onSave: onSave,
              ),
            ),
            TextButton(
              key: const ValueKey('outside-title-editor'),
              onPressed: () {},
              child: const Text('Outside'),
            ),
          ],
        ),
      ),
    ),
  );
}

final Uint8List _emojiPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
