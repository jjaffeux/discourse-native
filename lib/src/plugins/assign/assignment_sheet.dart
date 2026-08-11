import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/discourse_api_contracts.dart';
import '../../shell/avatar_image.dart';
import '../../shell/shell_scope.dart';
import '../../shell/shell_sheet.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
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

/// Opens the one write surface for both topic and post assignments.
///
/// Suggestions and writes are target-scoped on the server. Keeping the target
/// captured here makes it impossible for a picker opened for one post to write
/// to whichever post happens to be current by the time the request finishes.
Future<void> showAssignmentEditor({
  required BuildContext context,
  required String siteUrl,
  required AssignmentTarget target,
  Assignment? existing,
  bool nested = false,
}) {
  final controller = ShellScope.read(context);
  final config = controller.siteConfigFor(siteUrl);
  final targetName = target.type == AssignmentTargetType.topic
      ? 'topic'
      : 'post';
  final title = existing == null
      ? 'Assign $targetName'
      : 'Edit $targetName assignment';
  Widget editor(BuildContext presentationContext) => AssignmentEditor(
    existing: existing,
    statusesEnabled: config.assignStatusesEnabled,
    statuses: config.assignStatuses,
    loadSuggestions: () => controller.assignmentSuggestions(siteUrl, target),
    searchAssignees: (suggestions, term) => controller
        .searchAssignmentAssignees(siteUrl, target, suggestions, term),
    save: (assignee, {note, status}) => controller.assignTarget(
      siteUrl,
      target,
      assignee,
      note: note,
      status: status,
    ),
    remove: existing == null
        ? null
        : () => controller.unassignTarget(siteUrl, target),
    onComplete: () => Navigator.of(presentationContext).pop(),
  );
  final isTouch = switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    _ => false,
  };

  if (isTouch) {
    return showShellSheet<void>(
      context: context,
      title: title,
      nested: nested,
      builder: editor,
    );
  }

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(dialogContext).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const DIcon(DIcons.xmark),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Divider(color: Theme.of(dialogContext).shell.divider, height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: editor(dialogContext),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A target-aware user/group picker used inside [showAssignmentEditor].
///
/// It is public so its asynchronous behavior can be tested without constructing
/// an entire shell. Product code should normally open it through the function
/// above, which always supplies the exact target and controller methods.
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
        // Site settings arrive independently from the topic payload. Preserve
        // the serialized status while they are still unknown; omitting it on
        // a detail edit makes Assign reset it to the first configured status.
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
      // PopScope still reflects the previous build until the next frame. Wait
      // for canPop to become true before the successful write closes its sheet.
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('assignment-search'),
            controller: _searchController,
            enabled: !_saving,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              labelText: 'User or group',
              hintText: 'Search by name',
              prefixIcon: DIcon(DIcons.magnifyingGlass),
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingSuggestions)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator.adaptive(),
              ),
            )
          else if (_suggestions != null) ...[
            if (_searching) const LinearProgressIndicator(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: _results.isEmpty && !_searching
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No matching users or groups.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
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
          const SizedBox(height: 12),
          TextField(
            key: const Key('assignment-note'),
            controller: _noteController,
            enabled: !_saving,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              alignLabelWithHint: true,
            ),
          ),
          if (widget.statusesEnabled && statuses.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
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
                child: TextButton(
                  key: const Key('assignment-retry-suggestions'),
                  onPressed: _saving ? null : _retrySuggestions,
                  child: const Text('Retry'),
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
                OutlinedButton.icon(
                  key: const Key('assignment-unassign'),
                  onPressed: _saving ? null : _remove,
                  icon: const DIcon(DIcons.circleMinus),
                  label: const Text('Unassign'),
                ),
              FilledButton.icon(
                key: const Key('assignment-save'),
                onPressed: _saving || _searching || _selected == null
                    ? null
                    : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : const DIcon(DIcons.check),
                label: Text(widget.existing == null ? 'Assign' : 'Save'),
              ),
            ],
          ),
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
        child: ListTile(
          enabled: enabled,
          selected: selected,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: AssignmentAssigneeAvatar(assignee: assignee, size: 32),
          title: Text(assignee.displayName),
          subtitle: Text(subtitle),
          trailing: selected ? const DIcon(DIcons.check) : null,
          onTap: enabled ? onTap : null,
        ),
      ),
    );
  }
}

/// The same assignee identity used in picker rows and assignment summaries.
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

/// A complete, readable assignment line. Notes and statuses remain visible for
/// readers who cannot mutate the target.
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
