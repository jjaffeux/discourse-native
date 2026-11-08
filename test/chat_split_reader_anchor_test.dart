import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/desktop_panels.dart';
import 'package:discourse_native/src/shell/forum_tab_scope.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_presentation.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_thread_controller_test.dart' as threads;
import 'support/chat_scroll_fixture.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';

void main() {
  for (final thread in [false, true]) {
    testWidgets(
      'targeting a second visible ${thread ? 'thread' : 'channel'} reader preserves the first',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final shell = await chatScrollController(
          count: 120,
          reader: const DiscourseUser(id: 1, username: 'reader1'),
          configureApi: (api) {
            final all = api.chatMessagesByKey['9']!.messages;
            final messages = thread
                ? all
                      .map(
                        (message) => ChatMessage(
                          id: message.id,
                          channelId: 9,
                          threadId: 22,
                          cooked: message.cooked,
                          raw: message.raw,
                          author: message.author,
                          createdAt: message.createdAt,
                        ),
                      )
                      .toList()
                : all;
            final base = thread ? 'thread-9-22' : '9';
            api.chatMessagesByKey['$base~target~42'] = (
              messages: messages
                  .where((m) => m.id >= 35 && m.id <= 50)
                  .toList(),
              canLoadMorePast: false,
              canLoadMoreFuture: true,
              targetMessageId: 42,
            );
            api.chatMessagesByKey[base] = (
              messages: messages.where((m) => m.id >= 100).toList(),
              canLoadMorePast: false,
              canLoadMoreFuture: false,
              targetMessageId: null,
            );
            for (var id = 35; id <= 50; id++) {
              api.chatMessagesByKey['$base~future~$id'] = (
                messages: <ChatMessage>[],
                canLoadMorePast: false,
                canLoadMoreFuture: false,
                targetMessageId: null,
              );
            }
            if (thread) {
              api.chatThreadsByKey[FakeDiscourseApi.chatThreadKey(9, 22)] =
                  threads.threadDetail();
            }
          },
        );
        addTearDown(shell.dispose);
        shell.desktopTopicTabs = true;
        if (thread) {
          shell.pluginSession
              .require(chatShellService)
              .openThread(
                siteUrl: chatScrollSite,
                channelId: 9,
                threadId: 22,
                mainPanel: true,
              );
        } else {
          expect(shell.openChatChannel(9), isTrue);
        }
        final source = shell.activeTabId!;
        shell.openContentInNewTab(
          ContentRoute.topicList(TopicListMode.latest),
          panel: ForumPanel.secondary,
          select: true,
        );
        shell.selectTab(source);
        await tester.pumpWidget(
          ShellScope(
            controller: shell,
            child: MaterialApp(
              theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
              home: const TopicPresentationPreferences(
                child: Scaffold(body: DesktopPanels()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Finder readerScroll(String tabId) => find.descendant(
          of: find.byWidgetPredicate(
            (widget) => widget is ForumTabScope && widget.tabId == tabId,
          ),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.up,
          ),
        );
        expect(readerScroll(source), findsOneWidget);
        double sourcePixels() =>
            tester.state<ScrollableState>(readerScroll(source)).position.pixels;
        final before = sourcePixels();
        ChatMessageStream transcript(String id) =>
            tester.widget<ChatMessageStream>(
              find.descendant(
                of: find.byWidgetPredicate(
                  (widget) => widget is ForumTabScope && widget.tabId == id,
                ),
                matching: find.byType(ChatMessageStream),
              ),
            );
        final sourceIds = transcript(source).stream.messageIds;
        expect(
          sourceIds,
          unorderedEquals([for (var id = 100; id <= 120; id++) id]),
        );

        expect(
          await shell.pluginSession
              .require(chatShellService)
              .openPluginUrl(
                '$chatScrollSite/chat/c/-/9/${thread ? 't/22/' : ''}42',
                origin: PluginLinkOrigin.secondaryPanelNewTab,
              ),
          isTrue,
        );
        final destination = shell.tabsForCurrentForum.last.id;
        await tester.pumpAndSettle();
        expect(shell.activeTabId, source);
        expect(shell.chatNavigation.value?.messageId, 42);
        expect(sourcePixels(), closeTo(before, 1));

        shell.selectTab(destination);
        await tester.pumpAndSettle();

        expect(readerScroll(source), findsOneWidget);
        expect(readerScroll(destination), findsOneWidget);
        expect(sourcePixels(), closeTo(before, 1));
        expect(transcript(source).stream.messageIds, orderedEquals(sourceIds));
        expect(transcript(destination).stream.messageIds, contains(42));
        expect(transcript(destination).stream.messageIds, isNot(contains(120)));
        expect(
          find.descendant(
            of: find.byWidgetPredicate(
              (widget) =>
                  widget is ForumTabScope && widget.tabId == destination,
            ),
            matching: find.byKey(const ValueKey('chat-message-highlight')),
          ),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: const TargetPlatformVariant({TargetPlatform.macOS}),
    );
  }
}
