import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_inbox_filters.dart';
import 'chat_inbox_order.dart';

export 'chat_controller.dart' show chatInboxActivityAt;
export 'chat_conversation_avatar.dart';
export 'chat_inbox_order.dart';
export 'chat_inbox_row.dart';
export 'chat_inbox_section.dart';

/// One mixed list of channels and direct messages, most recent activity first.
List<ChatChannel> chatInboxConversations(
  ChatController chat,
  String siteUrl,
  ChatInboxFilter filter,
) => chat.inboxConversations(siteUrl, filter);

String chatInboxEmptyMessage(ChatInboxFilter filter) => switch (filter.kind) {
  ChatInboxKind.all => appL10n.noConversationsYet,
  ChatInboxKind.channels => appL10n.youHaveNotJoinedAnyChannelsYet,
  ChatInboxKind.directMessages => appL10n.youHaveNoDirectMessagesYet,
  ChatInboxKind.voiceRooms => appL10n.noVoiceRoomsYet,
};

/// The switch between chats by kind and all of them as one list, shared by
/// the Chats page and chat's side. A choice between only two, each drawn as
/// its mark alone, its name what is read out.
class ChatInboxFilterBar extends StatelessWidget {
  const ChatInboxFilterBar({
    super.key,
    required this.siteUrl,
    required this.filters,
  });

  final String siteUrl;
  final ChatInboxFilters filters;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: filters,
    builder: (context, _) {
      final filter = filters.filterFor(siteUrl);
      return DReferenceTextScale(
        child: DToggleGroup<ChatInboxSort>(
          key: const ValueKey('chat-inbox-sort-filter'),
          size: DControlSize.segment,
          inset: true,
          allowEmptySelection: false,
          semanticLabel: context.l10n.chatOrder,
          values: [filter.sort],
          items: [
            DToggleGroupItem.iconOnly(
              value: ChatInboxSort.byType,
              icon: const DIcon(DIcons.folder, size: 13),
              semanticLabel: context.l10n.chatOrderByType,
              tooltip: context.l10n.chatOrderByType,
            ),
            DToggleGroupItem.iconOnly(
              value: ChatInboxSort.newest,
              icon: const DIcon(DIcons.list, size: 13),
              semanticLabel: context.l10n.chatOrderNewest,
              tooltip: context.l10n.chatOrderNewest,
            ),
          ],
          onChanged: (values) =>
              filters.update(siteUrl, filter.copyWith(sort: values.single)),
        ),
      );
    },
  );
}

DIconData _inboxSectionIcon(ChatInboxSectionKind kind) => switch (kind) {
  ChatInboxSectionKind.results => DIcons.magnifyingGlass,
  ChatInboxSectionKind.starred => DIcons.star,
  ChatInboxSectionKind.channels => DIcons.hashtag,
  ChatInboxSectionKind.directMessages => DIcons.user,
  ChatInboxSectionKind.allChats => DIcons.comments,
};

String _inboxSectionLabel(BuildContext context, ChatInboxSectionKind kind) =>
    switch (kind) {
      ChatInboxSectionKind.results => context.l10n.chatResults,
      ChatInboxSectionKind.starred => context.l10n.starred,
      ChatInboxSectionKind.channels => context.l10n.channels,
      ChatInboxSectionKind.directMessages => context.l10n.directMessages,
      ChatInboxSectionKind.allChats => context.l10n.chatAllChats,
    };

/// A group's name under its mark. The first stands as far under the controls
/// as a list's first row's words do; the rest are set apart from the group
/// over them.
class ChatInboxSectionHeading extends StatelessWidget {
  const ChatInboxSectionHeading({
    super.key,
    required ChatInboxSectionKind this.kind,
    this.first = false,
    this.edge = 0,
  });

  /// The voice rooms, which close the list under a heading of their own.
  const ChatInboxSectionHeading.rooms({
    super.key,
    this.first = false,
    this.edge = 0,
  }) : kind = null;

  final ChatInboxSectionKind? kind;
  final bool first;
  final double edge;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.fromSTEB(edge, first ? 12 : 18, edge, 2),
    child: Row(
      spacing: 6,
      children: [
        DIcon(
          switch (kind) {
            final kind? => _inboxSectionIcon(kind),
            null => DIcons.microphoneLines,
          },
          size: 11,
          color: DTokens.of(context).mutedForeground,
        ),
        Flexible(
          child: Text(
            switch (kind) {
              final kind? => _inboxSectionLabel(context, kind),
              null => context.l10n.voiceRooms,
            },
            style: TextStyle(
              fontSize: DiscourseTypography.xs,
              fontWeight: FontWeight.w600,
              letterSpacing: .2,
              color: DTokens.of(context).mutedForeground,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The inbox's error state: nothing to show and a way to ask again.
class ChatInboxError extends StatelessWidget {
  const ChatInboxError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => DEmpty(
    children: [
      DEmptyHeader(
        children: [DEmptyTitle(context.l10n.couldNotLoadConversations)],
      ),
      DButton(label: Text(context.l10n.retry), onPressed: onRetry),
    ],
  );
}
