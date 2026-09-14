import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../app_shortcuts.dart';
import '../models/bookmark.dart';
import '../models/content_route.dart';
import '../plugin_api/plugin_scope.dart';
import 'composer_presentation.dart';
import 'keyboard_navigation.dart';
import 'platform.dart';
import 'shell_scope.dart';
import 'topic_list_bottom_bar.dart';
import 'topic_sheet_scope.dart';
import 'topic_view.dart';

typedef _TopicSheetState = ({
  String? siteUrl,
  String? tabId,
  ContentRoute? route,
  bool canReply,
  bool bookmarkBusy,
  bool isConnected,
});

/// A local Navigator keeps the sheet below window chrome and retains the page
/// underneath it, including while the desktop switches between shell widths.
class DesktopTopicSheetHost extends StatelessWidget {
  const DesktopTopicSheetHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.isTouch) return child;
    return LayoutBuilder(
      builder: (context, bounds) => MediaQuery(
        data: MediaQuery.of(context).copyWith(size: bounds.biggest),
        child: Navigator(
          pages: [
            MaterialPage<void>(
              key: const ValueKey('desktop-topic-background'),
              child: _TopicSheetRouteHost(child: child),
            ),
          ],
          onDidRemovePage: (_) {},
        ),
      ),
    );
  }
}

class _TopicSheetRouteHost extends StatelessWidget {
  const _TopicSheetRouteHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final expanded = ComposerPresentationHost.sheetExpandedOf(context);
    return ShellSelector<_TopicSheetState>(
      select: (shell) {
        final site = shell.currentInstance;
        final topic = shell.currentTopic;
        return (
          siteUrl: site?.url,
          tabId: shell.activeTabId,
          route: shell.forumActive && shell.currentContent?.isTopic == true
              ? shell.currentContent
              : null,
          canReply: shell.canReplyHere,
          bookmarkBusy:
              site != null &&
              topic != null &&
              shell.bookmarkWriteInFlight(
                siteUrl: site.url,
                topicId: topic.id,
                targetType: BookmarkTargetType.topic,
                targetId: topic.id,
              ),
          isConnected: site?.isConnected == true,
        );
      },
      builder: (context, state, _) {
        final shell = ShellScope.read(context);
        final route = state.route;
        void close() {
          if (shell.currentInstance?.url == state.siteUrl &&
              shell.activeTabId == state.tabId &&
              shell.currentContent?.topicId == route?.topicId) {
            shell.closeTopicSheet();
          }
        }

        final available = MediaQuery.sizeOf(context).width;
        final readingWidth = math.min(840.0, math.max(480.0, available * .64));
        final width = expanded
            ? math.min(1380.0, math.max(readingWidth, available - 76))
            : readingWidth;
        return DSheet<void>(
          open: route != null,
          onOpenChanged: (details) {
            if (!details.open) close();
          },
          barrierLabel: 'Close topic sheet',
          routeSettings: const RouteSettings(name: 'desktop-topic-sheet'),
          trigger: DSheetTrigger(
            builder: (context, _) =>
                TopicSheetScope(background: true, child: child),
          ),
          content: DSheetContent(
            key: const ValueKey('desktop-topic-sheet'),
            inset: true,
            animateSize: true,
            sidePanelWidth: width,
            sidePanelMaxWidth: 1380,
            showCloseButton: false,
            scrollWholeSheet: false,
            semanticLabel: route?.title ?? 'Topic',
            children: [
              Expanded(
                child: route == null
                    ? const SizedBox.shrink()
                    : TopicSheetScope(
                        background: false,
                        onClose: close,
                        child: Builder(
                          builder: (readerContext) => ReadingShortcuts(
                            sequenceContext: (
                              state.siteUrl,
                              state.tabId,
                              route,
                            ),
                            commands: {
                              ReadingCommand.back: () {
                                close();
                                return true;
                              },
                              ReadingCommand.openNextTopic: () =>
                                  openAdjacentTopic(
                                    readerContext,
                                    next: true,
                                    fromKeyboard: true,
                                  ),
                              ReadingCommand.openPreviousTopic: () =>
                                  openAdjacentTopic(
                                    readerContext,
                                    next: false,
                                    fromKeyboard: true,
                                  ),
                            },
                            child: ComposerDock(
                              key: const ValueKey('topic-sheet-composer-dock'),
                              topicId: route.topicId,
                              siteUrl: state.siteUrl,
                              tabId: state.tabId,
                              child: TopicView(
                                key: ValueKey((
                                  state.siteUrl,
                                  state.tabId,
                                  route.topicId,
                                )),
                                inbox: true,
                                route: route,
                                canReturnToSidebar: false,
                                canReply: state.canReply,
                                bookmarkBusy: state.bookmarkBusy,
                                isConnected: state.isConnected,
                                registry: PluginScope.of(context).registry,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
