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

import 'support/native_ui_evidence.dart';

Future<void> pumpTranscript(
  WidgetTester tester,
  String source, {
  double width = 430,
  double textScale = 1,
  bool dark = true,
  PluginRegistry registry = const PluginRegistry([ChatPlugin()]),
}) async {
  await prepareNativeUiEvidence(tester);
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final theme = dark ? AppTheme.dark : AppTheme.light;
  await tester.pumpWidget(
    MaterialApp(
      builder: nativeUiEvidenceBuilder,
      locale: const Locale('en'),
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'TranscriptReview'),
      ),
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
                    registry: registry,
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
  setUpAll(() async {
    await (FontLoader(
      'TranscriptReview',
    )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
  });
  final threadTranscript = File(
    'test/fixtures/chat_thread_transcript.html',
  ).readAsStringSync();
  final title = find.textContaining('Better Discourse app', findRichText: true);
  final reply = find.textContaining('RFC: native app', findRichText: true);

  String continuation({
    String name = 'alice',
    String message = 'Second message',
    int id = 409,
  }) => transcript
      .replaceAll('mcwumbly', name)
      .replaceAll('408', '$id')
      .replaceFirst('data-channel-name="ai-tech"', '')
      .replaceFirst('data-channel-id="47"', '')
      .replaceFirst(
        '<a class="chat-transcript-channel" href="/chat/c/-/47">ai-tech</a>',
        '',
      )
      .replaceFirst('A couple questions about MCP work:', message);

  testWidgets(
    'threads are expanded with bodies, quotes and authors exactly once',
    (tester) async {
      await pumpTranscript(tester, threadTranscript);
      expect(title, findsOneWidget);
      expect(reply, findsOneWidget);
      expect(find.text('nat'), findsOneWidget);
      expect(find.text('mark.reeves'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('A second reply', findRichText: true), findsOneWidget);
      expect(
        find.textContaining('A quoted passage', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(ChatTranscriptBlock), findsOneWidget);
      expect(find.byType(DCollapsibleTrigger), findsNothing);
      expect(find.text('general'), findsOneWidget);
      expect(find.text('Transcript'), findsOneWidget);
      expect(
        find.textContaining('Originally sent in', findRichText: true),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'adjacent continuations share a header while named sources and prose split groups',
    (tester) async {
      await pumpTranscript(
        tester,
        '$transcript${continuation()}<p>Between groups</p>${continuation(name: 'bob')}',
      );
      expect(find.byType(ChatTranscriptBlock), findsNWidgets(2));
      expect(find.text('ai-tech'), findsOneWidget);
      expect(find.text('mcwumbly'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('Between groups', findRichText: true), findsOneWidget);
      expect(find.text('Second message', findRichText: true), findsNWidgets(2));
      await pumpTranscript(tester, '$transcript$transcript');
      expect(find.byType(ChatTranscriptBlock), findsNWidgets(2));
    },
  );

  testWidgets(
    'already grouped markup keeps one group without nested duplicates',
    (tester) async {
      await pumpTranscript(
        tester,
        '<div class="chat-transcript-group"><div class="chat-transcript-group__header">Old header</div><div class="chat-transcript-group__body">$transcript${continuation()}</div></div>',
      );
      expect(find.byType(ChatTranscriptBlock), findsOneWidget);
      expect(find.text('Old header', findRichText: true), findsNothing);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('mcwumbly'), findsOneWidget);
      expect(find.text('ai-tech'), findsOneWidget);
    },
  );

  test(
    'typed group preserves root chronology and expands nested thread structure',
    () {
      final group = ChatTranscriptGroupData.from(
        html.parseFragment(threadTranscript).children,
      );
      expect(group.name, 'general');
      expect(group.channelLink, '/chat/c/-/5');
      final message = group.messages.single;
      expect(message.username, 'nat');
      expect(message.bodyHtml, contains('https://betterdiscourse.app/'));
      expect(message.bodyHtml, isNot(contains('RFC: native app')));
      expect(message.replies.map((reply) => reply.username), [
        'mark.reeves',
        'alice',
      ]);
      expect(message.replies.first.sourceLink, '/chat/c/-/5/t/140/102');
      expect(message.replies.last.sourceLink, '/chat/c/-/5/t/140/103');
      expect(message.threadLink, '/chat/c/-/5/t/140');
    },
  );

  testWidgets('cooked fragments between replies keep their order and content', (
    tester,
  ) async {
    final source = threadTranscript.replaceFirst(
      '<div class="chat-transcript chat-transcript-chained" data-message-id="103"',
      '<p>Transcript note</p><div class="chat-transcript chat-transcript-chained" data-message-id="103"',
    );
    final data = ChatTranscriptGroupData.from(
      html.parseFragment(source).children,
    );
    final meaningful = data.messages.single.parts
        .where(
          (part) =>
              part is ChatTranscriptReply ||
              (part is ChatTranscriptFragment &&
                  part.html.contains('Transcript note')),
        )
        .toList();
    expect(meaningful, hasLength(3));
    expect(
      (meaningful[0] as ChatTranscriptReply).message.username,
      'mark.reeves',
    );
    expect(
      (meaningful[1] as ChatTranscriptFragment).html,
      contains('Transcript note'),
    );
    expect((meaningful[2] as ChatTranscriptReply).message.username, 'alice');
    await pumpTranscript(tester, source);
    expect(find.text('Transcript note', findRichText: true), findsOneWidget);
    expect(reply, findsOneWidget);
  });

  test('unlinked archives never gain timestamp or thread links', () {
    final unlinked = threadTranscript.replaceFirst(
      '<a href="/chat/c/-/5/101" title="2026-10-02T04:18:00Z"></a>',
      '<span title="2026-10-02T04:18:00Z"></span>',
    );
    final group = ChatTranscriptGroupData.from(
      html.parseFragment(unlinked).children,
    );
    final message = group.messages.single;
    expect(message.sourceLink, isNull);
    expect(message.threadLink, isNull);
    expect(message.replies.map((reply) => reply.sourceLink), [null, null]);
  });

  test('generated transcript links retain a forum subfolder', () {
    final group = ChatTranscriptGroupData.from(
      html.parseFragment(threadTranscript).children,
      siteUrl: 'https://example.com/community',
    );
    expect(group.channelLink, 'https://example.com/community/chat/c/-/5');
    expect(
      group.messages.single.threadLink,
      'https://example.com/community/chat/c/-/5/t/140',
    );
    expect(
      group.messages.single.replies.first.sourceLink,
      'https://example.com/community/chat/c/-/5/t/140/102',
    );
  });

  testWidgets('promoted pre-grouped thread titles remain visible once', (
    tester,
  ) async {
    final element = html.parseFragment(threadTranscript).children.single;
    element.querySelector('.chat-transcript-thread-header')!.remove();
    await pumpTranscript(
      tester,
      '<div class="chat-transcript-group">'
      '<div class="chat-transcript-group__header">'
      '<span class="chat-transcript-group__thread">Promoted title</span>'
      '</div><div class="chat-transcript-group__body">'
      '${element.outerHtml}</div></div>',
    );
    expect(title, findsOneWidget);
    expect(reply, findsOneWidget);
    expect(find.text('Promoted title', findRichText: true), findsNothing);
    expect(find.byType(ChatTranscriptBlock), findsOneWidget);
  });

  testWidgets(
    'timestamp and thread links retain destinations with replies visible',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final launched = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await pumpTranscript(tester, threadTranscript);
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(launched.last, 'https://meta.discourse.org/chat/c/-/5/t/140');
      await tester.tapOnText(find.textRange.ofSubstring('RFC: native app'));
      await tester.pumpAndSettle();
      expect(launched.last, 'https://meta.discourse.org/t/native-app/42');
      expect(reply, findsOneWidget);
    },
  );

  testWidgets('message details stay independent inside expanded threads', (
    tester,
  ) async {
    await pumpTranscript(
      tester,
      threadTranscript.replaceFirst(
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
  });

  for (final dark in [true, false]) {
    testWidgets('narrow scaled expanded thread wraps ($dark)', (tester) async {
      await pumpTranscript(
        tester,
        threadTranscript,
        width: 300,
        textScale: 2,
        dark: dark,
      );
      expect(title, findsOneWidget);
      expect(reply, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unknown source types have a readable unlinked header', (
    tester,
  ) async {
    await pumpTranscript(
      tester,
      transcript
          .replaceFirst(
            'data-channel-name="ai-tech"',
            'data-source="Community call" data-source-type="unregistered"',
          )
          .replaceFirst('data-channel-id="47"', '')
          .replaceFirst(
            '<a class="chat-transcript-channel" href="/chat/c/-/47">ai-tech</a>',
            '',
          ),
    );
    expect(find.text('Community call'), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.text('mcwumbly'), findsOneWidget);
  });

  test(
    'rich thread titles and media fragments survive without mutating cooked input',
    () {
      final source = threadTranscript
          .replaceFirst(
            'Better Discourse app scraping concerns and legal discussion</span>',
            'Thread <img class="emoji" src="/smile.png" alt=":smile:"></span>',
          )
          .replaceFirst(
            '<p>A second reply</p>',
            '<p>A second reply</p><details><summary>More</summary><p>Body detail</p></details>',
          )
          .replaceFirst(
            '</summary>',
            '<div class="chat-transcript-images"><a class="lightbox" href="/original.png"><img src="/thumbnail.png"></a></div></summary>',
          );
      final element = html.parseFragment(source).children.single;
      final before = element.outerHtml;
      final group = ChatTranscriptGroupData.from([element]);
      expect(group.messages.single.threadTitleHtml, contains('class="emoji"'));
      expect(group.messages.single.bodyHtml, contains('/original.png'));
      expect(
        group.messages.single.replies.last.bodyHtml,
        contains('Body detail'),
      );
      expect(element.outerHtml, before);
    },
  );

  test('thread id without replies and message details remain body content', () {
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
    expect(data.threadTitleHtml, isNull);
    expect(data.replies, isEmpty);
    expect(data.bodyHtml, contains('<details>'));
  });

  test(
    'claims only transcript roots and preserves a detached continuation',
    () {
      element(String source) => html.parseFragment(source).children.single;
      expect(
        chatTranscriptWidgetBuilder(element(transcript)),
        isA<ChatTranscriptBlock>(),
      );
      expect(
        chatTranscriptWidgetBuilder(element(continuation())),
        isA<ChatTranscriptBlock>(),
      );
      expect(
        chatTranscriptWidgetBuilder(
          element('<div class="chat-message"></div>'),
        ),
        isNull,
      );
      expect(
        chatTranscriptWidgetBuilder(
          element('<aside class="chat-transcript"></aside>'),
        ),
        isNull,
      );
    },
  );

  for (final width in [390.0, 1440.0]) {
    testWidgets('readable transcript evidence $width', (tester) async {
      await pumpTranscript(tester, threadTranscript, width: width);
      await captureNativeUi(tester, 'chat-transcript-${width.toInt()}');
      expect(reply, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
