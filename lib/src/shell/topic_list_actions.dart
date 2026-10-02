import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/topic_filter.dart';
import '../theme/d_native_icons.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_filter_controller.dart';
import 'topic_filter_input.dart';

/// Loads the server's autocomplete vocabulary only when the menu is opened.
/// A route/account change disposes this menu before a late lookup can apply.
class TopicListFilterMenu extends StatefulWidget {
  const TopicListFilterMenu({
    super.key,
    required this.siteUrl,
    required this.query,
    this.onSubmitted,
    this.label,
  });
  final String siteUrl;
  final String query;
  final Future<void> Function(String)? onSubmitted;
  final String? label;

  @override
  State<TopicListFilterMenu> createState() => _TopicListFilterMenuState();
}

class _TopicListFilterMenuState extends State<TopicListFilterMenu> {
  final _popover = DPopoverController();
  late String _query = widget.query;
  List<TopicFilterOption>? _options;
  bool _loading = false;
  int _presetRevision = 0;
  ShellController? _shell;
  String? _tabId;
  Object? _owner;
  bool _retired = false;

  Object _ownerOf(ShellController shell) => shell.readTab(
    _tabId,
    () => (
      shell.currentInstance?.url,
      shell.currentAccountIdentity,
      shell.lifecycle.capture(widget.siteUrl).session,
      shell.rootMode,
      shell.activeTabId,
      shell.topicListContent?.id,
      shell.topicListContent?.feedPath,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = ShellScope.identityOf(context);
    final tabId = ForumTabScope.idOf(context);
    if (identical(shell, _shell) && tabId == _tabId) return;
    _shell?.removeListener(_checkOwner);
    _shell = shell;
    _tabId = tabId;
    _retired = false;
    _owner = _ownerOf(shell);
    shell.addListener(_checkOwner);
  }

  void _checkOwner() {
    if (_ownerOf(_shell!) == _owner) return;
    _retired = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _popover.close();
    });
  }

  Future<void> _load() async {
    if (_retired || _loading || _options != null) return;
    setState(() => _loading = true);
    final options = await ShellScope.read(
      context,
    ).loadTopicFilterOptions(widget.siteUrl);
    if (mounted && !_retired) {
      setState(() {
        _options = options;
        _loading = false;
      });
    }
  }

  Future<void> _apply(String query) async {
    if (!mounted || _retired) return;
    final shell = ShellScope.read(context);
    if (_retired || !identical(shell, _shell) || _ownerOf(shell) != _owner) {
      return;
    }
    _popover.close();
    if (_tabId case final tabId? when shell.activeTabId != tabId) {
      shell.selectTab(tabId);
    }
    await (widget.onSubmitted ?? shell.submitTopicFilter)(query);
  }

  @override
  void dispose() {
    _shell?.removeListener(_checkOwner);
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DPopover(
    controller: _popover,
    onOpenChange: (open, _) {
      if (open) unawaited(_load());
    },
    content: DPopoverContent(
      width: 400,
      align: DPopoverAlign.end,
      semanticLabel: context.l10n.filterTopics,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(context.l10n.filterTopics),
          TopicFilterInput(
            key: ValueKey(_presetRevision),
            siteUrl: widget.siteUrl,
            initialQuery: _query,
            options: _options ?? const [],
            categories: ShellScope.read(
              context,
            ).filterCategoriesFor(widget.siteUrl),
            hintText: context.l10n.addAFilter,
            tokenized: true,
            multiline: true,
            padding: EdgeInsets.zero,
            onChanged: (query) => setState(() => _query = query),
            onSubmitted: _apply,
          ),
          Wrap(
            spacing: DSpacing.controlGap,
            runSpacing: 8,
            children: [
              for (final (label, query) in [
                (context.l10n.openTopics, 'status:open'),
                (context.l10n.unanswered, 'status:noreplies'),
                (context.l10n.closedTopics, 'status:closed'),
                (context.l10n.bookmarked, 'in:bookmarked'),
                (context.l10n.unreadReplies, 'in:new-replies'),
                (context.l10n.newTopicsTopiclistactions, 'in:new-topics'),
                (context.l10n.unseen, 'in:unseen'),
                (context.l10n.watching, 'in:watching'),
                (context.l10n.tracking, 'in:tracking'),
              ])
                DToggle(
                  pressed: splitTopicFilterQuery(_query).contains(query),
                  variant: DToggleVariant.outline,
                  onPressedChanged: (pressed) => setState(() {
                    _query = setTopicFilterShortcut(
                      _query,
                      query,
                      selected: pressed,
                    );
                    _presetRevision++;
                  }),
                  child: Text(label),
                ),
            ],
          ),
          const DSeparator(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.query.isNotEmpty) ...[
                DButton(
                  label: Text(context.l10n.clearFilter),
                  variant: DButtonVariant.ghost,
                  onPressed: () => _apply(''),
                ),
                const Spacer(),
              ],
              DButton(
                label: Text(context.l10n.applyFilter),
                onPressed: () => _apply(_query),
              ),
            ],
          ),
        ],
      ),
    ),
    child: DPopoverTrigger(
      builder: (context, trigger) => widget.label == null
          ? DButton.iconOnly(
              key: const ValueKey('topic-list-filter'),
              tooltip: widget.query.isEmpty
                  ? context.l10n.filterTopics
                  : context.l10n.editActiveFilter,
              icon: const DIcon(DNativeIcons.filterLines),
              size: DButtonSize.large,
              variant: widget.query.isEmpty
                  ? DButtonVariant.transparentBackground
                  : DButtonVariant.primary,
              focusNode: trigger.focusNode,
              expanded: trigger.open,
              hasPopup: true,
              onPressed: trigger.toggle,
            )
          : DButton(
              key: const ValueKey('topic-list-filter'),
              label: Text(widget.label!),
              tooltip: widget.query.isEmpty
                  ? context.l10n.filterTopics
                  : context.l10n.editActiveFilter,
              icon: const DIcon(DNativeIcons.filterLines, size: 12),
              size: DButtonSize.filter,
              variant: widget.query.isEmpty
                  ? DButtonVariant.secondary
                  : DButtonVariant.primary,
              backgroundColor: widget.query.isEmpty
                  ? DTokens.of(context).footerBackground
                  : null,
              focusNode: trigger.focusNode,
              expanded: trigger.open,
              hasPopup: true,
              onPressed: trigger.toggle,
            ),
    ),
  );
}
