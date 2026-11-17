import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_channel.dart';
import 'chat_channel_actions.dart';
import 'chat_controller.dart';
import 'chat_conversation_avatar.dart';
import 'chat_inbox_order.dart';
import 'chat_reader_time.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';
import 'chat_user_avatar.dart';

/// Where a list's rows stand in the box the list is given.
///
/// [edge] is how far in a read row's own edge is. An unread row's box
/// reaches [ChatInboxRowFrame.reach] past that edge and is padded by as much,
/// so its words stay on the others'.
@immutable
final class ChatInboxRowFrame {
  const ChatInboxRowFrame({required this.edge, this.leadingEdge = 3});

  /// The Chats page, whose lane the list fills edge to edge.
  static const page = ChatInboxRowFrame(edge: 16);

  /// A page of rows that are never the open one, so none keeps room for the
  /// accent along its leading edge.
  static const plain = ChatInboxRowFrame(edge: 16, leadingEdge: 0);

  final double edge;

  /// Room kept before every row's mark for the open row's accent edge.
  final double leadingEdge;

  static const double mark = 40;

  double get reach => edge < 12 ? edge : 12;
  double get boxInset => edge - reach;

  @override
  bool operator ==(Object other) =>
      other is ChatInboxRowFrame &&
      other.edge == edge &&
      other.leadingEdge == leadingEdge;

  @override
  int get hashCode => Object.hash(edge, leadingEdge);
}

/// The shell every row of chat's list is drawn in: flush and ruled when read,
/// boxed in the kit's unread fill when [boxed].
class ChatInboxRowSurface extends StatelessWidget {
  const ChatInboxRowSurface({
    super.key,
    required this.frame,
    required this.boxed,
    required this.onPressed,
    required this.mark,
    required this.words,
    this.itemKey,
    this.selected = false,
    this.enabled = true,
    this.semanticLabel,
    this.cornerAction,
  });

  final ChatInboxRowFrame frame;
  final bool boxed;
  final bool selected;
  final bool enabled;
  final Key? itemKey;
  final VoidCallback onPressed;
  final String? semanticLabel;
  final Widget? cornerAction;

  /// What the row is of, [ChatInboxRowFrame.mark] across.
  final Widget mark;
  final ChatInboxRowWords words;

  @override
  Widget build(BuildContext context) {
    final box = boxed && !selected;
    final item = DItem(
      key: itemKey,
      shape: box ? DItemShape.standard : DItemShape.fullWidth,
      variant: box ? DItemVariant.unread : DItemVariant.standard,
      padding: EdgeInsetsDirectional.fromSTEB(
        frame.leadingEdge + (box ? frame.reach : 0),
        12,
        box ? frame.reach : 0,
        12,
      ),
      gap: 10,
      selected: selected,
      enabled: enabled,
      selectionStyle: DItemSelectionStyle.leadingAccent,
      showSelectionIndicator: false,
      cornerAction: cornerAction,
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      children: [
        DItemMedia(variant: DItemMediaVariant.avatar, child: mark),
        DItemContent(
          spacing: 0,
          alignment: CrossAxisAlignment.stretch,
          children: [words],
        ),
      ],
    );
    return Padding(
      padding: box
          ? EdgeInsets.symmetric(horizontal: frame.boxInset, vertical: 2)
          : EdgeInsets.symmetric(horizontal: frame.edge),
      child: item,
    );
  }
}

/// A row's words: its name with how much is new at the top right, and under
/// them its line with when at the bottom right.
class ChatInboxRowWords extends StatelessWidget {
  const ChatInboxRowWords({
    super.key,
    required this.name,
    required this.line,
    this.over,
    this.count,
    this.tail,
  });

  /// Where the row's subject is, quietly over its name, as a thread says its
  /// channel. With it, [count] stands beside it rather than beside the name.
  final Widget? over;
  final Widget name;
  final Widget line;

  /// What stands at the top right. Without it the name takes the whole line.
  final Widget? count;

