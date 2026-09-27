import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/media_pipeline.dart';
import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'bundled_plugins.dart';
import 'chat_shell.dart';
import 'fakes.dart';

const chatScrollSite = 'https://scroll.example';

/// Offline stand-in for public emoji assets; the reaction controls and SVG
/// decoding path are the production ones. Private images use the site cache.
MediaPipeline chatScrollMediaPipeline() => MediaPipeline(
  client: MockClient(
    (_) async => http.Response(
      '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" '
      'viewBox="0 0 32 32"><circle cx="16" cy="16" r="15" fill="#ffc83d"/>'
      '<path d="M8 19 Q16 29 24 19 M10 10 V14 M22 10 V14" '
      'fill="none" stroke="#583d16" stroke-width="2"/></svg>',
      200,
      headers: {'content-type': 'image/svg+xml'},
    ),
  ),
);

Future<ShellController> chatScrollController({
  int count = 500,
  void Function(FakeDiscourseApi api)? configureApi,
  bool directMessage = false,
  bool group = false,
  bool rich = false,
  Uint8List? animatedBytes,
  DiscourseUser? reader,
  Completer<DiscourseUser>? sessionUser,
}) async {
  final imageBytes =
      animatedBytes ??
      (rich
          ? (await rootBundle.load(
              'packages/discourse_native/src/styleguide/assets/item/model-lg.jpg',
            )).buffer.asUint8List()
          : null);
  final api = _ChatScrollApi(
    sessionUser: sessionUser,
    user: const DiscourseUser(id: 1, username: 'reader1'),
    chatMessagesByKey: {
      '9': (
        messages: [
          for (var id = 1; id <= count; id++)
            ChatMessage(
              id: id,
              channelId: 9,
              cooked: animatedBytes != null && id > count - 3
                  ? '<p>Message $id</p><img src="$chatScrollSite/animated-$id.gif" width="100" height="100">'
                  : rich
                  ? richChatScrollHtml(id)
                  : switch (id % 4) {
                      0 =>
                        '<p>Message $id with <strong>formatted text</strong> '
                            'and a longer paragraph that wraps in a narrow channel. '
                            'Reading history should keep the visible messages stable.</p>',
                      1 =>
                        '<p>Message $id</p><ul><li>First point</li>'
                            '<li>Second point with <code>inline code</code></li></ul>',
                      _ => '<p>Message $id: a short reply.</p>',
                    },
              reactions: rich
                  ? const [
                      ChatReaction(emoji: 'heart', count: 12, reacted: true),
                      ChatReaction(emoji: '+1', count: 8),
                      ChatReaction(emoji: 'laughing', count: 3),
                      ChatReaction(emoji: 'tada', count: 2),
                    ]
                  : const [],
              uploads: rich && id % 6 == 0
                  ? [
                      for (var image = 0; image < 2; image++)
                        ChatUpload(
                          id: id * 2 + image,
                          url: '$chatScrollSite/upload-$id-$image.jpg',
                          originalFilename: 'photo-$id-$image.jpg',
                          kind: ChatUploadKind.image,
                          width: 640,
                          height: 427,
                        ),
                    ]
                  : const [],
              author: ChatMessageAuthor(
                id: (id ~/ 3) % 4 + 1,
                username: 'reader${(id ~/ 3) % 4 + 1}',
              ),
              createdAt: DateTime(
                2026,
                8,
                1,
              ).add(Duration(days: (id - 1) ~/ 12, minutes: id % 12)),
            ),
        ],
        canLoadMorePast: false,
        canLoadMoreFuture: false,
        targetMessageId: null,
      ),
    },
  );
  configureApi?.call(api);
  final controller = ShellController(
    siteImages: imageBytes == null
        ? null
        : SiteImageRepository(
            credentials: FakeApiCredentialReader(),
            lifecycle: SiteLifecycle(),
            client: MockClient((_) async {
              // Exercise loading and decoding as new rows enter the viewport.
              await Future<void>.delayed(const Duration(milliseconds: 40));
              return http.Response.bytes(Uint8List.fromList(imageBytes), 200);
            }),
          ),
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('scroll.example').copyWith(user: reader),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[chatScrollSite] = 'fixture-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await controller.load();
  controller.chatRecords.put(
    chatScrollSite,
    ChatChannel(
      id: 9,
      title: 'Scroll profiling',
      kind: directMessage
          ? ChatChannelKind.directMessage
          : ChatChannelKind.category,
      isGroup: group,
      membership: ChatMembership(following: true, lastReadMessageId: count),
    ),
  );
  await controller.chat.openChannel(chatScrollSite, 9);
  return controller;
}

final class _ChatScrollApi extends FakeDiscourseApi {
  _ChatScrollApi({this.sessionUser, super.user, super.chatMessagesByKey});

  /// Answers the session's account refresh when completed; until then the
  /// stored account stays current.
  final Completer<DiscourseUser>? sessionUser;

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) =>
      sessionUser?.future ??
      super.currentUser(siteUrl: siteUrl, apiKey: apiKey, clientId: clientId);
}

/// Unique URLs force real image loading/decoding on the outward pass, then
/// exercise the production caches on return. No external service is contacted.
String richChatScrollHtml(int id) => [
  '<p>Message $id: <strong>rich channel history</strong> with '
      '<a href="https://example.com/$id">a link</a> and <code>inline code</code>.</p>',
  if (id % 3 == 0)
    '<p><img src="$chatScrollSite/inline-$id.jpg" width="480" height="320"></p>',
  if (id % 3 == 1)
    '<aside class="onebox" data-onebox-src="https://example.com/$id">'
        '<header><a href="https://example.com/$id">Example publication</a></header>'
        '<article class="onebox-body">'
        '<img class="thumbnail" src="$chatScrollSite/thumbnail-$id.jpg" '
        'width="640" height="427">'
        '<h3><a href="https://example.com/$id">A useful article $id</a></h3>'
        '<p>Preview $id with <strong>formatting</strong>, a thumbnail, and enough '
        'text to wrap across several lines in narrow chat channels.</p>'
        '</article></aside>',
  if (id % 2 == 0)
    '<aside class="quote" data-username="reader2">'
        '<div class="title">reader2:</div><blockquote>'
        '<p>Quoted reply $id with <em>emphasis</em> and <code>some code</code>.</p>'
        '<blockquote><p>Nested quotation $id with more context.</p></blockquote>'
        '</blockquote></aside>',
  if (id % 5 == 0)
    '<ul><li>Images and previews should stay stable.</li>'
        '<li>Reactions should stay interactive.</li></ul>'
        '<pre><code class="lang-ruby">def scroll(channel)\n'
        '  channel.messages.each { |message| render(message) }\nend</code></pre>',
].join();

class ChatScrollFixture extends StatelessWidget {
  const ChatScrollFixture({
    super.key,
    required this.controller,
    required this.diagnostics,
    this.width = 800,
    this.dark = false,
  });

  final ShellController controller;
  final DiagnosticsController diagnostics;
  final double width;
  final bool dark;

  @override
  Widget build(BuildContext context) => DiagnosticsScope(
    controller: diagnostics,
    child: ShellScope(
      controller: controller,
      child: PluginUiScope.own(
        chatPluginId,
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => DToaster(child: child!),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: 600,
                // These suites measure the transcript against a fixed
                // viewport. The channel header retracts with scrolling and
                // wraps its metadata by width, so it would make that viewport
                // vary per case; chat_channel_header_test and the lifecycle
                // suite cover it.
                child: const ChatChannelView(channelId: 9, showHeader: false),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
