import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_transcript.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

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