  /// What stands at the bottom right.
  final Widget? tail;

  /// As wide as the widest time, so every count across the list stands on
  /// one line.
  static const double tailWidth = 56;

  static const nameStyle = TextStyle(fontSize: 14.5, height: 1.35);
  static const lineStyle = TextStyle(
    fontSize: 12.5,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );
  static const tailStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _build);

  Widget _build(BuildContext context, BoxConstraints constraints) {
    final muted = DTokens.of(context).mutedForeground;
    // A long date in large text gives way before it takes the line from
    // what was said.
    final most = constraints.maxWidth * .45;
    Widget ended(Widget child) => ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: most < tailWidth ? most : tailWidth,
        maxWidth: most,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        widthFactor: 1,
        child: child,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 3,
      children: [
        if (over case final over?)
          Row(
            spacing: DSpacing.sm,
            children: [
              Expanded(
                child: DefaultTextStyle.merge(
                  style: tailStyle.copyWith(color: muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: over,
                ),
              ),
              ?switch (count) {
                final count? => ended(count),
                null => null,
              },
            ],
          ),
        Row(
          spacing: DSpacing.sm,
          children: [
            Expanded(
              child: DefaultTextStyle.merge(style: nameStyle, child: name),
            ),
            if (over == null)
              ?switch (count) {
                final count? => ended(count),
                null => null,
              },
          ],
        ),
        Row(
          spacing: DSpacing.sm,
          children: [
            Expanded(
              child: DefaultTextStyle.merge(
                style: lineStyle.copyWith(color: muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: line,
              ),
            ),
            ?switch (tail) {
              final tail? => ended(
                DefaultTextStyle.merge(
                  style: tailStyle.copyWith(color: muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: tail,
                ),
              ),
              null => null,
            },
          ],
        ),
      ],
    );
  }
}

/// Whoever said a line, by their face before it.
class ChatSaidBy extends StatelessWidget {
  const ChatSaidBy({
    super.key,
    required this.siteUrl,
    required this.userId,
    required this.name,
    required this.avatarUrl,
  });

  final String siteUrl;
  final int userId;
  final String? name;
  final String? avatarUrl;

  static const double size = 16;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 6),
    child: Semantics(
      label: name,
      child: ChatUserAvatar(
        siteUrl: siteUrl,
        userId: userId,
        url: avatarUrl,
        size: size,
        fallback: DAvatarFallback(
          child: Text(
            (name ?? '?').characters.take(1).toString().toUpperCase(),
            style: const TextStyle(fontSize: 9),
          ),
        ),
      ),
    ),
  );
}

/// A conversation in chat's list: who or where, what is new, what was said
/// last and when.
class ChatInboxRow extends StatelessWidget {
  const ChatInboxRow({
    super.key,
    required this.siteUrl,
    required this.channel,
    required this.onPressed,
    this.frame = ChatInboxRowFrame.page,
    this.selected = false,
    this.showStar = false,
    this.menuButton = false,
    this.found,
  });

  final String siteUrl;
  final ChatChannel channel;
  final VoidCallback onPressed;
  final ChatInboxRowFrame frame;
  final bool selected;

  /// Starred, where no Starred heading over the row says so.
  final bool showStar;

  /// The row's menu as a button under the pointer, as a side's row has it.
  final bool menuButton;

