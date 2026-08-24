import 'package:discourse_native/src/data/chat_thread_panel_width_store.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_composer.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread_view.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const String _siteUrl = 'https://meta.discourse.org';
const int _channelId = 9;
const int _threadId = 3;
const String _channelTitle = 'Support';
const String _threadTitle = 'Rate limiting logging added by Discourse';
const DiscourseUser _reader = DiscourseUser(
  id: 7,
  username: 'reader',
  name: 'Reader',
);

const ChatChannel _channel = ChatChannel(
  id: _channelId,
  title: _channelTitle,
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: true),
  threadingEnabled: true,
);

const ChatThread _thread = ChatThread(
  id: _threadId,
  channelId: _channelId,
  status: 'open',
  replyCount: 5,
  title: _threadTitle,
  membership: ChatThreadMembership(
    threadId: _threadId,
    notificationLevel: ChatThreadNotificationLevel.tracking,
  ),
);

const ChatMessage _threadOriginal = ChatMessage(
  id: 41,
  channelId: _channelId,
  cooked: '<p>Original message inside the thread</p>',
  author: ChatMessageAuthor(id: 2, username: 'sam', name: 'Sam'),
  threadId: _threadId,
  thread: ChatThreadPreview(threadId: _threadId, replyCount: 5),
);

const ChatMessage _channelOriginal = ChatMessage(
  id: 10,
  channelId: _channelId,
  cooked: '<p>Open the existing thread</p>',
  author: ChatMessageAuthor(id: 2, username: 'sam', name: 'Sam'),
  threadId: _threadId,
  thread: ChatThreadPreview(
    threadId: _threadId,
    replyCount: 5,
    lastReplyId: 41,
  ),
);

const ChatMessagePage _channelPage = (
  messages: <ChatMessage>[_channelOriginal],
  canLoadMorePast: false,
  canLoadMoreFuture: false,
  targetMessageId: null,
);

