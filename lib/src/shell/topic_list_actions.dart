import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/topic_filter.dart';
import '../theme/d_native_icons.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_filter_controller.dart';
import 'topic_filter_input.dart';

/// The same list presentation controls are used in every topic source.
class TopicListActions extends StatelessWidget {
  const TopicListActions({super.key, this.filter});
  final Widget? filter;

  @override
  Widget build(BuildContext context) {
    final settings = ShellScope.maybeIdentityOf(context)?.appSettings;
    if (settings == null) return filter ?? const SizedBox.shrink();
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DSpacing.controlGap,
        children: [
          ?filter,
          DDropdownMenu(
            content: DDropdownMenuContent(
              width: 280,
              semanticLabel: 'Display topics',
              children: [
                const DDropdownMenuLabel(child: Text('Display')),
                DDropdownMenuCheckboxItem(
                  checked: settings.topicListLargerText,
                  onChanged: (value) =>
                      unawaited(settings.setTopicListLargerText(value)),
                  child: const Text('Larger text'),
                ),
                DDropdownMenuCheckboxItem(
                  checked: settings.topicListShowTags,
                  onChanged: (value) =>
                      unawaited(settings.setTopicListShowTags(value)),
                  child: const Text('Show tags'),
                ),
                DDropdownMenuCheckboxItem(
                  checked: settings.topicListShowLastPoster,
                  onChanged: (value) =>
                      unawaited(settings.setTopicListShowLastPoster(value)),
                  child: const Text('Show last poster'),
                ),
                DDropdownMenuCheckboxItem(
                  checked: settings.topicListShowAssignments,
                  onChanged: (value) =>
                      unawaited(settings.setTopicListShowAssignments(value)),
                  child: const Text('Show assignments'),
                ),
              ],
            ),
            child: DDropdownMenuTrigger(
              builder: (context, trigger) => DButton.iconOnly(
                key: const ValueKey('topic-list-display'),
                tooltip: 'Display',
                icon: const DIcon(DNativeIcons.sliders),
                size: DButtonSize.large,
                variant: DButtonVariant.transparentBackground,
                focusNode: trigger.focusNode,
                hasPopup: true,
                expanded: trigger.open,
                onPressed: trigger.toggle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loads the server's autocomplete vocabulary only when the menu is opened.
/// A route/account change disposes this menu before a late lookup can apply.
class TopicListFilterMenu extends StatefulWidget {
  const TopicListFilterMenu({
    super.key,
    required this.siteUrl,
    required this.query,
    this.onSubmitted,
  });
  final String siteUrl;
  final String query;
  final Future<void> Function(String)? onSubmitted;

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
  Object? _owner;
  bool _retired = false;

  Object _ownerOf(ShellController shell) => (
    shell.currentInstance?.url,
    shell.currentAccountIdentity,
    shell.lifecycle.capture(widget.siteUrl).session,
    shell.rootMode,
    shell.activeTabId,
    shell.topicListContent?.id,
    shell.topicListContent?.feedPath,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = ShellScope.identityOf(context);
    if (identical(shell, _shell)) return;
    _shell?.removeListener(_checkOwner);
    _shell = shell;
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
      semanticLabel: 'Filter topics',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          const Text('Filter topics'),
          TopicFilterInput(
            key: ValueKey(_presetRevision),
            siteUrl: widget.siteUrl,
            initialQuery: _query,
            options: _options ?? const [],
            categories: ShellScope.read(
              context,
            ).filterCategoriesFor(widget.siteUrl),
            hintText: 'Add a filter…',
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
              for (final (label, query) in const [
                ('Open topics', 'status:open'),
                ('Unanswered', 'status:noreplies'),
                ('Closed topics', 'status:closed'),
                ('Bookmarked', 'in:bookmarked'),
                ('Unread replies', 'in:new-replies'),
                ('New topics', 'in:new-topics'),
                ('Unseen', 'in:unseen'),
                ('Watching', 'in:watching'),
                ('Tracking', 'in:tracking'),
              ])
                DToggle(
                  pressed: splitTopicFilterQuery(_query).contains(query),
                  variant: DToggleVariant.outline,
                  onPressedChanged: (pressed) => setState(() {
                    final clauses = splitTopicFilterQuery(_query)
                      ..removeWhere((clause) => clause == query);
                    if (pressed) clauses.add(query);
                    _query = clauses.join(' ');
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
                  label: const Text('Clear filter'),
                  variant: DButtonVariant.ghost,
                  onPressed: () => _apply(''),
                ),
                const Spacer(),
              ],
              DButton(
                label: const Text('Apply filter'),
                onPressed: () => _apply(_query),
              ),
            ],
          ),
        ],
      ),
    ),
    child: DPopoverTrigger(
      builder: (context, trigger) => DButton.iconOnly(
        key: const ValueKey('topic-list-filter'),
        tooltip: widget.query.isEmpty ? 'Filter topics' : 'Edit active filter',
        icon: const DIcon(DNativeIcons.filterLines),
        size: DButtonSize.large,
        variant: widget.query.isEmpty
            ? DButtonVariant.transparentBackground
            : DButtonVariant.primary,
        focusNode: trigger.focusNode,
        expanded: trigger.open,
        hasPopup: true,
        onPressed: trigger.toggle,
      ),
    ),
  );
}