  final ChatInboxFoundLine? found;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final muted = channel.membership.muted;
    final count = chatInboxUnreadCount(channel);
    final fresh = chatInboxIsNew(channel);
    final chat = PluginUiScope.require(context, chatControllerService);
    final currentUserId = PluginUiScope.require(
      context,
      chatShellService,
    ).currentUser?.id;
    final time = chatTimeFor(context, siteUrl);
    final activity = chatInboxActivityAt(channel);
    final at = activity == null ? null : time.local(activity);
    final directUser = channel.directUser;
    final status = directUser?.status;
    final mark = TextStyle(color: tokens.mutedForeground);
    return ChatChannelMenu(
      siteUrl: siteUrl,
      channelId: channel.id,
      child: ChatInboxRowSurface(
        itemKey: ValueKey('chat-inbox-channel-${channel.id}'),
        frame: frame,
        boxed: fresh,
        selected: selected,
        cornerAction: menuButton && !context.isTouch
            ? ChatChannelMenu(
                siteUrl: siteUrl,
                channelId: channel.id,
                channel: channel,
              )
            : null,
        onPressed: onPressed,
        semanticLabel: fresh ? context.l10n.unreadConversation : null,
        mark: ChatConversationAvatar(
          siteUrl: siteUrl,
          channel: channel,
          size: ChatInboxRowFrame.mark,
        ),
        words: ChatInboxRowWords(
          name: Row(
            children: [
              Flexible(
                child: Text(
                  channel.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: fresh ? FontWeight.w700 : FontWeight.w400,
                    color: muted
                        ? tokens.mutedForeground
                        : fresh
                        ? tokens.foreground
                        : tokens.titleRead,
                  ),
                ),
              ),
              if (status != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 6),
                  child: UserStatusMessage(
                    siteUrl: siteUrl,
                    userId: directUser!.id,
                    status: status,
                    size: 14,
                  ),
                ),
              for (final (icon, label) in [
                if (showStar && channel.membership.starred)
                  (DIcons.star, context.l10n.starred),
                if (channel.readRestricted)
                  (DIcons.lock, context.l10n.chatPrivateChannel),
                if (muted)
                  (DNativeIcons.bellSlash, context.l10n.chatMutedChannel),
              ])
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 6),
                  child: Semantics(
                    label: label,
                    child: DIcon(icon, size: 10, color: mark.color),
                  ),
                ),
            ],
          ),
          count: fresh
              ? DBadge.unreadChip(
                  key: ValueKey('chat-inbox-unread-${channel.id}'),
                  count: count,
                  semanticLabel: context.l10n.unreadChatplugin(count),
                )
              : muted && count > 0
              ? DNotificationDot(
                  key: ValueKey('chat-inbox-muted-unread-${channel.id}'),
                  color: tokens.mutedForeground,
                  semanticLabel: context.l10n.chatUnreadMuted,
                )
              : null,
          line: _line(context, chat, currentUserId),
          tail: at == null
              ? null
              : Text(
                  chatInboxActivityLabel(
                    context,
                    at,
                    time.local(DateTime.now()),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _line(BuildContext context, ChatController chat, int? currentUserId) {
    final found = this.found;
    final last = switch (channel.lastMessageId) {
      final id? when found == null => chat.message(siteUrl, id),
      _ => null,
    };
    final authorId = found != null
        ? found.authorId
        : channel.lastMessageUserId ?? last?.author.id;
    final member = channel.users
        .where((user) => user.id == authorId)
        .firstOrNull;
    // Your own turn has nothing before it, and in a conversation with one
    // person the row is already their face.
    final faced =
        authorId != null &&
        authorId != currentUserId &&
        authorId != channel.directUser?.id;
    final text = found != null
        ? found.text
        : channel.lastMessagePreview ??
              (channel.lastMessageId == null ? context.l10n.noMessagesYet : '');
    return Row(
      children: [
        if (faced)
          ChatSaidBy(
            key: ValueKey('chat-inbox-said-by-${channel.id}'),
            siteUrl: siteUrl,
            userId: authorId,
            name: found != null
                ? found.authorName
                : last?.author.displayName ??
                      member?.username ??
                      channel.lastMessageUsername,
            avatarUrl: found != null
                ? found.authorAvatarUrl
                : last?.author.avatarUrl ?? member?.avatarUrl,
          ),
        Expanded(
          child: found != null
              ? SearchText(
                  text,
                  query: found.query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : SiteEmojiText.plain(
                  text,
                  siteUrl: siteUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ],
    );
  }
}

/// When something was last said, as a row's tail says it: the time today,
/// the date before that.
String chatInboxActivityLabel(BuildContext context, DateTime at, DateTime now) {
  if (at.year == now.year && at.month == now.month && at.day == now.day) {
    return clockTimeLabel(context, at);
  }
  return MaterialLocalizations.of(context).formatShortDate(at);
}

/// A way out of the list to more of chat, drawn as a channel's row is so it
/// stands among them: the threads, or every channel.
class ChatInboxWayRow extends StatelessWidget {
  const ChatInboxWayRow({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onPressed,
    this.frame = ChatInboxRowFrame.page,
    this.count = 0,
  });

  final DIconData icon;
  final String title;
  final String description;
  final VoidCallback onPressed;
  final ChatInboxRowFrame frame;

  /// How much is new behind it. With any, the row is boxed as an unread
  /// chat's is.
  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return ChatInboxRowSurface(
      frame: frame,
      boxed: count > 0,
      onPressed: onPressed,
      mark: DAvatar(
        dimension: ChatInboxRowFrame.mark,
        border: false,
        borderRadius: BorderRadius.circular(DRadius.bubble),
        decorative: true,
        fallback: DAvatarFallback(
          backgroundColor: tokens.raisedBackground,
          foregroundColor: tokens.mutedForeground,
          child: DIcon(icon, size: 15),
        ),
      ),
      words: ChatInboxRowWords(
        name: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: count > 0 ? FontWeight.w700 : FontWeight.w500,
            color: tokens.foreground,
          ),
        ),
        count: count > 0 ? DBadge.unreadChip(count: count) : null,
        line: Text(description),
      ),
    );
  }
}

/// Keeps a mounted row's listeners and content across a reorder, so only its
/// own channel or selection redraws it.
class ChatInboxEntry extends StatefulWidget {
  const ChatInboxEntry({
    super.key,
    required this.siteUrl,
    required this.channelId,
    this.frame = ChatInboxRowFrame.page,
    this.showStar = false,
    this.menuButton = false,
    this.found,
  });

  final String siteUrl;
  final int channelId;
  final ChatInboxRowFrame frame;
  final bool showStar;
  final bool menuButton;
  final ChatInboxFoundLine? found;

  @override
  State<ChatInboxEntry> createState() => _ChatInboxEntryState();
}

class _ChatInboxEntryState extends State<ChatInboxEntry> {
  Widget? _content;

  @override
  void didUpdateWidget(ChatInboxEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.channelId != widget.channelId ||
        oldWidget.frame != widget.frame ||
        oldWidget.showStar != widget.showStar ||
        oldWidget.menuButton != widget.menuButton ||
        oldWidget.found != widget.found) {
      _content = null;
    }
  }

  @override
  Widget build(BuildContext context) => _content ??=
      PluginServiceSelector<
        ChatShellService,
        ({bool selected, DiscourseUser? user})
      >(
        service: chatShellService,
        select: (shell) => (
          selected: shell.visibleChannelId == widget.channelId,
          user: shell.currentUser,
        ),
        builder: (context, state, _) => ValueListenableBuilder<ChatChannel?>(
          valueListenable: PluginUiScope.require(
            context,
            chatControllerService,
          ).channelRef(widget.siteUrl, widget.channelId),
          // The id came from the store, so a gap means the channel was
          // just removed and the list is one frame from dropping it.
          builder: (context, channel, _) => channel == null
              ? const SizedBox.shrink()
              : ChatInboxRow(
                  siteUrl: widget.siteUrl,
                  channel: channel,
                  frame: widget.frame,
                  selected: state.selected,
                  showStar: widget.showStar,
                  menuButton: widget.menuButton,
                  found: widget.found,
                  onPressed: () => PluginUiScope.require(
                    context,
                    chatShellService,
                  ).openChannel(widget.channelId),
                ),
        ),
      );
}
