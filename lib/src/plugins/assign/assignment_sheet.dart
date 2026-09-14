import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../data/discourse_api_contracts.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../shell/avatar_image.dart';
import '../../theme/app_theme.dart';
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
}) {
  final controller = PluginUiScope.require(
    context,
    assignmentControllerService,
  );
  final session = controller.beginPicker(siteUrl, target);

  Future<T> fromPicker<T>(Future<T> Function() operation) async {
    if (!controller.isPickerCurrent(session) ||
        (context.mounted &&
            !identical(
              PluginUiScope.maybe(context, assignmentControllerService),
              controller,
            ))) {
      throw const WriteException(WriteFailure.forbidden);
    }
    return operation();
  }

  final statusOptions = controller.statusOptions(siteUrl);
  final targetName = target.type == AssignmentTargetType.topic
      ? 'topic'
      : 'post';
  final title = existing == null
      ? 'Assign $targetName'
      : 'Edit $targetName assignment';
  // Keep the opening presentation for this route's lifetime so a resize does
  // not remount the form or discard its draft and in-flight operations.
  final drawer = MediaQuery.sizeOf(context).width < 768;
  final editorKey = GlobalKey<_AssignmentEditorState>();
  bool canDismiss() => !(editorKey.currentState?._saving ?? false);
  Widget editor(VoidCallback close) => AssignmentEditor(
    key: editorKey,
    title: title,
    drawer: drawer,
    existing: existing,
    statusesEnabled: statusOptions.enabled,
    statuses: statusOptions.values,
    loadSuggestions: () => fromPicker(
      () => controller.suggestions(session.siteUrl, session.target),
    ),
    searchAssignees: (suggestions, term) => fromPicker(
      () =>
          controller.search(session.siteUrl, session.target, suggestions, term),
    ),
    save: (assignee, {note, status}) => fromPicker(
      () => controller.assign(
        session.siteUrl,
        session.target,
        assignee,
        note: note,
        status: status,
      ),
    ),
    remove: existing == null
        ? null
        : () => fromPicker(
            () => controller.unassign(session.siteUrl, session.target),
          ),
    onComplete: close,
    onCancel: close,
  );
  if (drawer) {
    return showDDrawer<void>(
      context: context,
      barrierLabel: 'Dismiss $targetName assignment',
      showSwipeHandle: true,
      requestInitialFocus: false,
      canDismiss: canDismiss,
      builder: (_, controller) => editor(controller.close),
    );
  }
  return showDDialog<void>(
    context: context,
    barrierLabel: 'Dismiss $targetName assignment',
    canDismiss: canDismiss,
    builder: (_, controller) => editor(controller.close),
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
    this.onCancel,
    this.title = 'Assign topic',
    this.drawer = false,
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
  final VoidCallback? onCancel;
  final String title;
  final bool drawer;
  final Duration searchDebounce;

  @override
  State<AssignmentEditor> createState() => _AssignmentEditorState();
}

class _AssignmentEditorState extends State<AssignmentEditor> {
  late final TextEditingController _searchController;
  late final TextEditingController _noteController;
  final _searchFocus = FocusNode();
  final _noteFocus = FocusNode();
  final _errorKey = GlobalKey();
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
  bool _searchFailed = false;
  late bool _noteOpen;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _noteController = TextEditingController(text: widget.existing?.note ?? '');
    _noteOpen = _nullableText(widget.existing?.note) != null;
    _selected = widget.existing?.assignee;
    final advertisedStatuses = widget.statuses
        .map((status) => status.trim())
        .where((status) => status.isNotEmpty)
        .toList(growable: false);
    final existingStatus = _nullableText(widget.existing?.status);
    _status =
        existingStatus ??
        (advertisedStatuses.isEmpty ? null : advertisedStatuses.first);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.drawer) _searchFocus.requestFocus();
    });
    unawaited(_loadSuggestions());
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _queuedSearch = null;
    _searchController.dispose();
    _noteController.dispose();
    _searchFocus.dispose();
    _noteFocus.dispose();
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
    _searchFailed = false;
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
        _results = _withSelected(results, includeSelected: false);
        _searching = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || epoch != _searchEpoch) return;
      setState(() {
        _searching = false;
        _searchFailed = true;
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
    Iterable<AssignmentAssignee> assignees, {
    bool includeSelected = true,
  }) {
    final unique = <String, AssignmentAssignee>{};
    if (includeSelected && _selected != null) {
      final selected = _selected!;
      unique[_assigneeKey(selected)] = selected;
    }
    for (final assignee in assignees) {
      unique.putIfAbsent(_assigneeKey(assignee), () => assignee);
    }
    return List.unmodifiable(unique.values);
  }

  Future<void> _save() async {
    final selected = _selected;
    if (_saving || _searching || selected == null) return;
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
    } else {
      _revealError();
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
    } else {
      _revealError();
    }
  }

  void _revealError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final errorContext = _errorKey.currentContext;
      if (mounted && errorContext != null) {
        unawaited(Scrollable.ensureVisible(errorContext));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final statuses = <String>{
      ...widget.statuses
          .map((status) => status.trim())
          .where((status) => status.isNotEmpty),
      ?_nullableText(widget.existing?.status),
    }.toList(growable: false);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.md,
      children: [
        _assignees(),
        _note(),
        if (widget.statusesEnabled && statuses.isNotEmpty)
          DRadioGroup<String>.controlled(
            key: const Key('assignment-status'),
            groupValue: _status,
            initialValue: _status,
            enabled: !_saving,
            onChanged: (value) => setState(() => _status = value),
            label: const Text('Status'),
            child: Column(
              spacing: DSpacing.sm,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final status in statuses)
                  DRadioGroupItem(value: status, label: Text(status)),
              ],
            ),
          ),
        if (_error != null)
          KeyedSubtree(key: _errorKey, child: _errorMessage()),
      ],
    );
    final cancel = DButton(
      key: const Key('assignment-cancel'),
      label: const Text('Cancel'),
      onPressed: _saving ? null : widget.onCancel,
      variant: DButtonVariant.outline,
      size: widget.drawer ? DControlSize.large : DControlSize.regular,
    );
    final save = DButton(
      key: const Key('assignment-save'),
      label: Text(
        widget.existing != null
            ? 'Save changes'
            : _selected == null
            ? 'Assign'
            : 'Assign to @${_selected!.identifier}',
        maxLines: null,
      ),
      onPressed: _saving || _searching || _selected == null ? null : _save,
      icon: const DIcon(DIcons.check),
      variant: DButtonVariant.primary,
      size: widget.drawer ? DControlSize.large : DControlSize.regular,
      loading: _saving,
    );
    final remove = widget.remove == null
        ? null
        : DButton(
            key: const Key('assignment-unassign'),
            label: const Text('Unassign'),
            onPressed: _saving ? null : _remove,
            variant: DButtonVariant.destructive,
            size: widget.drawer ? DControlSize.large : DControlSize.regular,
          );
    final close = DButton.iconOnly(
      key: const Key('assignment-close'),
      onPressed: _saving ? null : widget.onCancel,
      icon: const DIcon(DIcons.xmark),
      variant: DButtonVariant.ghost,
      size: DControlSize.small,
      tooltip: 'Close',
      semanticLabel: 'Close assignment',
    );
    final media = MediaQuery.of(context);
    // Let the header and search scroll when large text or the keyboard would
    // otherwise leave no room for the form. The draft and focus nodes stay owned
    // by this editor as the available space changes.
    final scrollHeader =
        (media.size.height - media.viewInsets.bottom) /
            media.textScaler.scale(1) <
        600;
    final drawerHeader = DDrawerHeader(
      textAlign: TextAlign.start,
      children: [
        Row(
          children: [
            Expanded(child: DDrawerTitle(child: Text(widget.title))),
            close,
          ],
        ),
        const DDrawerDescription(child: Text('Choose one person or group.')),
      ],
    );
    final drawerForm = Padding(
      padding: const EdgeInsets.symmetric(horizontal: DSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DSpacing.md,
        children: [if (scrollHeader) _search(), body],
      ),
    );

    return PopScope(
      canPop: !_saving,
      child: widget.drawer
          ? DDrawerContent(
              key: const Key('assignment-drawer'),
              semanticLabel: widget.title,
              children: [
                if (!scrollHeader) ...[
                  drawerHeader,
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DSpacing.md,
                      0,
                      DSpacing.md,
                      DSpacing.md,
                    ),
                    child: _search(),
                  ),
                ],
                DDrawerScrollArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [if (scrollHeader) drawerHeader, drawerForm],
                  ),
                ),
                DDrawerFooter(children: [save, cancel, ?remove]),
              ],
            )
          : DDialogContent(
              key: const Key('assignment-dialog'),
              maxWidth: 480,
              semanticLabel: widget.title,
              showCloseButton: widget.onCancel != null,
              closeButton: close,
              children: [
                DDialogHeader(
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: DSpacing.xl,
                      ),
                      child: DDialogTitle(child: Text(widget.title)),
                    ),
                    const DDialogDescription(
                      child: Text('Choose one person or group.'),
                    ),
                  ],
                ),
                _search(),
                DDialogScrollArea(maxHeightFactor: .5, child: body),
                DDialogFooter(children: [?remove, cancel, save]),
              ],
            ),
    );
  }

  Widget _search() => DField(
    enabled: !_saving,
    children: [
      DFieldLabel(focusNode: _searchFocus, child: const Text('Assign to')),
      DInputGroup(
        children: [
          DInputGroupInput(
            key: const Key('assignment-search'),
            controller: _searchController,
            focusNode: _searchFocus,
            semanticLabel: 'Search users or groups',
            hintText: 'Search users or groups…',
            enabled: !_saving,
            onChanged: _onSearchChanged,
            onSubmitted: _onSearchChanged,
          ),
          const DInputGroupAddon(child: DIcon(DIcons.magnifyingGlass)),
        ],
      ),
    ],
  );

  Widget _assignees() {
    if (_loadingSuggestions) {
      return const Padding(
        padding: EdgeInsets.all(DSpacing.lg),
        child: Center(child: DSpinner(semanticLabel: 'Loading assignees')),
      );
    }
    if (_suggestions == null) return const SizedBox.shrink();
    final selected = _selected;
    final stackGroupBadge =
        MediaQuery.sizeOf(context).width /
            MediaQuery.textScalerOf(context).scale(1) <
        360;
    const groupBadge = DBadge(
      variant: DBadgeVariant.outline,
      child: Text('Group'),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.sm,
      children: [
        if (_searching)
          const DProgress(semanticsLabel: 'Searching assignments'),
        DFieldDescription(
          child: Text(
            _searchController.text.trim().isEmpty
                ? 'Suggested'
                : 'Search results',
          ),
        ),
        if (_results.isEmpty && !_searching && !_searchFailed)
          Semantics(
            key: const Key('assignment-empty-results'),
            container: true,
            liveRegion: true,
            child: const DEmpty(
              children: [
                DEmptyHeader(
                  children: [
                    DEmptyTitle('No matching users or groups.'),
                    DEmptyDescription('Try a different name or username.'),
                  ],
                ),
              ],
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: DScrollArea(
              child: DRadioGroup<String>.controlled(
                groupValue: selected == null ? null : _assigneeKey(selected),
                enabled: !_saving && !_searching,
                onChanged: (value) {
                  final assignee = _results
                      .where((item) => _assigneeKey(item) == value)
                      .firstOrNull;
                  if (assignee != null) {
                    setState(() {
                      _selected = assignee;
                      _error = null;
                    });
                  }
                },
                child: Column(
                  spacing: DSpacing.sm,
                  children: [
                    for (final assignee in _results)
                      DRadioGroupItem<String>(
                        key: Key(
                          'assignment-assignee-${_assigneeKey(assignee)}',
                        ),
                        value: _assigneeKey(assignee),
                        card: true,
                        semanticLabel:
                            '${assignee.displayName}, ${assignee.isGroup ? 'group' : 'user'} @${assignee.identifier}',
                        label: ExcludeSemantics(
                          child: Row(
                            children: [
                              AssignmentAssigneeAvatar(
                                assignee: assignee,
                                size: 32,
                              ),
                              const SizedBox(width: DSpacing.md),
                              Expanded(
                                child: DItemContent(
                                  children: [
                                    DItemTitle(
                                      maxLines: null,
                                      child: Text(assignee.displayName),
                                    ),
                                    DItemDescription(
                                      maxLines: null,
                                      child: Text('@${assignee.identifier}'),
                                    ),
                                    if (assignee.isGroup && stackGroupBadge)
                                      groupBadge,
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: assignee.isGroup && !stackGroupBadge
                            ? const ExcludeSemantics(child: groupBadge)
                            : null,
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (selected != null &&
            !_results.any((item) => _sameAssignee(item, selected)))
          DFieldDescription(
            key: const Key('assignment-selected-summary'),
            child: Text('Selected: @${selected.identifier}'),
          ),
      ],
    );
  }

  Widget _note() => DCollapsible(
    open: _noteOpen,
    disabled: _saving,
    onOpenChange: (open) => setState(() => _noteOpen = open),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DCollapsibleTrigger(
            key: const Key('assignment-note-toggle'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: DSpacing.sm),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: DSpacing.sm,
                runSpacing: DSpacing.xs,
                children: [
                  DIcon(_noteOpen ? DIcons.chevronDown : DIcons.plus, size: 16),
                  Text(
                    _noteOpen
                        ? 'Hide note'
                        : _noteController.text.isEmpty
                        ? 'Add a note'
                        : 'Edit note',
                  ),
                  const DFieldDescription(child: Text('Optional')),
                ],
              ),
            ),
          ),
        ),
        DCollapsibleContent(
          keepMounted: true,
          child: DField(
            enabled: !_saving,
            children: [
              DFieldLabel(
                focusNode: _noteFocus,
                child: const Text('Note (optional)'),
              ),
              DTextarea(
                key: const Key('assignment-note'),
                controller: _noteController,
                focusNode: _noteFocus,
                semanticLabel: 'Note (optional)',
                enabled: !_saving,
                minLines: 3,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                hintText: 'Add context for the assignee…',
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _errorMessage() => DAlert(
    key: const Key('assignment-error'),
    variant: DAlertVariant.destructive,
    description: DAlertDescription(child: Text(_error!)),
    action: _suggestions == null || _searchFailed
        ? DAlertAction(
            child: DButton(
              key: Key(
                _suggestions == null
                    ? 'assignment-retry-suggestions'
                    : 'assignment-retry-search',
              ),
              label: const Text('Retry'),
              onPressed: _saving || _searching
                  ? null
                  : _suggestions == null
                  ? _retrySuggestions
                  : () {
                      _searchFailed = false;
                      _scheduleSearch(
                        _searchController.text.trim(),
                        immediate: true,
                      );
                    },
              variant: DButtonVariant.outline,
            ),
          )
        : null,
  );
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
    return DAvatar.frame(
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

    return DItem(
      variant: DItemVariant.muted,
      onPressed: onTap,
      semanticLabel: label,
      children: [
        DItemMedia(
          variant: DItemMediaVariant.avatar,
          child: ExcludeSemantics(
            child: AssignmentAssigneeAvatar(
              assignee: assignment.assignee,
              size: 34,
            ),
          ),
        ),
        DItemContent(
          children: [
            DItemTitle(
              maxLines: null,
              child: ExcludeSemantics(
                child: Text(
                  '$targetLabel assigned to ${assignment.assignee.displayName}',
                ),
              ),
            ),
            DItemDescription(
              maxLines: null,
              child: ExcludeSemantics(child: Text(subtitle.join('\n'))),
            ),
          ],
        ),
        if (onTap != null)
          const DItemActions(children: [DIcon(DIcons.pencil, size: 16)]),
      ],
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
