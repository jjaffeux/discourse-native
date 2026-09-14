import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../app_shortcuts.dart';
import '../models/bookmark.dart';
import '../models/content_route.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import 'keyboard_navigation.dart';
import 'platform.dart';
import 'reader_content_bounds.dart';
import 'shell_scope.dart';
import 'topic_list_bottom_bar.dart';
import 'topic_sheet_scope.dart';
import 'topic_view.dart';

const _idealTopicSheetWidth = 825.0;

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

        return DSheet<void>(
          open: route != null,
          onOpenChanged: (details) {
            if (!details.open) close();
          },
          barrierLabel: 'Close topic sheet',
          routeSettings: const TopicSheetRouteSettings(),
          trigger: DSheetTrigger(
            builder: (context, _) =>
                TopicSheetScope(background: true, child: child),
          ),
          content: DSheetContent(
            key: const ValueKey('desktop-topic-sheet'),
            inset: true,
            animateSize: true,
            // DSheet clamps to the workspace bounds, preserving its insets.
            sidePanelWidth: _idealTopicSheetWidth,
            sidePanelMaxWidth: _idealTopicSheetWidth,
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
                            child: ReaderContentBounds(
                              child: ColoredBox(
                                color: Theme.of(readerContext).shell.content,
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
              ),
            ],
          ),
        );
      },
    );
  }
}
