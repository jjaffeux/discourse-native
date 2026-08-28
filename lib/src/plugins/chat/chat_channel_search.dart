import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../plugin_api/plugin_scope.dart';
import '../../shell/shell_scope.dart';
import '../../theme/d_button.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'chat_notification_counter.dart';
import 'chat_plugin_data.dart';
import 'chat_search_controller.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

class ChatChannelSearchButton extends StatelessWidget {
  const ChatChannelSearchButton({
    super.key,
    required this.siteUrl,
    required this.channelId,
  });

  final String siteUrl;
  final int channelId;

  @override
  Widget build(BuildContext context) {
    return ShellSelector<bool>(
      select: (shell) {
        final instance = shell.currentInstance;
        return instance?.url == siteUrl &&
            instance!.isConnected &&
            instance.config.chatSettings.searchEnabled &&
            instance.user?.chatCurrentUser?.hasChatEnabled != false &&
            shell.currentTotals?.hasChatEnabled == true;
      },
      builder: (context, available, _) {
        if (!available) return const SizedBox.shrink();
        final search = PluginScope.require(
          context,
          chatSearchControllerService,
        );
        return ValueListenableBuilder<ScopedChatSearchState>(
          valueListenable: search.scopedRef(siteUrl, channelId),
          builder: (context, state, _) => DButton.iconOnly(
            key: const ValueKey('chat-channel-search-button'),
            onPressed: () => search.toggleScoped(siteUrl, channelId),
            variant: DButtonVariant.flat,
            icon: DIcon(
              DIcons.magnifyingGlass,
              size: 18,
              color: state.open ? Theme.of(context).colorScheme.primary : null,
            ),
            tooltip: state.open
                ? 'Close channel search'
                : 'Search this channel',
          ),
        );
      },
    );
  }
}

class ChatChannelSearchBar extends StatefulWidget {
  const ChatChannelSearchBar({
    super.key,
    required this.siteUrl,
    required this.channelId,
  });

  final String siteUrl;
  final int channelId;

  @override
  State<ChatChannelSearchBar> createState() => _ChatChannelSearchBarState();
}

class _ChatChannelSearchBarState extends State<ChatChannelSearchBar> {
  late final ChatSearchController _search;
  late final TextEditingController _query;
  int _seenSelectionRevision = 0;
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _search = PluginScope.require(context, chatSearchControllerService);
    final state = _search.scopedState(widget.siteUrl, widget.channelId);
    _query = TextEditingController(text: state.query);
    _seenSelectionRevision = state.selectionRevision;
    _ready = true;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ScopedChatSearchState>(
      valueListenable: _search.scopedRef(widget.siteUrl, widget.channelId),
      builder: (context, state, _) {
        if (!state.open) {
          if (_query.text.isNotEmpty) _query.clear();
          return const SizedBox.shrink();
        }
        _revealSelection(state);
        return Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _close();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: _bar(context, state),
        );
      },
    );
  }

  Widget _bar(BuildContext context, ScopedChatSearchState state) {
    final theme = Theme.of(context);
    final busy =
        state.phase == ChatSearchPhase.waiting ||
        state.phase == ChatSearchPhase.loading;
    return Container(
      key: const ValueKey('chat-channel-search-bar'),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('chat-channel-search-field'),
                  controller: _query,
                  autofocus: true,
                  onChanged: (value) => _search.setScopedQuery(
                    widget.siteUrl,
                    widget.channelId,
                    value,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search this channel',
                    prefixIcon: const DIcon(DIcons.magnifyingGlass, size: 17),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: _clear,
                            icon: const DIcon(DIcons.xmark, size: 15),
                            tooltip: 'Clear search',
                          ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              if (busy) ...[
                const SizedBox(width: 10),
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              ],
              if (state.hits.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text('${state.selectedIndex + 1} / ${state.hits.length}'),
                if (state.hits.length > 1) ...[
                  IconButton(
                    onPressed: () => _search.selectPrevious(
                      widget.siteUrl,
                      widget.channelId,
                    ),
                    icon: const RotatedBox(
                      quarterTurns: 2,
                      child: DIcon(DIcons.chevronDown, size: 16),
                    ),
                    tooltip: 'Previous result',
                  ),
                  IconButton(
                    onPressed: () =>
                        _search.selectNext(widget.siteUrl, widget.channelId),
                    icon: const DIcon(DIcons.chevronDown, size: 16),
                    tooltip: 'Next result',
                  ),
                ],
              ],
              TextButton(onPressed: _close, child: const Text('Done')),
            ],
          ),
          if (state.phase == ChatSearchPhase.empty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No messages found in this channel.'),
            )
          else if (state.error case final error?)
            Row(
              children: [
                Expanded(child: Text(error)),
                TextButton(
                  onPressed: () =>
                      _search.retryScoped(widget.siteUrl, widget.channelId),
                  child: const Text('Try again'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _revealSelection(ScopedChatSearchState state) {
    if (state.selectionRevision == _seenSelectionRevision) return;
    _seenSelectionRevision = state.selectionRevision;
    final hit = state.selectedHit;
    if (hit == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      PluginScope.require(context, chatShellService).revealChannelMessage(
        siteUrl: widget.siteUrl,
        channelId: widget.channelId,
        messageId: hit.message.id,
      );
    });
  }

  void _clear() {
    _query.clear();
    _search.setScopedQuery(widget.siteUrl, widget.channelId, '');
    setState(() {});
  }

  void _close() {
    _search.closeScoped(widget.siteUrl, widget.channelId);
  }
}
