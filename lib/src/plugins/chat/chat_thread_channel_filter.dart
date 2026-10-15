import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_channel.dart';
import 'chat_controller.dart';

/// Uses the topic filter's Native popover and searchable command composition.
class ChatThreadChannelFilter extends StatefulWidget {
  const ChatThreadChannelFilter({
    super.key,
    required this.chat,
    required this.siteUrl,
    required this.selected,
    required this.onSelected,
  });

  final ChatController chat;
  final String siteUrl;
  final ChatChannel? selected;
  final ValueChanged<ChatChannel?> onSelected;

  @override
  State<ChatThreadChannelFilter> createState() =>
      _ChatThreadChannelFilterState();
}

class _ChatThreadChannelFilterState extends State<ChatThreadChannelFilter> {
  final _popover = DPopoverController();
  late final PluginSiteLease _session;
  Timer? _debounce;
  int _generation = 0;
  String _query = '';
  List<ChatChannel> _channels = [];
  int _offset = 0;
  bool _hasMore = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _session = widget.chat.captureSession(widget.siteUrl);
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    final offset = more ? _offset : 0;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.chat.fetchBrowseChannels(
      widget.siteUrl,
      filter: _query.trim(),
      offset: offset,
    );
    if (!mounted || !_session.isCurrent || generation != _generation) return;
    setState(() {
      _loading = false;
      _error = result.error;
      if (result.page case final page?) {
        _channels = {
          if (more)
            for (final channel in _channels) channel.id: channel,
          for (final channel in page.channels)
            if (channel.threadingEnabled) channel.id: channel,
        }.values.toList();
        _offset = offset + page.rowCount;
        _hasMore = page.hasMore && page.rowCount > 0;
      }
    });
  }

  void _queryChanged(String query) {
    _debounce?.cancel();
    _generation++;
    setState(() {
      _query = query;
      _channels = [];
      _offset = 0;
      _hasMore = false;
      _error = null;
      _loading = true;
    });
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_load()),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final label = selected?.title ?? context.l10n.channel;
    final mobile = {
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.fuchsia,
    }.contains(Theme.of(context).platform);
    return DPopover(
      controller: _popover,
      sheetOnMobile: true,
      mobileSheetVariant: DSheetVariant.adaptiveMenu,
      mobileSheetSizeToContent: false,
      mobileSheetContentLoading: _loading,
      onOpenChange: (open, _) {
        _debounce?.cancel();
        _generation++;
        if (open) {
          _query = '';
          _channels = [];
          _offset = 0;
          _hasMore = false;
          unawaited(_load());
        }
      },
      content: DPopoverContent(
        width: 320,
        align: DPopoverAlign.start,
        sideOffset: 6,
        padding: const EdgeInsets.all(4),
        scrollable: false,
        semanticLabel: context.l10n.channel,
        child: DCommand<int>(
          query: _query,
          shouldFilter: false,
          loading: _loading,
          onQueryChanged: _queryChanged,
          onEscape: _popover.close,
          onSelected: (id) {
            if (!_session.isCurrent) return;
            if (id == -1) {
              unawaited(_load(more: true));
              return;
            }
            if (id == -2) {
              unawaited(_load(more: _offset > 0));
              return;
            }
            final channel = _channels
                .where((channel) => channel.id == id)
                .firstOrNull;
            if (id != 0 && channel == null) return;
            _popover.close();
            widget.onSelected(channel);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DCommandInput<int>(
                key: const ValueKey('chat-thread-channel-query'),
                density: DCommandInputDensity.menuFilter,
                placeholder: context.l10n.findAChannel,
                semanticLabel: context.l10n.findAChannel,
                autofocus: !mobile,
              ),
              if (_error case final error?)
                Padding(padding: const EdgeInsets.all(8), child: Text(error)),
              Flexible(
                child: DCommandList<int>(
                  maxHeight: mobile ? MediaQuery.sizeOf(context).height : 360,
                  children: [
                    if (_query.trim().isEmpty)
                      DCommandItem<int>(
                        value: 0,
                        checked: selected == null,
                        semanticLabel: context.l10n.allChannels,
                        child: Text(context.l10n.allChannels),
                      ),
                    for (final channel in _channels)
                      DCommandItem<int>(
                        key: ValueKey((
                          'chat-thread-channel-option',
                          channel.id,
                        )),
                        value: channel.id,
                        checked: selected?.id == channel.id,
                        semanticLabel: channel.title,
                        leading: Text(
                          '#',
                          style: TextStyle(color: channel.categoryColor),
                        ),
                        child: Text(channel.title),
                      ),
                    if (_loading)
                      DCommandLoading(child: Text(context.l10n.loading)),
                    if (!_loading && _error != null)
                      DCommandItem<int>(
                        value: -2,
                        child: Text(context.l10n.tryAgain),
                      )
                    else if (!_loading && _hasMore)
                      DCommandItem<int>(
                        value: -1,
                        child: Text(context.l10n.loadMore),
                      ),
                    DCommandEmpty(
                      child: Text(context.l10n.noChannelsMatchTheseFilters),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      child: DPopoverTrigger(
        builder: (context, trigger) => DButton(
          key: const ValueKey('chat-threads-channel-filter'),
          size: DButtonSize.filter,
          variant: selected == null
              ? DButtonVariant.quiet
              : DButtonVariant.quietSelected,
          semanticLabel: '${context.l10n.channel}, $label',
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          icon: Text(
            '■',
            style: TextStyle(
              color:
                  selected?.categoryColor ??
                  DTokens.of(context).mutedForeground,
            ),
          ),
          focusNode: trigger.focusNode,
          hasPopup: true,
          expanded: trigger.open,
          onPressed: trigger.toggle,
        ),
      ),
    );
  }
}
