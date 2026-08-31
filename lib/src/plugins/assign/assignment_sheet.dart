import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/discourse_api_contracts.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../shell/anchored_picker.dart';
import '../../shell/avatar_image.dart';
import '../../shell/select.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_button.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'assign_services.dart';
import 'assignment.dart';

typedef AssignmentSuggestionsLoader = Future<AssignmentSuggestions> Function();
typedef AssignmentAssigneeSearch =
    Future<List<AssignmentAssignee>> Function(
      AssignmentSuggestions suggestions,
      String term,
    );
typedef AssignmentSave =
    Future<String?> Function(
      AssignmentAssignee assignee, {
      String? note,
      String? status,
    });
typedef AssignmentRemove = Future<String?> Function();

Future<void> showAssignmentEditor({
  required BuildContext context,
  required String siteUrl,
  required AssignmentTarget target,
  Assignment? existing,
  BuildContext? anchorContext,
  Rect? anchor,
  bool nested = false,
}) {
  final controller = PluginUiScope.require(
    context,
    assignmentControllerService,
  );
  final statusOptions = controller.statusOptions(siteUrl);
  final targetName = target.type == AssignmentTargetType.topic
      ? 'topic'
      : 'post';
  final title = existing == null
      ? 'Assign $targetName'
      : 'Edit $targetName assignment';
  Widget editor(BuildContext presentationContext) => AssignmentEditor(
    existing: existing,
    statusesEnabled: statusOptions.enabled,
    statuses: statusOptions.values,
    loadSuggestions: () => controller.suggestions(siteUrl, target),
    searchAssignees: (suggestions, term) =>
        controller.search(siteUrl, target, suggestions, term),
    save: (assignee, {note, status}) => controller.assign(
      siteUrl,
      target,
      assignee,
      note: note,
      status: status,
    ),
    remove: existing == null
        ? null
        : () => controller.unassign(siteUrl, target),
    onComplete: () => Navigator.of(presentationContext).pop(),
  );
  return showAnchoredPicker<void>(
    context: context,
    anchorContext: anchorContext,
    anchor: anchor,
    title: title,
    barrierLabel: 'Dismiss $targetName assignment picker',
    popoverKey: const ValueKey('assignment-picker-popover'),
    popoverWidth: 360,
    popoverHeight: 400,
    nested: nested,
    // Drag dismissal bypasses PopScope while a write owns the target.
    sheetEnableDrag: false,
    builder: editor,
  );
}

class AssignmentEditor extends StatefulWidget {
  const AssignmentEditor({
    super.key,
    required this.loadSuggestions,
    required this.searchAssignees,
    required this.save,
    this.remove,
    this.existing,
    this.statusesEnabled = false,
    this.statuses = const [],
    this.onComplete,
    this.searchDebounce = const Duration(milliseconds: 300),
  });

  final AssignmentSuggestionsLoader loadSuggestions;
  final AssignmentAssigneeSearch searchAssignees;
  final AssignmentSave save;
  final AssignmentRemove? remove;
  final Assignment? existing;
  final bool statusesEnabled;
  final List<String> statuses;
  final VoidCallback? onComplete;
  final Duration searchDebounce;

  @override
  State<AssignmentEditor> createState() => _AssignmentEditorState();
}

