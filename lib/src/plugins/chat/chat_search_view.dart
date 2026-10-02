import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_message_tile.dart';
import 'chat_plugin.dart';
import 'chat_search.dart';
import 'chat_search_controller.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

final RegExp _htmlTags = RegExp(r'<[^>]*>');

class ChatSearchView extends StatefulWidget {
  const ChatSearchView({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<ChatSearchView> createState() => _ChatSearchViewState();
}

class _ChatSearchViewState extends State<ChatSearchView> {
  late ChatSearchController _search;
  ChatShellService? _shell;
  String? _boundSite;
  final TextEditingController _query = TextEditingController();
  late final FocusNode _focus;
  late final ScrollController _scroll;
  VoidCallback? _unregisterFocus;
  VoidCallback? _unregisterRefresher;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode(debugLabel: 'chat search');
    _scroll = ScrollController()..addListener(_maybeLoadMore);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(covariant ChatSearchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl) _bind();
  }

  void _bind() {
    final search = PluginUiScope.require(context, chatSearchControllerService);
    final shell = PluginUiScope.require(context, chatShellService);
    final siteUrl = widget.siteUrl;
    if (_ready &&
        identical(_search, search) &&
        identical(_shell, shell) &&
        _boundSite == siteUrl) {
      return;
    }
    _detach();
    _search = search;
    _shell = shell;
    _boundSite = siteUrl;
    _query.text = search.globalState(siteUrl).query;
    _unregisterFocus = search.registerGlobalFocus(siteUrl, _focus.requestFocus);
    _unregisterRefresher = shell.registerRouteRefresher(
      siteUrl,
      ChatPlugin.searchRouteId,
      () => search.retryGlobal(siteUrl),
    );
    _ready = true;
  }

  void _detach() {
    _unregisterFocus?.call();
    _unregisterFocus = null;
    _unregisterRefresher?.call();
    _unregisterRefresher = null;
  }

  @override
  void dispose() {
    _detach();
    _scroll.dispose();
    _focus.dispose();
    _query.dispose();
    super.dispose();
  }

  // A failed page is retried only from its Try again row: every scroll
  // update near the end would otherwise resend it as soon as it fails.
  void _maybeLoadMore() {
    if (!_scroll.hasClients ||
        _search.globalState(widget.siteUrl).error != null ||
        _scroll.position.extentAfter >
            paginationPrefetchDistance(_scroll.position)) {
      return;
    }
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
            focusNode: _focus,
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
      return _SearchMessage(
        icon: DIcons.magnifyingGlass,
        text: appL10n.searchMessagesAcrossYourChatChannels,
      );
    }
    if (state.hits.isEmpty &&
        (state.phase == ChatSearchPhase.waiting ||
            state.phase == ChatSearchPhase.loading)) {
      return const SizedBox.shrink();
    }
    if (state.phase == ChatSearchPhase.empty) {
      return _SearchMessage(
        icon: DIcons.magnifyingGlass,
        text: appL10n.noChatMessagesFound,
      );
    }
    if (state.phase == ChatSearchPhase.failed && state.hits.isEmpty) {
      return _SearchFailure(
        message: state.error ?? appL10n.couldNotSearchChat,
        onRetry: () => _search.retryGlobal(widget.siteUrl),
      );
    }
    if (state.hits.isEmpty) return const SizedBox.shrink();

    final hasFooter = state.loadingMore || state.error != null || state.hasMore;
    return ContentReadingLane(
      basePadding: const EdgeInsets.symmetric(vertical: 8),
      builder: (context, lane) => ListView.separated(
        key: const PageStorageKey('chat-search-results'),
        controller: _scroll,
        padding: lane.padding,
        itemCount: state.hits.length + (hasFooter ? 1 : 0),
        separatorBuilder: (_, _) => const DSeparator(space: 1),
        itemBuilder: (context, index) {
          if (index == state.hits.length) {
            if (state.loadingMore) {
              return const SizedBox.shrink();
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
                  DButton(
                    label: Text(
                      state.error == null ? appL10n.loadMore : appL10n.tryAgain,
                    ),
                    onPressed: () => _search.loadMore(widget.siteUrl),
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
      ),
    );
  }

  Future<void> _open(ChatSearchHit hit) async {
    final chat = PluginUiScope.require(context, chatControllerService);
    try {
      final channel = await chat.ensureChannel(widget.siteUrl, hit.channel.id);
      if (!mounted || channel == null) throw StateError('Channel unavailable');
      final shell = PluginUiScope.require(context, chatShellService);
      if (hit.message.threadId case final threadId?) {
        shell.openThread(
          siteUrl: widget.siteUrl,
          channelId: channel.id,
          threadId: threadId,
          messageId: hit.message.id,
        );
      } else {
        shell.openChannel(channel.id, messageId: hit.message.id);
      }
    } catch (_) {
      if (!mounted) return;
      DToast.show(
        context,
        appL10n.couldNotOpenThisChatMessage,
        type: DToastType.error,
      );
    }
  }
}

class _SearchControls extends StatelessWidget {
  const _SearchControls({
    required this.controller,
    required this.focusNode,
    required this.state,
    required this.onChanged,
    required this.onClear,
    required this.onSort,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final GlobalChatSearchState state;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<ChatSearchSort> onSort;

  static List<ChoiceMenuOption<ChatSearchSort>> get _sortOptions => [
    ChoiceMenuOption(
      value: ChatSearchSort.relevance,
      title: appL10n.relevance,
      description: appL10n.bestMatchingMessagesFirst,
      icon: DIcons.magnifyingGlass,
    ),
    ChoiceMenuOption(
      value: ChatSearchSort.latest,
      title: appL10n.latest,
      description: appL10n.newestMessagesFirst,
      icon: DIcons.farClock,
    ),
  ];

  String _sortLabel(ChatSearchSort sort) => switch (sort) {
    ChatSearchSort.relevance => appL10n.relevance,
    ChatSearchSort.latest => appL10n.latest,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            Expanded(
              child: DInputGroup(
                children: [
                  DInputGroupInput(
                    key: const ValueKey('chat-search-field'),
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    semanticLabel: context.l10n.searchMessages,
                    hintText: context.l10n.searchMessages,
                    textInputAction: TextInputAction.search,
                    onChanged: onChanged,
                  ),
                  const DInputGroupAddon(
                    child: DIcon(DIcons.magnifyingGlass, size: 18),
                  ),
                  if (state.query.isNotEmpty)
                    DInputGroupAddon(
                      alignment: DInputGroupAddonAlignment.inlineEnd,
                      child: DInputGroupButton.icon(
                        onPressed: onClear,
                        icon: const DIcon(DIcons.xmark, size: 16),
                        tooltip: context.l10n.clearSearch,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ChoiceMenuAnchor<ChatSearchSort>(
              title: context.l10n.sortSearchResults,
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
                  tooltip: context.l10n.sortSearchResults,
                  semanticLabel: context.l10n.sortSearchResultsBy(
                    (label).toString(),
                  ),
                  variant: DButtonVariant.ghost,
                  onPressed: openMenu,
                );
              },
            ),
          ],
        ),
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
    final preview = (hit.excerpt ?? '').replaceAll(_htmlTags, ' ').trim();
    final label = [
      '${hit.message.author.displayName}:',
      if (preview.isNotEmpty) preview,
      if (threadTitle != null) context.l10n.inThread((threadTitle).toString()),
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
    child: SingleChildScrollView(
      child: DEmpty(
        children: [
          DEmptyHeader(
            children: [
              DEmptyMedia(variant: DEmptyMediaVariant.icon, child: DIcon(icon)),
              DEmptyTitle(text),
            ],
          ),
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
    child: SingleChildScrollView(
      child: DEmpty(
        children: [
          DEmptyHeader(children: [DEmptyTitle(message)]),
          DEmptyContent(
            children: [
              DButton(label: Text(context.l10n.tryAgain), onPressed: onRetry),
            ],
          ),
        ],
      ),
    ),
  );
}
