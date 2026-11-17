import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_browse_navigation.dart';
import 'chat_browse_skeleton.dart';
import 'chat_inbox.dart';
import 'chat_inbox_filters.dart';
import 'chat_listing.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

/// The Chats page, which is also chat's side on a phone: chat's list under
/// its controls, kept across a visit to a conversation.
class ChatMobileSidebar extends StatelessWidget {
  const ChatMobileSidebar({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    final shell = PluginUiScope.require(context, chatShellService);
    return DPageSurface.headed(
      title: Text(context.l10n.chats, key: const ValueKey('chat-inbox-title')),
      controls: ContentReadingLaneBox(
        padding: EdgeInsets.zero,
        child: ChatListingControls(
          siteUrl: siteUrl,
          place: ChatInboxPlace.page,
        ),
      ),
      adaptiveBodyBuilder: (context, lazy) => ContentReadingLane(
        builder: (context, lane) {
          final padding = lane.padding.add(
            EdgeInsets.only(bottom: DScrollChrome.bottomInsetOf(context)),
          );
          return ChatListing(
            siteUrl: siteUrl,
            place: ChatInboxPlace.page,
            frame: ChatInboxRowFrame.page,
            builder: (context, view) {
              final content = view.loading
                  ? ChatBrowseSkeleton(
                      page: ChatBrowsePage.chats,
                      scrollable: lazy,
                      padding: padding.add(
                        EdgeInsets.symmetric(
                          horizontal: ChatInboxRowFrame.page.edge,
                        ),
                      ),
                    )
                  : lazy
                  ? ListView.builder(
                      key: PageStorageKey(('mobile-chat-list', siteUrl)),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: padding,
                      itemCount: view.entries.length,
                      // A chat that turns unread moves up its group. Finding
                      // a mounted row by its key keeps it, so only the row
                      // that changed is drawn again.
                      findChildIndexCallback: view.indexOf,
                      itemBuilder: (context, index) => view.entries[index],
                    )
                  : Padding(
                      padding: padding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: view.entries,
                      ),
                    );
              return lazy
                  ? DPullToRefresh(
                      key: ValueKey(siteUrl),
                      onRefresh:
                          view.loading ||
                              view.refreshing ||
                              !shell.chatAvailable(siteUrl)
                          ? null
                          : () => chat.loadChannels(siteUrl, force: true),
                      child: content,
                    )
                  : content;
            },
          );
        },
      ),
    );
  }
}
