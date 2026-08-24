import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/chat_thread_panel_width_store.dart';
import '../../shell/adaptive_shell.dart';
import '../../shell/forum_search.dart';
import '../../shell/shell_metrics.dart';
import '../../shell/shell_scope.dart';
import '../../shell/title_bar.dart';
import '../../shell/user_menu_button.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'chat_channel_view.dart';
import 'chat_composer.dart';
import 'chat_controller.dart';
import 'chat_header_button.dart';
import 'chat_message.dart';
import 'chat_route.dart';
import 'chat_stream.dart';
import 'chat_stream_target.dart';
import 'chat_thread.dart';

/// A routed thread and, when the shell is wide enough, its parent channel.
class ChatThreadWorkspace extends StatelessWidget {
  const ChatThreadWorkspace({
    super.key,
    required this.route,
    this.panelWidthStore,
  });

  final ChatRoute route;
  final ChatThreadPanelWidthStore? panelWidthStore;

  @override
  Widget build(BuildContext context) {
    return ShellSelector<_ThreadWorkspaceSource?>(
      select: (shell) {
        final siteUrl = shell.currentInstance?.url;
        return siteUrl == null ? null : (siteUrl: siteUrl, chat: shell.chat);
      },
      builder: (context, source, _) {
        if (source == null) return const SizedBox.shrink();
        final target = ChatThreadTarget(
          channelId: route.channelId,
          threadId: route.threadId!,
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            final expanded =
                ShellLayout.forWidth(MediaQuery.sizeOf(context).width) ==
                    ShellLayout.expanded &&
                constraints.maxWidth >= _ChatThreadSplit.minimumTotalWidth;
            if (!expanded) {
              return Column(
                children: [
                  _ThreadHeader(
                    siteUrl: source.siteUrl,
                    target: target,
                    leading: _HeaderAction.back,
                  ),
                  Expanded(
                    child: ChatThreadView(
                      siteUrl: source.siteUrl,
                      target: target,
                      chat: source.chat,
                    ),
                  ),
                ],
              );
            }
            return _ChatThreadSplit(
              siteUrl: source.siteUrl,
              target: target,
              chat: source.chat,
              widthStore: panelWidthStore ?? const ChatThreadPanelWidthStore(),
            );
          },
        );
      },
    );
  }
}

typedef _ThreadWorkspaceSource = ({String siteUrl, ChatController chat});

class _ChatThreadSplit extends StatefulWidget {
  const _ChatThreadSplit({
    required this.siteUrl,
    required this.target,
    required this.chat,
    required this.widthStore,
  });

  static const double minimumPaneWidth = 320;
  static const double dividerWidth = 8;
  static const double minimumTotalWidth = minimumPaneWidth * 2 + dividerWidth;

  final String siteUrl;
  final ChatThreadTarget target;
  final ChatController chat;
  final ChatThreadPanelWidthStore widthStore;

  @override
  State<_ChatThreadSplit> createState() => _ChatThreadSplitState();
}

