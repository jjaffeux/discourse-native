import 'dart:io';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_transcript.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

Future<void> pumpTranscript(
  WidgetTester tester,
  String source, {
  double width = 430,
  double textScale = 1,
  bool dark = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: SingleChildScrollView(
                child: SelectionArea(
                  child: CookedHtml(
                    html: source,
                    siteUrl: 'https://meta.discourse.org',
                    registry: const PluginRegistry([ChatPlugin()]),
                    buildAsync: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const transcript = '''
<div class="chat-transcript" data-message-id="408" data-username="mcwumbly"
     data-datetime="2026-08-25 03:33:54 UTC" data-channel-name="ai-tech"
     data-channel-id="47">
  <div class="chat-transcript-user">
    <div class="chat-transcript-user-avatar">
      <img src="/user_avatar/meta.discourse.org/mcwumbly/40/1.png"
           class="avatar">
    </div>
    <div class="chat-transcript-username">mcwumbly</div>
    <div class="chat-transcript-datetime">
      <a href="/chat/c/-/47/408" title="2026-08-25 03:33:54 UTC"></a>
    </div>
    <a class="chat-transcript-channel" href="/chat/c/-/47">ai-tech</a>
  </div>
  <div class="chat-transcript-messages">
    <p>A couple questions about MCP work:</p>
    <ul><li>Could one Discourse explore another?</li></ul>
  </div>
</div>
''';

void main() {
  final threadTranscript = File(
    'test/fixtures/chat_thread_transcript.html',
  ).readAsStringSync();

  final title = find.textContaining('Better Discourse app', findRichText: true);
  final reply = find.textContaining('RFC: native app', findRichText: true);

  testWidgets(
    'thread summary collapses replies and restores them on activation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await pumpTranscript(tester, threadTranscript);

        expect(
          tester.getSemantics(find.byType(DCollapsibleTrigger)).label,
          'Better Discourse app scraping concerns and legal discussion',
        );
        expect(title, findsOneWidget);
        expect(find.text('nat'), findsOneWidget);
        expect(find.textContaining('Oct 2,'), findsOneWidget);
        expect(
          find.textContaining('Originally sent in', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.text('https://betterdiscourse.app/', findRichText: true),
          findsOneWidget,
        );
        expect(reply, findsNothing);
        expect(find.byType(ChatTranscriptBlock), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('.*RFC: native app.*')),
          findsNothing,
        );

        await tester.tap(title);
        await tester.pumpAndSettle();
        expect(reply, findsOneWidget);
        expect(find.text('mark.reeves'), findsOneWidget);
        expect(find.text('alice'), findsOneWidget);
        expect(find.text('A second reply', findRichText: true), findsOneWidget);
        expect(
          find.textContaining('A quoted passage', findRichText: true),
          findsOneWidget,
        );
        expect(find.byType(ChatTranscriptBlock), findsNWidgets(3));

        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(reply, findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(reply, findsOneWidget);
        await tester.tap(title);
        await tester.pumpAndSettle();
        expect(reply, findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('summary and reply links retain destinations without toggling', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final launched = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') {
        launched.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await pumpTranscript(tester, threadTranscript);

    await tester.tapOnText(
      find.textRange.ofSubstring('https://betterdiscourse.app/'),
    );
    await tester.pumpAndSettle();
    expect(launched, ['https://betterdiscourse.app/']);
    expect(reply, findsNothing);
    await tester.tap(find.textContaining('Oct 2,'));
    await tester.pumpAndSettle();
    expect(launched.last, 'https://meta.discourse.org/chat/c/-/5/101');
    expect(reply, findsNothing);

    await tester.tap(title);
    await tester.pumpAndSettle();
    // The rich paragraph also contains plain text; hit the link span itself.
    await tester.tapOnText(find.textRange.ofSubstring('RFC: native app'));
    await tester.pumpAndSettle();
    expect(launched.last, 'https://meta.discourse.org/t/native-app/42');
    expect(reply, findsOneWidget);
  });

  for (final dark in [true, false]) {
    testWidgets('narrow scaled thread title and preview wrap ($dark)', (
      tester,
    ) async {
      await pumpTranscript(
        tester,
        threadTranscript,
        width: 300,
        textScale: 2,
        dark: dark,
      );
      expect(title, findsOneWidget);
      expect(reply, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(reply, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'explicitly open threads and nested message details stay independent',
    (tester) async {
      await pumpTranscript(
        tester,
        threadTranscript
            .replaceFirst('<details>', '<details open>')
            .replaceFirst(
              '<p>A second reply</p>',
              '<details><summary>Reply details</summary><p>Hidden detail</p></details>',
            ),
      );
      expect(reply, findsOneWidget);
      expect(find.text('Hidden detail', findRichText: true), findsNothing);
      await tester.ensureVisible(find.text('Reply details'));
      await tester.tap(find.text('Reply details'));
      await tester.pumpAndSettle();
      expect(find.text('Hidden detail', findRichText: true), findsOneWidget);
      expect(reply, findsOneWidget);
    },
  );

  test('keeps core thread summary separate from collapsed replies', () {
    final data = ChatTranscriptData.from(
      html.parseFragment(threadTranscript).children.single,
    );

    expect(data.metaHtml, contains('Originally sent in'));
    expect(data.username, 'nat');
    expect(data.displayName, 'nat');
    expect(data.sourceLink, '/chat/c/-/5/101');
    expect(data.bodyHtml, contains('https://betterdiscourse.app/'));
    expect(data.bodyHtml, isNot(contains('RFC: native app')));
    expect(data.nestedTranscriptsHtml, isEmpty);
    final disclosure = data.disclosure!;
    expect(disclosure.open, isFalse);
    expect(disclosure.titleHtml, contains('Better Discourse app'));
    expect(disclosure.bodyHtml, contains('RFC: native app'));
    expect(disclosure.bodyHtml, contains('A second reply'));
    expect(disclosure.bodyHtml, isNot(contains('betterdiscourse.app/')));
    expect(disclosure.bodyHtml, isNot(contains('<summary>')));
  });

  test('thread id without replies and message details stay ordinary quotes', () {
    final data = ChatTranscriptData.from(
      html
          .parseFragment(
            transcript
                .replaceFirst(
                  'data-message-id="408"',
                  'data-message-id="408" data-thread-id="140"',
                )
                .replaceFirst(
                  '<p>A couple questions about MCP work:</p>',
                  '<details><summary>Message details</summary><p>Body</p></details>',
                ),
          )
          .children
          .single,
    );

    expect(data.disclosure, isNull);
    expect(data.bodyHtml, contains('<details>'));
  });

  test('honors explicit open and preserves rich thread titles', () {
    final data = ChatTranscriptData.from(
      html
          .parseFragment(
            threadTranscript
                .replaceFirst('<details>', '<details open>')
                .replaceFirst(
                  'Better Discourse app scraping concerns and legal discussion</span>',
                  'Thread <img class="emoji" src="/smile.png" alt=":smile:"></span>',
                ),
          )
          .children
          .single,
    );

    expect(data.disclosure!.open, isTrue);
    expect(data.disclosure!.titleHtml, contains('class="emoji"'));
  });

  test('reads the chat quote structure emitted by core', () {
    final element = html.parseFragment(transcript).children.single;
    final data = ChatTranscriptData.from(element);

    expect(data.username, 'mcwumbly');
    expect(data.displayName, 'mcwumbly');
    expect(data.avatarUrl, '/user_avatar/meta.discourse.org/mcwumbly/40/1.png');
    expect(data.createdAt, DateTime.utc(2026, 8, 25, 3, 33, 54));
    expect(data.sourceLink, '/chat/c/-/47/408');
    expect(data.channelName, 'ai-tech');
    expect(data.channelLink, '/chat/c/-/47');
    expect(data.bodyHtml, contains('A couple questions about MCP work:'));
  });

  test('claims only core chat transcript wrappers', () {
    element(String source) => html.parseFragment(source).children.single;

    expect(
      chatTranscriptWidgetBuilder(element(transcript)),
      isA<ChatTranscriptBlock>(),
    );
    expect(
      chatTranscriptWidgetBuilder(element('<div class="chat-message"></div>')),
      isNull,
    );
    expect(
      chatTranscriptWidgetBuilder(
        element('<aside class="chat-transcript"></aside>'),
      ),
      isNull,
    );
  });

  testWidgets('renders a chat quote as one attributed aside', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: AppTheme.dark,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: CookedHtml(
              html: transcript,
              siteUrl: 'https://meta.discourse.org',
              registry: PluginRegistry([ChatPlugin()]),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ChatTranscriptBlock), findsOneWidget);
    expect(find.text('mcwumbly'), findsOneWidget);
    expect(find.textContaining('Aug 25,'), findsOneWidget);
    expect(find.text('ai-tech'), findsOneWidget);
    expect(find.text('2026-08-25 03:33:54 UTC'), findsNothing);
    expect(
      find.textContaining(
        'A couple questions about MCP work:',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Could one Discourse explore another?',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });
}
