import 'dart:async';

import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:flutter/material.dart';

// The review harness deliberately seeds the exact production store without
// issuing network requests.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'discourse_ui.dart';
import 'src/macos_launch_screen.dart';
import 'src/plugin_api/plugin_scope.dart';
import 'src/plugins/bundled_plugin_manifest.dart';
import 'src/plugins/chat/chat_channel.dart';
import 'src/plugins/chat/chat_channel_view.dart';
import 'src/plugins/chat/chat_controller.dart';
import 'src/plugins/chat/chat_message.dart';
import 'src/plugins/chat/chat_services.dart';
import 'src/plugins/chat/chat_stream.dart';
import 'src/plugins/chat/chat_stream_target.dart';
import 'src/styleguide/examples/message_scroller_examples.dart';
import 'src/styleguide/styleguide_page.dart';
import 'src/styleguide/styleguide_theme.dart';
import 'src/theme/app_theme.dart';

/// Offline exact-source fixture for independent Message Scroller review.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  final messages = _reviewMessages();
  final host = await _reviewHost(messages);
  runApp(
    host.scope(
      child: PluginUiScope.own(
        chatPluginId,
        _MessageScrollerReview(host: host, messages: messages),
      ),
    ),
  );
}

class _MessageScrollerReview extends StatefulWidget {
  const _MessageScrollerReview({required this.host, required this.messages});

  final PluginHostHarness host;
  final List<ChatMessage> messages;

  @override
  State<_MessageScrollerReview> createState() => _MessageScrollerReviewState();
}

class _MessageScrollerReviewState extends State<_MessageScrollerReview> {
  final _pageScroll = ScrollController();
  var _dark = false;
  var _narrow = false;
  var _large = false;
  var _rtl = false;
  var _reduced = false;
  var _plum = false;
  var _example = 0;
  var _surface = _ReviewSurface.examples;

  @override
  void dispose() {
    _pageScroll.dispose();
    unawaited(widget.host.close());
    super.dispose();
  }

