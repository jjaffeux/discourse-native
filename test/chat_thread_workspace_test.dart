import 'dart:ui' show CheckedState, PointerDeviceKind;

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_composer.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread_panel_width_store.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread_view.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
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

const ChatThread _editableThread = ChatThread(
  id: _threadId,
  channelId: _channelId,
  status: 'open',
  replyCount: 5,
  title: _threadTitle,
  membership: ChatThreadMembership(
    threadId: _threadId,
    notificationLevel: ChatThreadNotificationLevel.tracking,
  ),
  originalMessage: ChatThreadOriginalMessage(
    id: 10,
    channelId: _channelId,
    author: ChatMessageAuthor(id: 7, username: 'reader', name: 'Reader'),
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

ChatMessagePage _workspaceMessagesPage(int first, {int? threadId}) => (
  messages: [
    for (var id = first; id < first + 80; id++)
      ChatMessage(
        id: id,
        channelId: _channelId,
        cooked: '<p>Message $id</p>',
        author: const ChatMessageAuthor(id: 2, username: 'sam', name: 'Sam'),
        createdAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: id)),
        threadId: threadId,
      ),
  ],
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

  testWidgets('Settings releases and restores the active thread view', (
    tester,
  ) async {
    final fixture = await _fixture();
    addTearDown(fixture.shell.dispose);
    await _pumpWorkspace(tester, fixture.shell, width: 1000);

    final tracker = FakeSiteTracker.built.singleWhere(
      (tracker) => tracker.siteUrl == _siteUrl,
    );
    const threadChannel = '/chat/9/thread/3';
    expect(tracker.pluginChannelCallbacks[threadChannel], isNotEmpty);

    fixture.shell.selectSettings();
    expect(tracker.pluginChannelCallbacks[threadChannel], isEmpty);

    expect(fixture.shell.handleBack(), isTrue);
    expect(tracker.pluginChannelCallbacks[threadChannel], isNotEmpty);
  });

  testWidgets(
    'expanded thread route shows channel and thread panes at 1440 logical pixels',
    (tester) async {
      SharedPreferences.setMockInitialValues(const {
        ChatThreadPanelWidthStore.storageKey: 480.0,
      });
      final fixture = await _fixture();
      addTearDown(fixture.shell.dispose);
      final semantics = tester.ensureSemantics();
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
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
        expect(
          tester
              .widgetList<ChatUploadDropRegion>(
                find.byType(ChatUploadDropRegion),
              )
              .map((region) => region.title),
          containsAll([
            'Drop images to upload to #$_channelTitle',
            'Drop images to upload to this thread',
          ]),
        );

        final divider = find.bySemanticsLabel('Thread pane width');
        expect(divider, findsOneWidget);
        expect(tester.getSize(divider).width, 9);
        final border = find.byKey(const ValueKey('chat-thread-divider-border'));
        expect(tester.getSize(border), Size(1, tester.getSize(divider).height));
        final channelPane = find.byKey(const ValueKey('chat-channel-pane'));
        final threadPane = find.byKey(const ValueKey('chat-thread-pane'));
        final channelStream = find.descendant(
          of: channelPane,
          matching: find.byType(SuperListView),
        );
        final threadStream = find.descendant(
          of: threadPane,
          matching: find.byType(SuperListView),
        );
        final channelWidth = tester.getSize(channelPane).width;
        final threadWidth = tester.getSize(threadPane).width;
        final channelPadding =
            tester.widget<SuperListView>(channelStream).padding! as EdgeInsets;
        final threadPadding =
            tester.widget<SuperListView>(threadStream).padding! as EdgeInsets;
        final channelInset = channelWidth > 825
            ? (channelWidth - 825) / 2
            : 0.0;
        final threadInset = threadWidth > 825 ? (threadWidth - 825) / 2 : 0.0;
        expect(tester.getSize(channelStream).width, channelWidth);
        expect(tester.getSize(threadStream).width, threadWidth);
        expect(channelPadding.left, closeTo(channelInset, 0.001));
        expect(channelPadding.right, closeTo(channelInset, 0.001));
        expect(threadPadding.left, closeTo(threadInset, 0.001));
        expect(threadPadding.right, closeTo(threadInset, 0.001));
        expect(channelPadding.vertical, 16);
        expect(threadPadding.vertical, 16);
        expect(
          tester
              .getSize(
                find.descendant(
                  of: channelPane,
                  matching: find.byType(ChatComposer),
                ),
              )
              .width,
          channelWidth,
        );
        expect(
          tester
              .getSize(
                find.descendant(
                  of: threadPane,
                  matching: find.byType(ChatComposer),
                ),
              )
              .width,
          threadWidth,
        );
        expect(
          tester.getTopRight(channelPane).dx,
          tester.getTopLeft(border).dx,
        );
        expect(tester.getTopRight(border).dx, tester.getTopLeft(threadPane).dx);
        final theme = Theme.of(tester.element(border));
        expect(
          tester
              .widget<ColoredBox>(
                find.descendant(of: border, matching: find.byType(ColoredBox)),
              )
              .color,
          theme.shell.divider,
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
        debugDefaultTargetPlatformOverride = previousPlatform;
        semantics.dispose();
      }
    },
  );

  testWidgets('split route moves only the active chat stream', (tester) async {
    final fixture = await _fixture(
      channelPage: _workspaceMessagesPage(1),
      threadPage: _workspaceMessagesPage(101, threadId: _threadId),
    );
    addTearDown(fixture.shell.dispose);

    await _pumpWorkspace(tester, fixture.shell, width: 1440);

    final channelList = find.descendant(
      of: find.byKey(const ValueKey('chat-channel-pane')),
      matching: find.byType(SuperListView),
    );
    final threadList = find.descendant(
      of: find.byKey(const ValueKey('chat-thread-pane')),
      matching: find.byType(SuperListView),
    );
    final channelScroll = tester
        .widget<SuperListView>(channelList)
        .controller!
        .position;
    final threadScroll = tester
        .widget<SuperListView>(threadList)
        .controller!
        .position;
    expect(channelScroll.pixels, 0);
    expect(threadScroll.pixels, 0);

    final focusedEditors = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .where((editor) => editor.focusNode.hasFocus);
    expect(focusedEditors, hasLength(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(channelScroll.pixels, 0);
    expect(threadScroll.pixels, 0);

    // Interacting with the thread gives its list shortcut ownership without
    // moving the channel beside it.
    await tester.tap(threadList);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(channelScroll.pixels, 0);
    expect(threadScroll.pixels, closeTo(threadScroll.maxScrollExtent, 0.1));
    expect(threadScroll.pixels, greaterThan(0));

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(threadScroll.pixels, 0);

    // Interacting with the channel transfers shortcut ownership to its pane.
    await tester.tap(channelList);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(channelScroll.pixels, closeTo(channelScroll.maxScrollExtent, 0.1));
    expect(channelScroll.pixels, greaterThan(0));
    expect(threadScroll.pixels, 0);
  });

  testWidgets('thread notification choices use an anchored descriptive menu', (
    tester,
  ) async {
    final fixture = await _fixture();
    addTearDown(fixture.shell.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await _pumpWorkspace(tester, fixture.shell, width: 1000);

      final trigger = find.byTooltip('Thread notifications');
      final triggerRect = tester.getRect(trigger);
      DIconData triggerIcon() => tester
          .widget<DIcon>(
            find.descendant(of: trigger, matching: find.byType(DIcon)),
          )
          .icon;
      expect(triggerIcon(), DIcons.bell);

      await tester.tap(trigger);
      await tester.pumpAndSettle();

      final surface = find.byKey(const ValueKey('choice-menu-surface'));
      expect(surface, findsOneWidget);
      expect(tester.getSize(surface).width, 336);
      expect(
        tester.getTopLeft(surface).dy,
        inInclusiveRange(triggerRect.bottom + 8, triggerRect.bottom + 12),
      );
      expect(find.text('Thread notifications'), findsOneWidget);
      expect(find.text('Mentions only'), findsOneWidget);
      expect(find.text('Mentions and unread reply count'), findsOneWidget);
      expect(find.text('Every reply and unread count'), findsOneWidget);
      expect(find.byType(PopupMenuButton), findsNothing);

      Finder option(ChatThreadNotificationLevel level) =>
          find.byKey(ValueKey(('choice-menu-option', level)));
      List<DIconData> optionIcons(ChatThreadNotificationLevel level) => tester
          .widgetList<DIcon>(
            find.descendant(of: option(level), matching: find.byType(DIcon)),
          )
          .map((widget) => widget.icon)
          .toList();

      expect(
        optionIcons(ChatThreadNotificationLevel.normal),
        contains(DIcons.farBell),
      );
      expect(
        optionIcons(ChatThreadNotificationLevel.tracking),
        contains(DIcons.bell),
      );
      expect(
        optionIcons(ChatThreadNotificationLevel.watching),
        contains(DIcons.discourseBellExclamation),
      );

      final normalBackground = find.byKey(
        const ValueKey((
          'choice-menu-option-background',
          ChatThreadNotificationLevel.normal,
        )),
      );
      final trackingBackground = find.byKey(
        const ValueKey((
          'choice-menu-option-background',
          ChatThreadNotificationLevel.tracking,
        )),
      );
      expect(
        tester.getTopLeft(trackingBackground).dy -
            tester.getBottomLeft(normalBackground).dy,
        4,
      );
      Color backgroundColor() =>
          (tester.widget<AnimatedContainer>(normalBackground).decoration!
                  as BoxDecoration)
              .color!;
      expect(backgroundColor(), Colors.transparent);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(option(ChatThreadNotificationLevel.normal)),
      );
      await tester.pumpAndSettle();

      expect(backgroundColor(), isNot(Colors.transparent));

      final selected = tester.getSemantics(
        find.byKey(
          const ValueKey((
            'choice-menu-option',
            ChatThreadNotificationLevel.tracking,
          )),
        ),
      );
      expect(
        selected.getSemanticsData().flagsCollection.isChecked,
        CheckedState.isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(surface, findsNothing);
      expect(fixture.api.chatThreadNotificationLevelsUpdated, const [
        (
          channelId: _channelId,
          threadId: _threadId,
          notificationLevel: ChatThreadNotificationLevel.watching,
        ),
      ]);
      expect(triggerIcon(), DIcons.discourseBellExclamation);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('thread notification menu respects reduced motion', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    final fixture = await _fixture();
    addTearDown(fixture.shell.dispose);

    await _pumpWorkspace(tester, fixture.shell, width: 1000);
    await tester.tap(find.byTooltip('Thread notifications'));
    await tester.pump();

    final surface = find.byKey(const ValueKey('choice-menu-surface'));
    expect(surface, findsOneWidget);
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: surface, matching: find.byType(FadeTransition)).first,
    );
    final scale = tester.widget<ScaleTransition>(
      find.ancestor(of: surface, matching: find.byType(ScaleTransition)).first,
    );
    expect(fade.opacity.value, 1);
    expect(scale.scale.value, 1);
  });

  testWidgets('Arrow Up edits the last current-user message in a thread', (
    tester,
  ) async {
    final fixture = await _fixture(
      threadPage: (
        messages: [
          ChatMessage(
            id: 51,
            channelId: _channelId,
            raw: 'thread reply from reader',
            cooked: '<p>thread reply from reader</p>',
            author: const ChatMessageAuthor(
              id: 7,
              username: 'reader',
              name: 'Reader',
            ),
            createdAt: DateTime.utc(2026, 8, 11, 10),
            threadId: _threadId,
          ),
          ChatMessage(
            id: 52,
            channelId: _channelId,
            raw: 'later reply from Sam',
            cooked: '<p>later reply from Sam</p>',
            author: const ChatMessageAuthor(
              id: 2,
              username: 'sam',
              name: 'Sam',
            ),
            createdAt: DateTime.utc(2026, 8, 11, 11),
            threadId: _threadId,
          ),
        ],
        canLoadMorePast: false,
        canLoadMoreFuture: false,
        targetMessageId: null,
      ),
    );
    addTearDown(fixture.shell.dispose);
    await _pumpWorkspace(tester, fixture.shell, width: 1000);

    final threadView = find.byType(ChatThreadView);
    final field = find.descendant(
      of: threadView,
      matching: find.byType(TextField),
    );
    await tester.tap(field);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: threadView,
        matching: find.byKey(const ValueKey('chat-composer-edit-cancel')),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(field).controller!.text,
      'thread reply from reader',
    );
  });

  testWidgets('original author can edit the thread title', (tester) async {
    final fixture = await _fixture(editableThread: true);
    addTearDown(fixture.shell.dispose);

    await _pumpWorkspace(tester, fixture.shell, width: 1000);

    expect(find.byTooltip('Thread settings'), findsOneWidget);
    await tester.tap(find.byTooltip('Thread settings'));
    await tester.pumpAndSettle();

    expect(find.text('Thread settings'), findsOneWidget);
    final titleField = find.byKey(const ValueKey('chat-thread-title-field'));
    expect(titleField, findsOneWidget);
    expect(tester.widget<TextField>(titleField).maxLength, 100);

    await tester.enterText(titleField, 'Deploy plan');
    await tester.tap(find.byKey(const ValueKey('chat-thread-title-save')));
    await tester.pumpAndSettle();

    expect(fixture.api.chatThreadTitlesUpdated, const [
      (channelId: _channelId, threadId: _threadId, title: 'Deploy plan'),
    ]);
    expect(find.text('Thread settings'), findsNothing);
    expect(find.text('Deploy plan'), findsOneWidget);
  });

  testWidgets('thread notification choices use a sheet on touch', (
    tester,
  ) async {
    final fixture = await _fixture();
    addTearDown(fixture.shell.dispose);

    await _pumpWorkspace(
      tester,
      fixture.shell,
      width: 390,
      platform: TargetPlatform.iOS,
    );

    await tester.tap(find.byTooltip('Thread notifications'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('choice-menu-surface')), findsNothing);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.text('Thread notifications'), findsOneWidget);
    expect(find.text('Mentions and unread reply count'), findsOneWidget);

    await tester.tap(find.text('Normal'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Close'), findsNothing);
    expect(
      fixture.api.chatThreadNotificationLevelsUpdated.single.notificationLevel,
      ChatThreadNotificationLevel.normal,
    );
  });

  test(
    'panel width store restores positive finite widths and ignores invalid values',
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
  expect(editor.enableDropTarget, isFalse);
  expect(editor.composer.target.siteUrl, _siteUrl);
  expect(editor.composer.target.policy?.kind, ChatPlugin.messageComposerTarget);
  expect(editor.composer.target.data[ChatPlugin.composerChannelId], _channelId);
  expect(editor.composer.target.data[ChatPlugin.composerThreadId], _threadId);
  expect(editor.composer.target.draftKey, 'chat_9_thread_3');
  final dropRegion = tester.widget<ChatUploadDropRegion>(
    find.descendant(
      of: threadView,
      matching: find.byType(ChatUploadDropRegion),
    ),
  );
  expect(dropRegion.title, 'Drop images to upload to this thread');
}

Future<({ShellController shell, _WorkspaceApi api})> _fixture({
  bool terminalThread = false,
  bool editableThread = false,
  ChatMessagePage channelPage = _channelPage,
  ChatMessagePage threadPage = _threadPage,
}) async {
  final api = _WorkspaceApi(
    terminalThread: terminalThread,
    thread: editableThread ? _editableThread : _thread,
    channelPage: channelPage,
    threadPage: threadPage,
  );
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
    plugins: installedPlugins,
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
  TargetPlatform? platform,
}) async {
  tester.view.physicalSize = Size(width, width < 600 ? 844 : 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(
          platform: platform ?? TargetPlatform.macOS,
        ),
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
  _WorkspaceApi({
    this.terminalThread = false,
    this.thread = _thread,
    ChatMessagePage channelPage = _channelPage,
    ChatMessagePage threadPage = _threadPage,
  }) : super(
         user: _reader,
         totals: chatNotificationTotals(),
         feeds: const {'/latest.json': []},
         chatChannelsBySite: const {
           _siteUrl: ChatChannels(public: [_channel]),
         },
         chatMessagesByKey: {'9': channelPage, 'thread-9-3': threadPage},
         chatThreadsByKey: {'9~3': thread},
       );

  final bool terminalThread;
  final ChatThread thread;
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
