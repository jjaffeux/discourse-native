import 'dart:async';
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'ai_conversations_service.dart';
import 'ai_conversations_session.dart';
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
  AiConversationsSession? _session;

  AiConversationsState get _state => _session!.state;
  List<AiConversation> get _conversations => _state.conversations;
  bool get _loading => _state.loading;
  bool get _hasMore => _state.hasMore;
  bool get _unavailable => _state.unavailable;
  bool get _error => _state.error;

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
        !_session!.isCurrent) {
      _bind();
    }
  }

  void _bind() {
    _session?.removeListener(_changed);
    _session?.dispose();
    final service = widget.service;
    final siteUrl = widget.siteUrl;
    final session = AiConversationsSession(
      account: service.requests.capture(siteUrl),
      load: (page) => service.load(siteUrl, page: page),
      open: (conversation) => service.open(siteUrl, conversation),
    );
    _session = session;
    session.addListener(_changed);
    unawaited(session.refresh());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session?.removeListener(_changed);
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DPageSurface.headed(
    identity: widget.siteUrl,
    title: Text(context.l10n.aiConversations),
    controls: Align(
      alignment: AlignmentDirectional.centerEnd,
      child: DButton.iconOnly(
        icon: const DIcon(DIcons.arrowsRotate),
        tooltip: context.l10n.refresh,
        variant: DButtonVariant.ghost,
        onPressed: _loading ? null : _session!.refresh,
      ),
    ),
    child: ContentReadingLaneBox(widthLimit: 820, child: _body(context)),
  );

  Widget _body(BuildContext context) {
    final session = _session!;
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
                    onPressed: session.retry,
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
    return ListView.builder(
      itemCount:
          _conversations.length +
          (_error ? 1 : 0) +
          (_hasMore || _error ? 1 : 0),
      findChildIndexCallback: (key) {
        const prefix = 'ai-conversation-';
        if (key is! ValueKey<String> || !key.value.startsWith(prefix)) {
          return null;
        }
        final id = int.tryParse(key.value.substring(prefix.length));
        if (id == null) return null;
        final index = _conversations.indexWhere(
          (conversation) => conversation.id == id,
        );
        return index < 0 ? null : index;
      },
      itemBuilder: (context, index) {
        if (index < _conversations.length) {
          final conversation = _conversations[index];
          return DItem(
            key: ValueKey('ai-conversation-${conversation.id}'),
            shape: DItemShape.fullWidth,
            onPressed: () => session.open(conversation),
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
          );
        }
        if (_error && index == _conversations.length) {
          return Padding(
            padding: const EdgeInsets.all(DSpacing.lg),
            child: DText(context.l10n.aiConversationsLoadFailed),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(DSpacing.lg),
          child: DButton(
            label: Text(_error ? context.l10n.retry : context.l10n.loadMore),
            loading: _loading,
            onPressed: _loading
                ? null
                : _error
                ? session.retry
                : session.loadMore,
          ),
        );
      },
    );
  }
}