  void _scrollPage(double direction) {
    if (!_pageScroll.hasClients) return;
    final position = _pageScroll.position;
    _pageScroll.jumpTo(
      (position.pixels + direction * position.viewportDimension * .7).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: _plum
        ? StyleguideTheme.plum.resolve(AppTheme.light)
        : _dark
        ? AppTheme.dark
        : AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text('Message Scroller Review a0b4'),
          actions: [
            DButton(
              label: const Text('Page up'),
              onPressed: () => _scrollPage(-1),
              variant: DButtonVariant.ghost,
            ),
            DButton(
              label: const Text('Page down'),
              onPressed: () => _scrollPage(1),
              variant: DButtonVariant.ghost,
            ),
          ],
        ),
        body: ListView(
          controller: _pageScroll,
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DButton(
                  label: const Text('Open styleguide'),
                  onPressed: () => showComponentStyleguide(context),
                ),
                DButton(
                  label: const Text('Light / dark'),
                  onPressed: () => setState(() => _dark = !_dark),
                ),
                DButton(
                  label: const Text('Plum palette'),
                  onPressed: () => setState(() => _plum = !_plum),
                ),
                DButton(
                  label: const Text('360px'),
                  onPressed: () => setState(() => _narrow = !_narrow),
                ),
                DButton(
                  label: const Text('200% text'),
                  onPressed: () => setState(() => _large = !_large),
                ),
                DButton(
                  label: const Text('RTL'),
                  onPressed: () => setState(() => _rtl = !_rtl),
                ),
                DButton(
                  label: const Text('Reduced motion'),
                  onPressed: () => setState(() => _reduced = !_reduced),
                ),
                DButton(
                  label: const Text('Catalogue examples'),
                  variant: _surface == _ReviewSurface.examples
                      ? DButtonVariant.primary
                      : DButtonVariant.secondary,
                  onPressed: () =>
                      setState(() => _surface = _ReviewSurface.examples),
                ),
                DButton(
                  label: const Text('Production channel'),
                  variant: _surface == _ReviewSurface.channel
                      ? DButtonVariant.primary
                      : DButtonVariant.secondary,
                  onPressed: () =>
                      setState(() => _surface = _ReviewSurface.channel),
                ),
                DButton(
                  label: const Text('Production thread'),
                  variant: _surface == _ReviewSurface.thread
                      ? DButtonVariant.primary
                      : DButtonVariant.secondary,
                  onPressed: () =>
                      setState(() => _surface = _ReviewSurface.thread),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_surface == _ReviewSurface.examples) ...[
              DropdownButton<int>(
                value: _example,
                items: [
                  for (
                    var index = 0;
                    index < messageScrollerExamples.examples.length;
                    index++
                  )
                    DropdownMenuItem(
                      value: index,
                      child: Text(
                        messageScrollerExamples.examples[index].title,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _example = value);
                },
              ),
              const SizedBox(height: 16),
            ],
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: _narrow ? 360 : 720,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(_large ? 2 : 1),
                    disableAnimations: _reduced,
                  ),
                  child: Directionality(
                    textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: Builder(
                      builder: (context) => switch (_surface) {
                        _ReviewSurface.examples =>
                          messageScrollerExamples.examples[_example].builder(
                            context,
                          ),
                        _ReviewSurface.channel => _ProductionTranscript(
                          messages: widget.messages
                              .where((message) => message.threadId == null)
                              .toList(),
                          target: const ChatChannelTarget(9),
                          label: 'Production channel transcript',
                        ),
                        _ReviewSurface.thread => _ProductionTranscript(
                          messages: widget.messages
                              .where((message) => message.threadId == 77)
                              .toList(),
                          target: const ChatThreadTarget(
                            channelId: 9,
                            threadId: 77,
                          ),
                          label: 'Production thread transcript',
                        ),
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

enum _ReviewSurface { examples, channel, thread }

class _ProductionTranscript extends StatelessWidget {
  const _ProductionTranscript({
    required this.messages,
    required this.target,
    required this.label,
  });

  final List<ChatMessage> messages;
  final ChatStreamTarget target;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ids = messages.map((message) => message.id).toList();
    final lastRead = ids.length > 3 ? ids[ids.length - 3] : ids.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        DCard(
          child: SizedBox(
            height: 520,
            child: ChatMessageStream(
              siteUrl: _reviewSite,
              target: target,
              items: buildChatStream(
                messages,
                lastReadMessageId: lastRead,
                newestMessageId: ids.last,
              ),
              stream: ChatStreamState(
                messageIds: ids,
                fetchedOnce: true,
                fetches: 1,
                lastReadOnOpen: lastRead,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const _reviewSite = 'https://message-scroller-review.example';

Future<PluginHostHarness> _reviewHost(List<ChatMessage> messages) async {
  final host = await PluginHostHarness.open(
    transport: RecordingPluginTransport(),
    manifest: bundledPluginManifest,
    sites: const [
      PluginHostSite(
        url: _reviewSite,
        title: 'Message Scroller Review',
        apiKey: 'review-key',
        user: PluginHostUser(id: 1, username: 'reviewer'),
      ),
    ],
  );
  host.require(chatControllerService)
    ..putRecordForTesting(
      _reviewSite,
      const ChatChannel(
        id: 9,
        title: 'Design review',
        kind: ChatChannelKind.category,
        membership: ChatMembership(following: true, lastReadMessageId: 10),
        threadingEnabled: true,
      ),
    )
    ..putRecordsForTesting(_reviewSite, messages);
  return host;
}

List<ChatMessage> _reviewMessages() => [
  for (var id = 1; id <= 16; id++)
    ChatMessage(
      id: id,
      channelId: 9,
      cooked: id == 8
          ? '<p>A variable-height channel message checks resize preservation. '
                'It also keeps the real cooked-content, selection and action '
                'owners mounted inside the production row.</p>'
          : '<p>Channel message $id from the production timeline.</p>',
      author: ChatMessageAuthor(
        id: id.isEven ? 1 : 2,
        username: id.isEven ? 'reviewer' : 'sam',
      ),
      createdAt: DateTime.utc(2026, 9, 9, 9).add(Duration(minutes: id * 2)),
    ),
  for (var id = 101; id <= 112; id++)
    ChatMessage(
      id: id,
      channelId: 9,
      threadId: 77,
      cooked: '<p>Thread reply ${id - 100} in the production timeline.</p>',
      author: ChatMessageAuthor(
        id: id.isEven ? 1 : 3,
        username: id.isEven ? 'reviewer' : 'kai',
      ),
      createdAt: DateTime.utc(2026, 9, 9, 10).add(Duration(minutes: id - 100)),
    ),
];