class _ChatThreadSplitState extends State<_ChatThreadSplit> {
  double? _preferredWidth;
  bool _widthChanged = false;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreWidth());
  }

  Future<void> _restoreWidth() async {
    final width = await widget.widthStore.read();
    if (mounted && !_widthChanged && width != null) {
      setState(() => _preferredWidth = width);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final maximum =
            available -
            _ChatThreadSplit.minimumPaneWidth -
            _ChatThreadSplit.dividerWidth;
        final initial = _preferredWidth ?? available / 2;
        final threadWidth = initial.clamp(
          _ChatThreadSplit.minimumPaneWidth,
          maximum,
        );

        return Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  _ChannelPaneHeader(
                    siteUrl: widget.siteUrl,
                    channelId: widget.target.channelId,
                  ),
                  Expanded(
                    child: ChatChannelView(channelId: widget.target.channelId),
                  ),
                ],
              ),
            ),
            _ThreadPaneDivider(
              width: threadWidth,
              minimumWidth: _ChatThreadSplit.minimumPaneWidth,
              maximumWidth: maximum,
              onDelta: (delta) => setState(() {
                _widthChanged = true;
                _preferredWidth = (threadWidth - delta).clamp(
                  _ChatThreadSplit.minimumPaneWidth,
                  maximum,
                );
              }),
              onCommit: () {
                final width = _preferredWidth;
                if (width != null) unawaited(widget.widthStore.write(width));
              },
            ),
            SizedBox(
              width: threadWidth,
              child: Column(
                children: [
                  _ThreadHeader(
                    siteUrl: widget.siteUrl,
                    target: widget.target,
                    leading: _HeaderAction.none,
                    showClose: true,
                  ),
                  Expanded(
                    child: ChatThreadView(
                      siteUrl: widget.siteUrl,
                      target: widget.target,
                      chat: widget.chat,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ThreadPaneDivider extends StatelessWidget {
  const _ThreadPaneDivider({
    required this.width,
    required this.minimumWidth,
    required this.maximumWidth,
    required this.onDelta,
    required this.onCommit,
  });

  final double width;
  final double minimumWidth;
  final double maximumWidth;
  final ValueChanged<double> onDelta;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final divider = Color.alphaBlend(
      theme.colorScheme.onSurface.withValues(alpha: 0.12),
      theme.shell.divider,
    );
    final canIncrease = width < maximumWidth;
    final canDecrease = width > minimumWidth;
    final increasedWidth = (width + 24).clamp(minimumWidth, maximumWidth);
    final decreasedWidth = (width - 24).clamp(minimumWidth, maximumWidth);
    return Semantics(
      label: 'Thread pane width',
      value: '${width.round()} pixels',
      increasedValue: canIncrease ? '${increasedWidth.round()} pixels' : null,
      decreasedValue: canDecrease ? '${decreasedWidth.round()} pixels' : null,
      slider: true,
      onIncrease: canIncrease
          ? () {
              onDelta(-24);
              onCommit();
            }
          : null,
      onDecrease: canDecrease
          ? () {
              onDelta(24);
              onCommit();
            }
          : null,
      child: Focus(
        key: const ValueKey('chat-thread-divider-focus'),
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            if (!canIncrease) return KeyEventResult.handled;
            onDelta(-24);
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (!canDecrease) return KeyEventResult.handled;
            onDelta(24);
          } else {
            return KeyEventResult.ignored;
          }
          onCommit();
          return KeyEventResult.handled;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) => onDelta(details.delta.dx),
            onHorizontalDragEnd: (_) => onCommit(),
            child: SizedBox(
              width: _ChatThreadSplit.dividerWidth,
              child: Center(
                child: SizedBox(
                  key: const ValueKey('chat-thread-divider-border'),
                  width: 1,
                  child: ColoredBox(color: divider),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One independently mounted thread timeline.
class ChatThreadView extends StatefulWidget {
  const ChatThreadView({
    super.key,
    required this.siteUrl,
    required this.target,
    required this.chat,
  });

  final String siteUrl;
  final ChatThreadTarget target;
  final ChatController chat;

  @override
  State<ChatThreadView> createState() => _ChatThreadViewState();
}

class _ChatThreadViewState extends State<ChatThreadView> {
  late final Object _viewToken;
  Listenable? _navigation;
  bool _opened = false;
  bool _handledUnavailable = false;
  List<int>? _projectedMessageIds;
  List<int>? _projectedLocalMessageIds;
  int? _projectedLastRead;
  int? _projectedRevision;
  List<ChatMessage> _messages = const [];
  List<ChatStreamItem> _items = const [];
  int _focusComposerRequest = 0;
  int? _highlightMessageId;
  int _highlightRequest = 0;

  @override
  void initState() {
    super.initState();
    _viewToken = widget.chat.beginViewingThread(widget.siteUrl, widget.target);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigation = ShellScope.read(context).chatNavigation;
    if (identical(navigation, _navigation)) return;
    _navigation?.removeListener(_consumeNavigation);
    _navigation = navigation;
    navigation.addListener(_consumeNavigation);
    if (!_consumeNavigation() && !_opened) {
      _opened = true;
      unawaited(widget.chat.openThread(widget.siteUrl, widget.target));
    }
  }

  bool _consumeNavigation() {
    final shell = ShellScope.read(context);
    final pending = shell.chatNavigation.take(
      siteUrl: widget.siteUrl,
      route: ChatRoute.thread(
        channelId: widget.target.channelId,
        threadId: widget.target.threadId,
      ),
    );
    if (pending == null || !mounted) return false;
    _opened = true;
    setState(() {
      if (pending.focusComposer) _focusComposerRequest++;
      if (pending.messageId case final messageId?) {
        _highlightMessageId = messageId;
        _highlightRequest++;
      }
    });
    unawaited(
      widget.chat.openThread(
        widget.siteUrl,
        widget.target,
        targetMessageId: pending.messageId,
        force: true,
      ),
    );
    return true;
  }

  @override
  void dispose() {
    _navigation?.removeListener(_consumeNavigation);
    widget.chat.endViewingThread(widget.siteUrl, widget.target, _viewToken);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatStreamState>(
      valueListenable: widget.chat.streamListenableFor(
        widget.siteUrl,
        widget.target,
      ),
      builder: (context, stream, _) => _buildThread(stream),
    );
  }

  Widget _buildThread(ChatStreamState stream) {
    _handleUnavailable(stream);
    final hasMessages =
        stream.messageIds.isNotEmpty || stream.localMessageIds.isNotEmpty;
    final Widget content;
    if (hasMessages) {
      _syncProjection(stream);
      content = ChatMessageStream(
        siteUrl: widget.siteUrl,
        target: widget.target,
        items: _items,
        stream: stream,
        highlightMessageId: _highlightMessageId,
        highlightRequest: _highlightRequest,
        onHighlightComplete: _clearHighlight,
        showThreadSummaries: false,
      );
    } else if (stream.loading) {
      content = const Center(child: CircularProgressIndicator.adaptive());
    } else if (stream.error case final error?) {
      content = _ThreadStateMessage(
        icon: DIcons.triangleExclamation,
        text: error,
      );
    } else if (stream.isEmpty) {
      content = const _ThreadStateMessage(
        icon: DIcons.comments,
        text: 'No replies yet.',
      );
    } else {
      content = const SizedBox.shrink();
    }

    return Column(
      children: [
        if (stream.notice case final notice?)
          Semantics(
            liveRegion: true,
            child: Container(
              key: const ValueKey('chat-thread-notice'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Text(
                notice,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
        Expanded(child: content),
        if (!stream.threadUnavailable && (stream.error == null || hasMessages))
          ChatComposer(
            key: ValueKey((
              widget.siteUrl,
              widget.target.channelId,
              widget.target.threadId,
              'composer',
            )),
            siteUrl: widget.siteUrl,
            channelId: widget.target.channelId,
            threadId: widget.target.threadId,
            focusRequest: _focusComposerRequest,
          ),
      ],
    );
  }

  void _handleUnavailable(ChatStreamState stream) {
    if (!stream.threadUnavailable || _handledUnavailable) return;
    _handledUnavailable = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final shell = ShellScope.read(context);
      shell.handleBack(canReturnToSidebar: false);
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('This thread is no longer available.')),
      );
    });
  }

  void _clearHighlight(int request) {
    if (!mounted || request != _highlightRequest) return;
    setState(() => _highlightMessageId = null);
  }

  void _syncProjection(ChatStreamState stream) {
    if (identical(_projectedMessageIds, stream.messageIds) &&
        identical(_projectedLocalMessageIds, stream.localMessageIds) &&
        _projectedLastRead == stream.lastReadOnOpen &&
        _projectedRevision == stream.revision) {
      return;
    }
    _projectedMessageIds = stream.messageIds;
    _projectedLocalMessageIds = stream.localMessageIds;
    _projectedLastRead = stream.lastReadOnOpen;
    _projectedRevision = stream.revision;
    _messages = widget.chat.messagesFor(widget.siteUrl, widget.target);
    _items = buildChatStream(
      _messages,
      lastReadMessageId: stream.lastReadOnOpen,
    );
  }
}

enum _HeaderAction { none, back }

class _ChannelPaneHeader extends StatelessWidget {
  const _ChannelPaneHeader({required this.siteUrl, required this.channelId});

  final String siteUrl;
  final int channelId;

  @override
  Widget build(BuildContext context) {
    final chat = ShellScope.read(context).chat;
    return ValueListenableBuilder(
      valueListenable: chat.channelRef(siteUrl, channelId),
      builder: (context, channel, _) => _PaneHeaderShell(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final theme = Theme.of(context);
            final carriesSearch = !ShellTitleBar.isSupported;
            final showIdentity = !carriesSearch || constraints.maxWidth >= 620;
            final searchWidth = constraints.maxWidth >= 800 ? 360.0 : 260.0;
            return Row(
              children: [
                const SizedBox(width: 12),
                if (showIdentity) ...[
                  const DIcon(DIcons.comment, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      channel?.title ?? 'Chat',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else if (carriesSearch)
                  const Expanded(child: ForumSearch(dense: true)),
                if (carriesSearch && showIdentity) ...[
                  SizedBox(
                    width: searchWidth,
                    child: const ForumSearch(dense: true),
                  ),
                  const SizedBox(width: 4),
                ],
                if (ShellTitleBar.columnsCarryUserMenu) ...[
                  ChatHeaderButton(ringColor: theme.shell.content),
                  UserMenuButton(ringColor: theme.shell.content),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ThreadHeader extends StatelessWidget {
  const _ThreadHeader({
    required this.siteUrl,
    required this.target,
    required this.leading,
    this.showClose = false,
  });

  final String siteUrl;
  final ChatThreadTarget target;
  final _HeaderAction leading;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    return ValueListenableBuilder<ChatThread?>(
      valueListenable: shell.chat.threadRef(siteUrl, target.threadId),
      builder: (context, thread, _) => _PaneHeaderShell(
        child: Row(
          children: [
            if (leading == _HeaderAction.back)
              IconButton(
                tooltip: 'Back',
                onPressed: () => shell.handleBack(
                  canReturnToSidebar: ShellLayout.forWidth(
                    MediaQuery.sizeOf(context).width,
                  ).isCompact,
                ),
                icon: const DIcon(DIcons.arrowLeft, size: 20),
              )
            else
              const SizedBox(width: 12),
            Expanded(
              child: Text(
                thread?.title?.trim().isNotEmpty == true
                    ? thread!.title!
                    : 'Thread',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            _NotificationLevelButton(
              siteUrl: siteUrl,
              target: target,
              thread: thread,
            ),
            if (showClose)
              IconButton(
                tooltip: 'Close thread',
                onPressed: () => shell.handleBack(canReturnToSidebar: false),
                icon: const DIcon(DIcons.xmark, size: 18),
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _NotificationLevelButton extends StatelessWidget {
  const _NotificationLevelButton({
    required this.siteUrl,
    required this.target,
    required this.thread,
  });

  final String siteUrl;
  final ChatThreadTarget target;
  final ChatThread? thread;

  @override
  Widget build(BuildContext context) {
    final current =
        thread?.membership?.notificationLevel ??
        ChatThreadNotificationLevel.normal;
    return PopupMenuButton<ChatThreadNotificationLevel>(
      tooltip: 'Thread notifications',
      enabled: thread != null,
      onSelected: (level) => unawaited(
        ShellScope.read(
          context,
        ).chat.updateThreadNotificationLevel(siteUrl, target, level),
      ),
      itemBuilder: (context) => [
        for (final level in const [
          ChatThreadNotificationLevel.normal,
          ChatThreadNotificationLevel.tracking,
          ChatThreadNotificationLevel.watching,
        ])
          PopupMenuItem(
            value: level,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: level == current
                      ? const DIcon(DIcons.check, size: 16)
                      : null,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_levelTitle(level)),
                      Text(
                        _levelDescription(level),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
      icon: const DIcon(DIcons.bell, size: 18),
    );
  }

  static String _levelTitle(ChatThreadNotificationLevel level) =>
      switch (level) {
        ChatThreadNotificationLevel.normal => 'Normal',
        ChatThreadNotificationLevel.tracking => 'Tracking',
        ChatThreadNotificationLevel.watching => 'Watching',
        ChatThreadNotificationLevel.muted => 'Muted',
      };

  static String _levelDescription(ChatThreadNotificationLevel level) =>
      switch (level) {
        ChatThreadNotificationLevel.normal => 'Notify me about mentions.',
        ChatThreadNotificationLevel.tracking =>
          'Show mentions and an unread reply count.',
        ChatThreadNotificationLevel.watching =>
          'Notify me about every reply and show unread counts.',
        ChatThreadNotificationLevel.muted => 'Do not notify me.',
      };
}

class _PaneHeaderShell extends StatelessWidget {
  const _PaneHeaderShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: shellHeaderHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).shell.divider),
        ),
      ),
      child: child,
    );
  }
}

class _ThreadStateMessage extends StatelessWidget {
  const _ThreadStateMessage({required this.icon, required this.text});

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
            DIcon(icon, size: 28, color: theme.colorScheme.onSurfaceVariant),
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
