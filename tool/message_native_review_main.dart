import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/examples/message_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/bundled_plugins.dart';
import '../test/support/chat_shell.dart';
import '../test/support/fakes.dart';

const _siteUrl = 'https://message-review.invalid';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await _reviewController();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(_MessageNativeReviewApp(controller: controller));
}

Future<ShellController> _reviewController() async {
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      const DiscourseInstance(
        url: _siteUrl,
        title: 'Message review',
        apiVersion: 4,
        user: DiscourseUser(id: 1, username: 'reviewer'),
      ),
    ]),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'local-review-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: installedPlugins,
  );
  await controller.load();
  controller.chatRecords.put(
    _siteUrl,
    const ChatChannel(
      id: 9,
      title: 'Component review',
      kind: ChatChannelKind.category,
      canDeleteSelf: true,
      canManagePins: true,
      membership: ChatMembership(following: true),
    ),
  );
  for (final message in _messages) {
    controller.chatRecords.put(_siteUrl, message);
  }
  return controller;
}

final _messages = [
  const ChatMessage(
    id: 101,
    channelId: 9,
    cooked:
        '<p>The production tile keeps <strong>CookedHtml</strong>, selection, uploads, reactions and thread state.</p>',
    raw: 'The production tile keeps CookedHtml and domain state.',
    author: ChatMessageAuthor(id: 2, username: 'olivia', name: 'Olivia'),
    edited: true,
    pinned: true,
    uploads: [
      ChatUpload(
        id: 7,
        url: '/uploads/review.pdf',
        originalFilename: 'message-review.pdf',
        kind: ChatUploadKind.attachment,
        humanFilesize: '2.4 MB',
      ),
    ],
    reactions: [ChatReaction(emoji: 'thumbsup', count: 3)],
    thread: ChatThreadPreview(
      threadId: 33,
      replyCount: 4,
      lastReplyExcerpt: 'The app adapter still owns this thread preview.',
      lastReplyUser: ChatMessageAuthor(id: 3, username: 'sam', name: 'Sam'),
      participantCount: 2,
      participantUsers: [
        ChatMessageAuthor(id: 3, username: 'sam', name: 'Sam'),
        ChatMessageAuthor(id: 4, username: 'lee', name: 'Lee'),
      ],
    ),
  ),
  const ChatMessage(
    id: 102,
    channelId: 9,
    cooked: '<p>This is the chained follow-up row.</p>',
    raw: 'This is the chained follow-up row.',
    author: ChatMessageAuthor(id: 2, username: 'olivia', name: 'Olivia'),
    replyTo: ChatReplyTo(
      id: 101,
      userId: 2,
      excerpt: 'The production tile keeps CookedHtml…',
      username: 'olivia',
    ),
  ),
  const ChatMessage(
    id: 103,
    channelId: 9,
    cooked: '<p>Outgoing delivery failed; retry remains app-owned.</p>',
    raw: 'Outgoing delivery failed; retry remains app-owned.',
    author: ChatMessageAuthor(id: 1, username: 'reviewer', name: 'Reviewer'),
    delivery: ChatMessageDelivery.failed,
    sendError: 'Offline during review',
  ),
  ChatMessage(
    id: 104,
    channelId: 9,
    cooked: '<p>This message was deleted.</p>',
    raw: 'This message was deleted.',
    author: const ChatMessageAuthor(id: 2, username: 'olivia', name: 'Olivia'),
    deletedAt: DateTime.utc(2026, 9, 9),
  ),
];

class _MessageNativeReviewApp extends StatefulWidget {
  const _MessageNativeReviewApp({required this.controller});

  final ShellController controller;

  @override
  State<_MessageNativeReviewApp> createState() =>
      _MessageNativeReviewAppState();
}

class _MessageNativeReviewAppState extends State<_MessageNativeReviewApp> {
  var dark = false;
  var plum = false;
  var narrow = false;
  var largeText = false;
  var rtl = false;
  var reducedMotion = false;
  var showProduction = false;

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: widget.controller,
    child: PluginUiScope.own(
      chatPluginId,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: plum
            ? StyleguideTheme.plum.resolve(AppTheme.light)
            : dark
            ? AppTheme.dark
            : AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Message Review 8953')),
            body: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _toggle('Light / dark', () => dark = !dark),
                    _toggle('Plum palette', () => plum = !plum),
                    _toggle('360px', () => narrow = !narrow),
                    _toggle('200% text', () => largeText = !largeText),
                    _toggle('RTL', () => rtl = !rtl),
                    _toggle(
                      'Reduced motion',
                      () => reducedMotion = !reducedMotion,
                    ),
                    _toggle(
                      showProduction ? 'Show examples' : 'Show production',
                      () => showProduction = !showProduction,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Center(
                  child: SizedBox(
                    width: narrow ? 360 : 640,
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(largeText ? 2 : 1),
                        disableAnimations: reducedMotion,
                      ),
                      child: Directionality(
                        textDirection: rtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: showProduction
                            ? const _ProductionTiles()
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final example
                                      in messageExamples.examples) ...[
                                    Text(
                                      example.title,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Builder(builder: example.builder),
                                    const SizedBox(height: 32),
                                  ],
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _toggle(String label, VoidCallback mutation) => DButton(
    label: Text(label),
    onPressed: () => setState(mutation),
    size: DButtonSize.small,
  );
}

class _ProductionTiles extends StatefulWidget {
  const _ProductionTiles();

  @override
  State<_ProductionTiles> createState() => _ProductionTilesState();
}

class _ProductionTilesState extends State<_ProductionTiles> {
  var result = 'No production action yet';

  void record(String action) => setState(() => result = action);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Actual ChatMessageTile with local records',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      ChatMessageTile(
        siteUrl: _siteUrl,
        messageId: 101,
        chained: false,
        onOpenThread: (_) => record('Opened thread 33'),
        onJumpToMessage: (_) => record('Jumped to message 101'),
        onReply: (_) => record('Reply requested for message 101'),
        onEdit: (_) => record('Edit requested for message 101'),
      ),
      ChatMessageTile(
        siteUrl: _siteUrl,
        messageId: 102,
        chained: true,
        onJumpToMessage: (_) => record('Jumped to message 101'),
        onReply: (_) => record('Reply requested for message 102'),
      ),
      ChatMessageTile(
        siteUrl: _siteUrl,
        messageId: 103,
        chained: false,
        onReply: (_) => record('Reply requested for message 103'),
      ),
      const ChatMessageTile(siteUrl: _siteUrl, messageId: 104, chained: false),
      const SizedBox(height: 16),
      Text(result),
    ],
  );
}
