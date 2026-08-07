import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../shell/shell_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'chat_controller.dart';
import 'chat_message.dart';
import 'chat_message_tile.dart';
import 'chat_stream.dart';

/// One channel's messages, newest at the bottom.
class ChatChannelView extends StatefulWidget {
  const ChatChannelView({super.key, required this.channelId});

  final int channelId;

  /// Start fetching the page before this one about a screen from the end of
  /// what is held — the number [TopicView] already settled on, for the same
  /// reason. Under a reversed list this is the distance to the *oldest*
  /// message, which is where the reader is heading.
  static const double _loadOlderThreshold = 900;

  @override
  State<ChatChannelView> createState() => _ChatChannelViewState();
}

class _ChatChannelViewState extends State<ChatChannelView> {
  /// Which `(site, channel)` this has already asked for, so that the ask
  /// happens once per channel rather than once per notification.
  String? _opened;

  /// The fetch is kicked from here rather than from `initState`, which cannot
  /// reach the shell: `ShellScope.of` registers an inherited dependency, and
  /// doing that before `initState` has returned is an error.
  ///
  /// The cost is that this runs again on every shell notification — including
  /// the one the fetch itself raises — so the guard below is what stops it
  /// asking forever, and it has to be here rather than in the controller: an
  /// open is *meant* to re-ask when the reader comes back to a channel.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _openIfNeeded();
  }

  @override
  void didUpdateWidget(ChatChannelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelId != widget.channelId) _opened = null;
    _openIfNeeded();
  }

  void _openIfNeeded() {
    final controller = ShellScope.of(context);
    final siteUrl = controller.currentInstance?.url;
    if (siteUrl == null) return;

    final token = '$siteUrl~${widget.channelId}';
    if (_opened == token) return;
    _opened = token;

    controller.chat.openChannel(siteUrl, widget.channelId);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.of(context);
    final siteUrl = controller.currentInstance?.url;
    if (siteUrl == null) return const SizedBox.shrink();

    final chat = controller.chat;
    final stream = chat.stream(siteUrl, widget.channelId);

    if (stream.loading && stream.messageIds.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (stream.error case final error?) {
      return _Message(icon: DIcons.triangleExclamation, text: error);
    }
    if (stream.isEmpty) {
      return const _Message(
        icon: DIcons.comment,
        text: 'No messages here yet.',
      );
    }

    final messages = chat.messages(siteUrl, widget.channelId);
    final items = buildChatStream(
      messages,
      lastReadMessageId: chat
          .channel(siteUrl, widget.channelId)
          ?.membership
          .lastReadMessageId,
    );

    return _Stream(
      siteUrl: siteUrl,
      channelId: widget.channelId,
      items: items,
      messages: messages,
      stream: stream,
    );
  }
}

/// The list itself.
///
/// Split from the state above so that the arithmetic of a reversed viewport
/// sits in one place with the comment explaining it, rather than inside a
/// build method that is also deciding between four screens.
class _Stream extends StatelessWidget {
  const _Stream({
    required this.siteUrl,
    required this.channelId,
    required this.items,
    required this.messages,
    required this.stream,
  });

  final String siteUrl;
  final int channelId;
  final List<ChatStreamItem> items;
  final List<ChatMessage> messages;
  final ChatStreamState stream;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.of(context);
    final chat = controller.chat;

    // Messages by id, so a row can reach its own record without walking the
    // list. Built once per build rather than per row.
    final byId = {for (final message in messages) message.id: message};

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Under `reverse: true` the scroll axis points at the past: offset 0 is
        // the newest message and `maxScrollExtent` is the oldest one held. So
        // `extentAfter` — which in a topic means "posts further down, later" —
        // here means "messages further up, earlier". Easy to write backwards,
        // hence the note.
        if (notification.metrics.extentAfter <
            ChatChannelView._loadOlderThreshold) {
          chat.loadOlder(siteUrl, channelId);
        }
        return false;
      },
      // Reversed rather than reversing the list, which is what makes prepending
      // history free: older messages take higher scroll offsets, the viewport
      // lays out from offset 0 outward and holds `pixels` across a change in
      // content extent, so a page landing at the far end moves nothing the
      // reader is looking at. Rendering forwards and inserting at index 0 would
      // throw them into the past on every page.
      //
      // The array stays oldest-first and the builder does the arithmetic: the
      // grouping and the day separators all want a *previous* message in
      // chronological order, and a reversed copy per build would put the two
      // permanently at odds.
      //
      // SuperListView for the reason `TopicView` gives — message heights swing
      // from one word to a screenful of quotes, and a plain ListView's running
      // average makes the scrollbar thumb lurch. Under `reverse: true` that
      // estimate applies to the older end, which is where the reader is going.
      child: SuperListView.builder(
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length + (stream.loadingOlder ? 1 : 0),
        itemBuilder: (context, index) {
          // The oldest end, which in a reversed list is the last index.
          if (index >= items.length) return const _LoadingOlderRow();

          // Building the oldest row means the top of the stream is in view.
          // Scrolling alone is not enough: fifty one-line messages may not fill
          // the pane, leaving nothing to scroll and the rest never fetched.
          // Discourse calls this its fill-pane safety net and debounces it;
          // here the controller's in-flight guard is the debounce.
          if (index == items.length - 1 && stream.canLoadMorePast) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => chat.loadOlder(siteUrl, channelId),
            );
          }

          final item = items[items.length - 1 - index];
          return switch (item) {
            ChatStreamMessage(:final id, :final chained) => ChatMessageTile(
              siteUrl: siteUrl,
              messageId: id,
              chained: chained,
              replyTo: byId[id]?.replyTo,
            ),
            ChatStreamDay(:final day) => _DaySeparator(day: day),
            ChatStreamDeleted(:final count) => _DeletedRun(count: count),
            ChatStreamNewDivider() => const _NewDivider(),
          };
        },
      ),
    );
  }
}

/// The line between two days of conversation.
class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.day});

  final DateTime day;

  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// Today and yesterday by name, everything else by date. The reader's days,
  /// not the site's — [day] is already local midnight.
  String get _label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final delta = today.difference(day).inDays;
    if (delta == 0) return 'Today';
    if (delta == 1) return 'Yesterday';
    return '${day.day} ${_months[day.month - 1]} ${day.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(child: Divider(height: 1, color: theme.shell.divider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Divider(height: 1, color: theme.shell.divider)),
        ],
      ),
    );
  }
}

/// Where the messages the reader has not seen begin.
class _NewDivider extends StatelessWidget {
  const _NewDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Divider(height: 1, color: theme.colorScheme.error),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              'New',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A run of deleted messages, which only a moderator is ever shown.
class _DeletedRun extends StatelessWidget {
  const _DeletedRun({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Text(
        count == 1 ? '1 message deleted' : '$count messages deleted',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.error,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _LoadingOlderRow extends StatelessWidget {
  const _LoadingOlderRow();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

/// Local to this screen, the way `TopicListView` keeps its own: an empty
/// channel and an unreachable one are two sentences, not a shared widget.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final DIconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DIcon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
