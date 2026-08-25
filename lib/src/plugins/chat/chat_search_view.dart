import 'dart:async';

import 'package:flutter/material.dart';

import '../../shell/choice_menu.dart';
import '../../shell/shell_scope.dart';
import '../../theme/d_button.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../plugin_scope.dart';
import '../plugin_services.dart';
import 'chat_message_tile.dart';
import 'chat_search.dart';
import 'chat_search_controller.dart';

class ChatSearchView extends StatefulWidget {
  const ChatSearchView({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<ChatSearchView> createState() => _ChatSearchViewState();
}

class _ChatSearchViewState extends State<ChatSearchView> {
  late final ChatSearchController _search;
  late final TextEditingController _query;
  late final ScrollController _scroll;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController()..addListener(_maybeLoadMore);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _search = PluginScope.require(context, chatSearchControllerService);
    _query = TextEditingController(
      text: _search.globalState(widget.siteUrl).query,
    );
    _ready = true;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _query.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients || _scroll.position.extentAfter > 700) return;
    _search.loadMore(widget.siteUrl);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GlobalChatSearchState>(
      valueListenable: _search.globalRef(widget.siteUrl),
      builder: (context, state, _) => Column(
        children: [
          _SearchControls(
            controller: _query,
            state: state,
            onChanged: (value) => _search.setGlobalQuery(widget.siteUrl, value),
            onClear: () {
              _query.clear();
              _search.setGlobalQuery(widget.siteUrl, '');
            },
            onSort: (sort) => _search.setGlobalSort(widget.siteUrl, sort),
          ),
          Expanded(child: _results(state)),
        ],
      ),
    );
  }

  Widget _results(GlobalChatSearchState state) {
    if (!state.hasQuery) {
      return const _SearchMessage(
        icon: DIcons.magnifyingGlass,
        text: 'Search messages across your Chat channels.',
      );
    }
    if (state.hits.isEmpty &&
        (state.phase == ChatSearchPhase.waiting ||
            state.phase == ChatSearchPhase.loading)) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (state.phase == ChatSearchPhase.empty) {
      return const _SearchMessage(
        icon: DIcons.magnifyingGlass,
        text: 'No chat messages found.',
      );
    }
    if (state.phase == ChatSearchPhase.failed && state.hits.isEmpty) {
      return _SearchFailure(
        message: state.error ?? 'Could not search Chat.',
        onRetry: () => _search.retryGlobal(widget.siteUrl),
      );
    }
    if (state.hits.isEmpty) return const SizedBox.shrink();

    final hasFooter = state.loadingMore || state.error != null || state.hasMore;
    return ListView.separated(
      key: const PageStorageKey('chat-search-results'),
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.hits.length + (hasFooter ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == state.hits.length) {
          if (state.loadingMore) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator.adaptive()),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.error case final error?) ...[
                  Text(error, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                ],
                OutlinedButton(
                  onPressed: () => _search.loadMore(widget.siteUrl),
                  child: Text(state.error == null ? 'Load more' : 'Try again'),
                ),
              ],
            ),
          );
        }
        return _ChatSearchResult(
          siteUrl: widget.siteUrl,
          hit: state.hits[index],
          onOpen: () => unawaited(_open(state.hits[index])),
        );
      },
    );
  }

  Future<void> _open(ChatSearchHit hit) async {
    final chat = PluginScope.require(context, chatControllerService);
    try {
      final channel = await chat.ensureChannel(widget.siteUrl, hit.channel.id);
      if (!mounted || channel == null) throw StateError('Channel unavailable');
      final shell = ShellScope.read(context);
      if (hit.message.threadId case final threadId?) {
        shell.openChatThread(
          siteUrl: widget.siteUrl,
          channelId: channel.id,
          threadId: threadId,
          messageId: hit.message.id,
        );
      } else {
        shell.openChatChannel(channel.id, messageId: hit.message.id);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not open this chat message.')),
      );
    }
  }
}

class _SearchControls extends StatelessWidget {
  const _SearchControls({
    required this.controller,
    required this.state,
    required this.onChanged,
    required this.onClear,
    required this.onSort,
  });

  final TextEditingController controller;
  final GlobalChatSearchState state;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<ChatSearchSort> onSort;

  static const _sortOptions = [
    ChoiceMenuOption(
      value: ChatSearchSort.relevance,
      title: 'Relevance',
      description: 'Best matching messages first',
      icon: DIcons.magnifyingGlass,
    ),
    ChoiceMenuOption(
      value: ChatSearchSort.latest,
      title: 'Latest',
      description: 'Newest messages first',
      icon: DIcons.farClock,
    ),
  ];

  String _sortLabel(ChatSearchSort sort) => switch (sort) {
    ChatSearchSort.relevance => 'Relevance',
    ChatSearchSort.latest => 'Latest',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('chat-search-field'),
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: 'Search messages',
                prefixIcon: const DIcon(DIcons.magnifyingGlass, size: 18),
                suffixIcon: state.query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: onClear,
                        icon: const DIcon(DIcons.xmark, size: 16),
                        tooltip: 'Clear search',
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ChoiceMenuAnchor<ChatSearchSort>(
            title: 'Sort search results',
            value: state.sort,
            options: _sortOptions,
            onSelected: onSort,
            builder: (context, openMenu) {
              final label = _sortLabel(state.sort);
              return DButton(
                key: const ValueKey('chat-search-sort'),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label),
                    const SizedBox(width: 8),
                    const DIcon(DIcons.chevronDown, size: 12),
                  ],
                ),
                tooltip: 'Sort search results',
                semanticLabel: 'Sort search results by $label',
                variant: DButtonVariant.flat,
                onPressed: openMenu,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ChatSearchResult extends StatelessWidget {
  const _ChatSearchResult({
    required this.siteUrl,
    required this.hit,
    required this.onOpen,
  });

  final String siteUrl;
  final ChatSearchHit hit;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final threadTitle = hit.threadTitle;
    final preview = (hit.excerpt ?? '')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .trim();
    final label = [
      '${hit.message.author.displayName}:',
      if (preview.isNotEmpty) preview,
      if (threadTitle != null) 'in thread $threadTitle',
    ].join(' ');
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  threadTitle == null
                      ? hit.channel.title
                      : '${hit.channel.title} · $threadTitle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ExcludeSemantics(
                child: IgnorePointer(
                  child: ChatMessageTile(
                    siteUrl: siteUrl,
                    messageId: hit.message.id,
                    chained: false,
                    showThreadSummary: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({required this.icon, required this.text});

  final DIconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DIcon(icon, size: 28),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _SearchFailure extends StatelessWidget {
  const _SearchFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}
