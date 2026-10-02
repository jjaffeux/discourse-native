import 'dart:async';
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'ai_conversations_service.dart';
import 'discourse_ai_icons.dart';

class AiConversationsPage extends StatefulWidget {
  const AiConversationsPage({
    super.key,
    required this.siteUrl,
    required this.service,
  });
  final String siteUrl;
  final AiConversationsService service;
  @override
  State<AiConversationsPage> createState() => _AiConversationsPageState();
}

class _AiConversationsPageState extends State<AiConversationsPage> {
  List<AiConversation> _conversations = [];
  bool _loading = true;
  bool _hasMore = false;
  bool _unavailable = false;
  bool _error = false;
  bool _retryMore = false;
  int _page = -1;
  Object? _request;
  late PluginSiteLease _account;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(AiConversationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl ||
        !identical(oldWidget.service, widget.service) ||
        !_account.isCurrent) {
      _bind();
    }
  }

  void _bind() {
    _account = widget.service.requests.capture(widget.siteUrl);
    _conversations = [];
    _page = -1;
    _hasMore = false;
    unawaited(_load());
  }

  Future<void> _load({bool more = false}) async {
    final request = Object();
    final account = _account;
    _request = request;
    setState(() {
      _loading = true;
      _retryMore = more;
      _error = false;
      _unavailable = false;
    });
    try {
      final result = await widget.service.load(
        widget.siteUrl,
        page: more ? _page + 1 : 0,
      );
      if (!mounted ||
          _request != request ||
          !account.isCurrent ||
          result == null) {
        return;
      }
      setState(() {
        final rows = more
            ? [..._conversations, ...result.conversations]
            : result.conversations;
        final seen = <int>{};
        _conversations = rows.where((row) => seen.add(row.id)).toList();
        _page = result.page;
        _hasMore = result.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || _request != request || !account.isCurrent) return;
      setState(() {
        _loading = false;
        _error = true;
        _unavailable = error is AiConversationsUnavailable;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ContentReadingLaneBox(
    widthLimit: 820,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(DSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: DText(
                  context.l10n.aiConversations,
                  variant: DTextVariant.h3,
                  headingLevel: 1,
                ),
              ),
              DButton.iconOnly(
                icon: const DIcon(DIcons.arrowsRotate),
                tooltip: context.l10n.refresh,
                variant: DButtonVariant.ghost,
                onPressed: _loading ? null : () => _load(),
              ),
            ],
          ),
        ),
        Expanded(child: _body(context)),
      ],
    ),
  );

  Widget _body(BuildContext context) {
    if (!widget.service.available(widget.siteUrl)) {
      return SingleChildScrollView(
        child: DEmpty(
          children: [
            DEmptyHeader(
              children: [DEmptyTitle(context.l10n.aiConversationsUnavailable)],
            ),
            DEmptyContent(
              children: [
                DButton(
                  label: Text(context.l10n.aiConversationsOpenForum),
                  onPressed: () => widget.service.openForum(widget.siteUrl),
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (_loading && _conversations.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: DSkeletonRegion(
            color: skeletonFill(context),
            semanticsLabel: context.l10n.aiConversationsLoading,
            child: Column(
              children: [
                for (var i = 0; i < (constraints.maxHeight / 80).ceil(); i++)
                  const Padding(
                    padding: EdgeInsets.all(DSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DSkeleton(width: 240, height: 18),
                        SizedBox(height: DSpacing.sm),
                        DSkeleton(width: 120, height: 14),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    if (_conversations.isEmpty || _unavailable) {
      return SingleChildScrollView(
        child: DEmpty(
          children: [
            DEmptyHeader(
              children: [
                const DEmptyMedia(
                  variant: DEmptyMediaVariant.icon,
                  child: DIcon(DiscourseAiIcons.sparkles),
                ),
                DEmptyTitle(
                  _unavailable
                      ? context.l10n.aiConversationsUnavailable
                      : _error
                      ? context.l10n.aiConversationsLoadFailed
                      : context.l10n.aiConversationsEmpty,
                ),
              ],
            ),
            DEmptyContent(
              children: [
                if (_error && !_unavailable)
                  DButton(
                    label: Text(context.l10n.retry),
                    onPressed: () => _load(),
                  ),
                DButton(
                  label: Text(context.l10n.aiConversationsOpenForum),
                  variant: DButtonVariant.outline,
                  onPressed: () => widget.service.openForum(widget.siteUrl),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return ListView(
      children: [
        for (final conversation in _conversations)
          DItem(
            key: ValueKey('ai-conversation-${conversation.id}'),
            shape: DItemShape.fullWidth,
            onPressed: () => widget.service.open(widget.siteUrl, conversation),
            children: [
              DItemMedia(
                child: DIcon(
                  conversation.starred
                      ? DIcons.star
                      : DiscourseAiIcons.sparkles,
                ),
              ),
              DItemContent(
                children: [DItemTitle(child: Text(conversation.title))],
              ),
            ],
          ),
        if (_error)
          Padding(
            padding: const EdgeInsets.all(DSpacing.lg),
            child: DText(context.l10n.aiConversationsLoadFailed),
          ),
        if (_hasMore || _error)
          Padding(
            padding: const EdgeInsets.all(DSpacing.lg),
            child: DButton(
              label: Text(_error ? context.l10n.retry : context.l10n.loadMore),
              loading: _loading,
              onPressed: _loading
                  ? null
                  : () => _load(more: _error ? _retryMore : true),
            ),
          ),
      ],
    );
  }
}