const ChatMessagePage _threadPage = (
  messages: <ChatMessage>[_threadOriginal],
  canLoadMorePast: false,
  canLoadMoreFuture: false,
  targetMessageId: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  for (final width in const [390.0, 1000.0]) {
    testWidgets(
      'thread route replaces the channel at ${width.toInt()} logical pixels',
      (tester) async {
        final fixture = await _fixture();
        addTearDown(fixture.shell.dispose);

        await _pumpWorkspace(tester, fixture.shell, width: width);

        expect(fixture.shell.currentContent?.id, 'chat-c-9-t-3');
        expect(find.byType(ChatThreadWorkspace), findsOneWidget);
        expect(find.byType(ChatChannelView), findsNothing);
        expect(find.byTooltip('Back'), findsOneWidget);
        expect(find.text(_threadTitle), findsOneWidget);
        expect(find.byTooltip('Thread notifications'), findsOneWidget);
        expect(find.byTooltip('Close thread'), findsNothing);
        expect(find.bySemanticsLabel('Thread pane width'), findsNothing);
        _expectThreadBodyTargets(tester);

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();

        expect(fixture.shell.currentContent?.id, 'chat-c-9');
        expect(find.byType(ChatThreadWorkspace), findsNothing);
        expect(find.byType(ChatChannelView), findsOneWidget);
      },
    );
  }

  testWidgets(
    'expanded thread route shows channel and thread panes at 1440 logical pixels',
    (tester) async {
      SharedPreferences.setMockInitialValues(const {
        ChatThreadPanelWidthStore.storageKey: 480.0,
      });
      final fixture = await _fixture();
      addTearDown(fixture.shell.dispose);
      final semantics = tester.ensureSemantics();
      try {
        await _pumpWorkspace(tester, fixture.shell, width: 1440);

        expect(fixture.shell.currentContent?.id, 'chat-c-9-t-3');
        expect(find.byType(ChatThreadWorkspace), findsOneWidget);
        expect(find.byType(ChatChannelView), findsOneWidget);
        expect(find.byType(ChatThreadView), findsOneWidget);
        expect(find.byTooltip('Back'), findsNothing);
        expect(find.text(_channelTitle), findsOneWidget);
        expect(find.text(_threadTitle), findsOneWidget);
        expect(find.byTooltip('Thread notifications'), findsOneWidget);
        expect(find.byTooltip('Close thread'), findsOneWidget);
        _expectThreadBodyTargets(tester);

        final divider = find.bySemanticsLabel('Thread pane width');
        expect(divider, findsOneWidget);
        expect(tester.getSize(divider).width, 8);
        final border = find.byKey(const ValueKey('chat-thread-divider-border'));
        expect(tester.getSize(border).width, 1);
        final theme = Theme.of(tester.element(border));
        expect(
          tester
              .widget<ColoredBox>(
                find.descendant(of: border, matching: find.byType(ColoredBox)),
              )
              .color,
          Color.alphaBlend(
            theme.colorScheme.onSurface.withValues(alpha: 0.12),
            theme.shell.divider,
          ),
        );
        final node = tester.getSemantics(divider);
        final data = node.getSemanticsData();
        expect(data.value, '480 pixels');
        expect(data.increasedValue, '504 pixels');
        expect(data.decreasedValue, '456 pixels');
        expect(data.hasAction(SemanticsAction.increase), isTrue);
        expect(data.hasAction(SemanticsAction.decrease), isTrue);

        tester.platformDispatcher.onSemanticsActionEvent!(
          SemanticsActionEvent(
            type: SemanticsAction.increase,
            viewId: tester.view.viewId,
            nodeId: node.id,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          (await SharedPreferences.getInstance()).getDouble(
            ChatThreadPanelWidthStore.storageKey,
          ),
          504,
        );

        await tester.tap(find.byTooltip('Close thread'));
        await tester.pumpAndSettle();

        expect(fixture.shell.currentContent?.id, 'chat-c-9');
        expect(find.byType(ChatThreadWorkspace), findsNothing);
        expect(find.byType(ChatChannelView), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  test(
    'panel width store restores a valid write and rejects invalid values',
    () async {
      final persistence = _MemoryPanelWidthPersistence();
      final store = ChatThreadPanelWidthStore(persistence: persistence);

      expect(await store.read(), isNull);

      await store.write(512);
      expect(persistence.writes, [512]);
      expect(
        await ChatThreadPanelWidthStore(persistence: persistence).read(),
        512,
      );

      await store.write(0);
      await store.write(-1);
      await store.write(double.nan);
      await store.write(double.infinity);
      expect(persistence.writes, [512]);

      persistence.width = double.infinity;
      expect(await store.read(), isNull);
    },
  );
}

void _expectThreadBodyTargets(WidgetTester tester) {
  final threadView = find.byType(ChatThreadView);
  expect(
    find.descendant(of: threadView, matching: find.byType(ChatMessageTile)),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: threadView,
      matching: find.byKey(ChatMessageTile.threadPreviewKey(_threadId)),
    ),
    findsNothing,
  );
  expect(
    find.descendant(of: threadView, matching: find.text('5 replies')),
    findsNothing,
  );

  final composerFinder = find.descendant(
    of: threadView,
    matching: find.byType(ChatComposer),
  );
  expect(composerFinder, findsOneWidget);
  final composer = tester.widget<ChatComposer>(composerFinder);
  expect(composer.siteUrl, _siteUrl);
  expect(composer.channelId, _channelId);
  expect(composer.threadId, _threadId);

  final editorFinder = find.descendant(
    of: threadView,
    matching: find.byType(ComposerEditor),
  );
  expect(editorFinder, findsOneWidget);
  final editor = tester.widget<ComposerEditor>(editorFinder);
  expect(editor.composer.target.siteUrl, _siteUrl);
  expect(editor.composer.target.chatChannelId, _channelId);
  expect(editor.composer.target.chatThreadId, _threadId);
  expect(editor.composer.target.draftKey, 'chat_9_thread_3');
}

Future<({ShellController shell, _WorkspaceApi api})> _fixture({
  bool terminalThread = false,
}) async {
  final api = _WorkspaceApi(terminalThread: terminalThread);
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      const DiscourseInstance(
        url: _siteUrl,
        title: 'Discourse Meta',
        apiVersion: 4,
        user: _reader,
      ),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    forumTabsEnabled: false,
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  await shell.load();
  await shell.chat.loadChannels(_siteUrl);
  shell.openChatThread(
    siteUrl: _siteUrl,
    channelId: _channelId,
    threadId: _threadId,
  );
  return (shell: shell, api: api);
}

Future<void> _pumpWorkspace(
  WidgetTester tester,
  ShellController shell, {
  required double width,
}) async {
  tester.view.physicalSize = Size(width, width < 600 ? 844 : 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: MainContent(layout: ShellLayout.forWidth(width))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _MemoryPanelWidthPersistence
    implements ChatThreadPanelWidthPersistence {
  double? width;
  final List<double> writes = [];

  @override
  Future<double?> readWidth() async => width;

  @override
  Future<bool> writeWidth(double width) async {
    writes.add(width);
    this.width = width;
    return true;
  }
}

final class _WorkspaceApi extends FakeDiscourseApi {
  _WorkspaceApi({this.terminalThread = false})
    : super(
        user: _reader,
        totals: const NotificationTotals(
          chatNotifications: 0,
          hasChatEnabled: true,
        ),
        feeds: const {'/latest.json': []},
        chatChannelsBySite: const {
          _siteUrl: ChatChannels(public: [_channel]),
        },
        chatMessagesByKey: const {'9': _channelPage, 'thread-9-3': _threadPage},
        chatThreadsByKey: const {'9~3': _thread},
      );

  final bool terminalThread;
  final List<({int channelId, int threadId, int messageId})> threadReads = [];

  @override
  Future<ChatThread> chatThread({
    required String siteUrl,
    required int channelId,
    required int threadId,
    String? apiKey,
    String? clientId,
  }) {
    if (terminalThread) {
      throw const SiteLookupException(
        SiteLookupFailure.unreachable,
        _siteUrl,
        statusCode: 404,
      );
    }
    return super.chatThread(
      siteUrl: siteUrl,
      channelId: channelId,
      threadId: threadId,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  @override
  Future<void> markChatThreadRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required int messageId,
    String? clientId,
  }) async {
    threadReads.add((
      channelId: channelId,
      threadId: threadId,
      messageId: messageId,
    ));
  }
}