class _AssignmentEditorState extends State<AssignmentEditor> {
  late final TextEditingController _searchController;
  late final TextEditingController _noteController;
  AssignmentSuggestions? _suggestions;
  List<AssignmentAssignee> _results = const [];
  AssignmentAssignee? _selected;
  String? _status;
  String? _error;
  Timer? _searchTimer;
  int _searchEpoch = 0;
  bool _searchRunning = false;
  ({int epoch, String term})? _queuedSearch;
  bool _loadingSuggestions = true;
  bool _searching = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _noteController = TextEditingController(text: widget.existing?.note ?? '');
    _selected = widget.existing?.assignee;
    final advertisedStatuses = widget.statuses
        .map((status) => status.trim())
        .where((status) => status.isNotEmpty)
        .toList(growable: false);
    final existingStatus = _nullableText(widget.existing?.status);
    _status =
        existingStatus ??
        (advertisedStatuses.isEmpty ? null : advertisedStatuses.first);
    unawaited(_loadSuggestions());
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _queuedSearch = null;
    _searchController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    try {
      final suggestions = await widget.loadSuggestions();
      if (!mounted) return;
      setState(() {
        _suggestions = suggestions;
        _loadingSuggestions = false;
        _error = null;
        _results = _withSelected(suggestions.initialAssignees);
      });
      final term = _searchController.text.trim();
      if (term.isNotEmpty) _scheduleSearch(term, immediate: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingSuggestions = false;
        _error = _errorText(error);
      });
    }
  }

  void _retrySuggestions() {
    if (_loadingSuggestions || _saving) return;
    _searchTimer?.cancel();
    ++_searchEpoch;
    setState(() {
      _loadingSuggestions = true;
      _searching = false;
      _error = null;
      _results = const [];
    });
    unawaited(_loadSuggestions());
  }

  void _onSearchChanged(String rawTerm) {
    final term = rawTerm.trim();
    if (term.isEmpty) {
      _searchTimer?.cancel();
      ++_searchEpoch;
      _queuedSearch = null;
      setState(() {
        _searching = false;
        _error = null;
        _results = _withSelected(
          _suggestions?.initialAssignees ?? const <AssignmentAssignee>[],
        );
      });
      return;
    }
    _scheduleSearch(term);
  }

  void _scheduleSearch(String term, {bool immediate = false}) {
    _searchTimer?.cancel();
    if (_suggestions == null) return;
    final epoch = ++_searchEpoch;
    setState(() {
      _searching = true;
      _error = null;
    });
    if (immediate || widget.searchDebounce == Duration.zero) {
      _enqueueSearch(epoch, term);
      return;
    }
    _searchTimer = Timer(
      widget.searchDebounce,
      () => _enqueueSearch(epoch, term),
    );
  }

  void _enqueueSearch(int epoch, String term) {
    if (!mounted || epoch != _searchEpoch) return;
    if (_searchRunning) {
      _queuedSearch = (epoch: epoch, term: term);
      return;
    }
    _searchRunning = true;
    unawaited(_runSearch(epoch, term));
  }

  Future<void> _runSearch(int epoch, String term) async {
    final suggestions = _suggestions;
    if (suggestions == null) return;
    try {
      final results = await widget.searchAssignees(suggestions, term);
      if (!mounted || epoch != _searchEpoch) return;
      setState(() {
        _results = _withSelected(results);
        _searching = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || epoch != _searchEpoch) return;
      setState(() {
        _searching = false;
        _error = _errorText(error);
      });
    } finally {
      _searchRunning = false;
      final queued = _queuedSearch;
      _queuedSearch = null;
      if (queued != null && mounted && queued.epoch == _searchEpoch) {
        _enqueueSearch(queued.epoch, queued.term);
      }
    }
  }

  List<AssignmentAssignee> _withSelected(
    Iterable<AssignmentAssignee> assignees,
  ) {
    final unique = <String, AssignmentAssignee>{};
    if (_selected case final selected?) {
      unique[_assigneeKey(selected)] = selected;
    }
    for (final assignee in assignees) {
      unique.putIfAbsent(_assigneeKey(assignee), () => assignee);
    }
    return List.unmodifiable(unique.values);
  }

  Future<void> _save() async {
    final selected = _selected;
    if (_saving || selected == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.save(
        selected,
        note: _nullableText(_noteController.text),
        // Preserve serialized status until independently loaded settings arrive.
        status: widget.statusesEnabled
            ? _nullableText(_status)
            : widget.existing?.status,
      );
    } catch (caught) {
      error = _errorText(caught);
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
    if (error == null) {
      // PopScope exposes the successful write's canPop state next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onComplete?.call();
      });
    }
  }

  Future<void> _remove() async {
    final remove = widget.remove;
    if (_saving || remove == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    String? error;
    try {
      error = await remove();
    } catch (caught) {
      error = _errorText(caught);
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
    if (error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onComplete?.call();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statuses = <String>{
      ...widget.statuses
          .map((status) => status.trim())
          .where((status) => status.isNotEmpty),
      ?_nullableText(widget.existing?.status),
    }.toList(growable: false);

    return PopScope(
      canPop: !_saving,
      child: AnchoredPickerContent(
        queryKey: const Key('assignment-search'),
        queryController: _searchController,
        queryHint: 'Search users or groups…',
        queryEnabled: !_saving,
        onQueryChanged: _onSearchChanged,
        onQuerySubmitted: _onSearchChanged,
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('assignment-note'),
              controller: _noteController,
              enabled: !_saving,
              minLines: 3,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.statusesEnabled && statuses.isNotEmpty) ...[
              const SizedBox(height: 12),
              DSelectField<String>(
                key: const Key('assignment-status'),
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  for (final status in statuses)
                    DropdownMenuItem(
                      value: status,
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _status = _nullableText(value)),
              ),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                container: true,
                child: Text(
                  error,
                  key: const Key('assignment-error'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
              if (_suggestions == null && !_loadingSuggestions)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: DButton(
                    key: const Key('assignment-retry-suggestions'),
                    label: const Text('Retry'),
                    onPressed: _saving ? null : _retrySuggestions,
                    variant: DButtonVariant.link,
                  ),
                ),
            ],
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.remove != null)
                  DButton(
                    key: const Key('assignment-unassign'),
                    label: const Text('Unassign'),
                    onPressed: _remove,
                    variant: DButtonVariant.danger,
                    loading: _saving,
                  ),
                DButton(
                  key: const Key('assignment-save'),
                  label: Text(widget.existing == null ? 'Assign' : 'Save'),
                  onPressed: _searching || _selected == null ? null : _save,
                  icon: const DIcon(DIcons.check),
                  variant: DButtonVariant.primary,
                  loading: _saving,
                ),
              ],
            ),
          ],
        ),
        children: [
          if (_loadingSuggestions)
            const AnchoredPickerProgress()
          else if (_suggestions != null) ...[
            if (_searching) const LinearProgressIndicator(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: _results.isEmpty && !_searching
                  ? Semantics(
                      key: const Key('assignment-empty-results'),
                      container: true,
                      liveRegion: true,
                      child: const AnchoredPickerMessage(
                        'No matching users or groups.',
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final assignee = _results[index];
                        final selected = _sameAssignee(assignee, _selected);
                        return _AssigneeChoice(
                          key: Key(
                            'assignment-assignee-${_assigneeKey(assignee)}',
                          ),
                          assignee: assignee,
                          selected: selected,
                          enabled: !_saving && !_searching,
                          onTap: () => setState(() => _selected = assignee),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssigneeChoice extends StatelessWidget {
  const _AssigneeChoice({
    super.key,
    required this.assignee,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final AssignmentAssignee assignee;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = assignee.isGroup
        ? 'Group @${assignee.groupName}'
        : '@${assignee.username}';
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: '${assignee.displayName}, $subtitle',
      onTap: enabled ? onTap : null,
      child: ExcludeSemantics(
        child: AnchoredPickerOption(
          enabled: enabled,
          selected: selected,
          showSelectionIndicator: true,
          leading: AssignmentAssigneeAvatar(assignee: assignee, size: 32),
          title: Text(assignee.displayName),
          subtitle: Text(subtitle),
          onTap: enabled ? onTap : null,
        ),
      ),
    );
  }
}

class AssignmentAssigneeAvatar extends StatelessWidget {
  const AssignmentAssigneeAvatar({
    super.key,
    required this.assignee,
    required this.size,
  });

  final AssignmentAssignee assignee;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = ColoredBox(
      color: theme.shell.mention,
      child: Center(
        child: DIcon(
          assignee.isGroup ? DIcons.users : DIcons.user,
          size: size * 0.58,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: assignee.isGroup
            ? fallback
            : AvatarImage(
                url: assignee.avatarUrl,
                size: size,
                fallback: fallback,
              ),
      ),
    );
  }
}

class AssignmentDetailRow extends StatelessWidget {
  const AssignmentDetailRow({
    super.key,
    required this.assignment,
    required this.targetLabel,
    this.onTap,
  });

  final Assignment assignment;
  final String targetLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = <String>[
      if (assignment.assignee.isGroup)
        'Group @${assignment.assignee.groupName}'
      else
        '@${assignment.assignee.username}',
      if (_nullableText(assignment.status) case final status?)
        'Status: $status',
      if (_nullableText(assignment.note) case final note?) 'Note: $note',
    ];
    final label = [
      '$targetLabel assigned to ${assignment.assignee.displayName}',
      ...subtitle,
      if (onTap != null) 'Edit assignment',
    ].join('. ');

    return Semantics(
      container: true,
      button: onTap != null,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: theme.shell.mention.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          child: ListTile(
            dense: true,
            leading: AssignmentAssigneeAvatar(
              assignee: assignment.assignee,
              size: 34,
            ),
            title: Text(
              '$targetLabel assigned to ${assignment.assignee.displayName}',
            ),
            subtitle: Text(subtitle.join('\n')),
            trailing: onTap == null ? null : const DIcon(DIcons.pencil),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

String assignmentSummary(Assignment assignment, String targetLabel) {
  final identity = assignment.assignee.isGroup
      ? 'group @${assignment.assignee.groupName}'
      : 'user @${assignment.assignee.username}';
  final parts = <String>[
    '$targetLabel assigned to ${assignment.assignee.displayName}',
    identity,
    if (_nullableText(assignment.status) case final status?) 'status $status',
    if (_nullableText(assignment.note) case final note?) 'note $note',
  ];
  return parts.join(', ');
}

String _assigneeKey(AssignmentAssignee assignee) =>
    '${assignee.isGroup ? 'group' : 'user'}:${assignee.identifier.toLowerCase()}';

bool _sameAssignee(AssignmentAssignee left, AssignmentAssignee? right) =>
    right != null && _assigneeKey(left) == _assigneeKey(right);

String? _nullableText(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _errorText(Object error) {
  if (error is WriteException) return error.message;
  if (error is SiteLookupException) return error.message;
  final text = error.toString().trim();
  return text.replaceFirst(RegExp(r'^(Exception|Error):\s*'), '');
}
