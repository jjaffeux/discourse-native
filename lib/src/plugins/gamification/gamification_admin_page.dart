import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'gamification_controller.dart';
import 'gamification_fields.dart';
import 'gamification_labels.dart';
import 'gamification_models.dart';
import 'gamification_navigation.dart';
import 'gamification_recalculation.dart';
import 'gamification_route.dart';
import 'gamification_score_events.dart';
import 'gamification_settings_editor.dart';

enum _AdminSection { boards, settings, events, recalculate }

class GamificationAdminPage extends StatefulWidget {
  const GamificationAdminPage({
    super.key,
    required this.site,
    required this.controller,
    this.initialBoardId,
    this.create = false,
    this.navigation,
  });
  final String site;
  final GamificationController controller;
  final int? initialBoardId;
  final bool create;
  final GamificationNavigation? navigation;
  @override
  State<GamificationAdminPage> createState() => _GamificationAdminPageState();
}

class _GamificationAdminPageState extends State<GamificationAdminPage> {
  late GamificationAdminHandle handle;
  _AdminSection _section = _AdminSection.boards;
  GamificationAdminBoard? _board;
  bool _creating = false, _routeApplied = false;
  int _selectionGeneration = 0, _reviewGeneration = 0;
  late int _revision;
  void _acquire() {
    handle = widget.controller.acquireAdmin(widget.site);
    handle.addListener(_changed);
    _revision = widget.controller.revision(widget.site);
  }

  @override
  void initState() {
    super.initState();
    _acquire();
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (_revision != widget.controller.revision(widget.site)) {
      _revision = widget.controller.revision(widget.site);
      _board = null;
      _creating = false;
    }
    if (!_routeApplied && handle.index != null) {
      _routeApplied = true;
      if (widget.create) {
        _creating = true;
      } else if (widget.initialBoardId != null) {
        unawaited(_openBoard(widget.initialBoardId!));
      }
    }
    setState(() {});
  }

  Future<void> _openBoard(int id) async {
    final selection = ++_selectionGeneration;
    final value = await handle.readBoard(id);
    if (mounted && selection == _selectionGeneration && value != null) {
      setState(() {
        _board = value;
        _creating = false;
      });
    }
  }

  @override
  void didUpdateWidget(GamificationAdminPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site != widget.site ||
        oldWidget.controller != widget.controller ||
        oldWidget.initialBoardId != widget.initialBoardId ||
        oldWidget.create != widget.create) {
      oldWidget.controller.removeListener(_changed);
      handle.removeListener(_changed);
      handle.release();
      _board = null;
      _creating = false;
      _routeApplied = false;
      _selectionGeneration++;
      _acquire();
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    handle.removeListener(_changed);
    handle.release();
    super.dispose();
  }

  String _label(_AdminSection section) => switch (section) {
    _AdminSection.boards => context.l10n.gamificationBoards,
    _AdminSection.settings => context.l10n.gamificationSettings,
    _AdminSection.events => context.l10n.gamificationEvents,
    _AdminSection.recalculate => context.l10n.gamificationRecalculate,
  };
  @override
  Widget build(BuildContext context) => DPageSurface.headed(
    title: Text(context.l10n.gamificationAdminTitle),
    controls: Wrap(
      spacing: DSpacing.sm,
      runSpacing: DSpacing.sm,
      children: [
        DSelect<_AdminSection>.controlled(
          value: _section,
          semanticLabel: context.l10n.gamificationManage,
          entries: [
            for (final section in _AdminSection.values)
              DSelectOption(
                value: section,
                label: _label(section),
                child: Text(_label(section)),
              ),
          ],
          onChanged: (section) {
            if (section != null) setState(() => _section = section);
          },
        ),
        DButton(
          label: Text(context.l10n.gamificationRefresh),
          onPressed: handle.loading || handle.busy
              ? null
              : () => unawaited(handle.refresh()),
        ),
      ],
    ),
    bodyBuilder: (context, header) => CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: header.spacer),
        SliverPadding(
          padding: const EdgeInsets.all(DSpacing.lg),
          sliver: SliverToBoxAdapter(
            child: DTouchFields(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DSpacing.md,
                children: [
                  if (!handle.canManage)
                    gameNotice(context.l10n.gamificationAdminOnly)
                  else ...[
                    if (handle.loading) const Center(child: DSpinner()),
                    if (handle.error != null)
                      gameNotice(gameError(handle.error!)),
                    if (handle.mutation.error != null)
                      gameNotice(gameError(handle.mutation.error!)),
                    if (handle.mutation.status ==
                        GamificationMutationStatus.unknown) ...[
                      gameNotice(context.l10n.gamificationUnknownWrite),
                      DButton(
                        label: Text(context.l10n.gamificationReadBack),
                        onPressed: () async {
                          await handle.reviewUncertainWrite();
                          if (mounted) setState(() => _reviewGeneration++);
                        },
                      ),
                    ],
                    if (handle.settings?.enabled == false &&
                        _section != _AdminSection.settings)
                      gameNotice(context.l10n.gamificationDisabledAdmin)
                    else
                      KeyedSubtree(
                        key: ValueKey((
                          widget.site,
                          _revision,
                          _section,
                          _reviewGeneration,
                        )),
                        child: switch (_section) {
                          _AdminSection.settings =>
                            handle.settings == null
                                ? const SizedBox.shrink()
                                : GamificationSettingsEditor(
                                    handle: handle,
                                    settings: handle.settings!,
                                  ),
                          _AdminSection.events => GamificationScoreEvents(
                            handle: handle,
                          ),
                          _AdminSection.recalculate =>
                            GamificationRecalculation(handle: handle),
                          _AdminSection.boards => _boards(context),
                        },
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _boards(BuildContext context) {
    final index = handle.index;
    if (index == null) return const SizedBox.shrink();
    if (_creating || _board != null) {
      return GamificationBoardEditor(
        key: ValueKey(_board?.board.id ?? 0),
        handle: handle,
        board: _board,
        onFinished: () {
          if (mounted) {
            setState(() {
              _board = null;
              _creating = false;
            });
          }
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.md,
      children: [
        DButton(
          label: Text(context.l10n.gamificationNewBoard),
          onPressed: handle.mayMutate
              ? () => setState(() => _creating = true)
              : null,
        ),
        if (index.boards.isEmpty) gameNotice(context.l10n.gamificationNoBoards),
        for (final board in index.boards)
          DCard(
            children: [
              DCardHeader(
                title: DCardTitle(child: Text(board.board.name)),
                description: board.creator == null
                    ? null
                    : DCardDescription(child: Text(board.creator!.username)),
              ),
              DCardFooter(
                child: Wrap(
                  spacing: DSpacing.sm,
                  children: [
                    if (widget.navigation != null)
                      DButton(
                        label: Text(context.l10n.gamificationView),
                        onPressed: () => widget.navigation!.open(
                          GamificationRoute(boardId: board.board.id),
                        ),
                      ),
                    DButton(
                      label: Text(context.l10n.gamificationEdit),
                      onPressed: handle.mayMutate
                          ? () => unawaited(_openBoard(board.board.id))
                          : null,
                    ),
                    DButton(
                      label: Text(context.l10n.gamificationDelete),
                      onPressed: handle.mayMutate
                          ? () => unawaited(_delete(board))
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _delete(GamificationAdminBoard board) async {
    final lease = widget.controller.requests.capture(widget.site),
        revision = widget.controller.revision(widget.site);
    final result = await showDDialog<bool>(
      context: context,
      builder: (context, dialog) => DDialogContent(
        children: [
          Text(board.board.name),
          Text(context.l10n.gamificationDeleteConfirm),
          DDialogFooter(
            children: [
              DButton(
                label: Text(context.l10n.gamificationCancel),
                onPressed: () => dialog.close(false),
              ),
              DButton(
                label: Text(context.l10n.gamificationDelete),
                onPressed: () => dialog.close(true),
              ),
            ],
          ),
        ],
      ),
    );
    if (result == true &&
        mounted &&
        widget.controller.current(widget.site, lease, revision, admin: true)) {
      await handle.deleteBoard(board.board.id);
    }
  }
}

class GamificationBoardEditor extends StatefulWidget {
  const GamificationBoardEditor({
    super.key,
    required this.handle,
    this.board,
    required this.onFinished,
  });
  final GamificationAdminHandle handle;
  final GamificationAdminBoard? board;
  final VoidCallback onFinished;
  @override
  State<GamificationBoardEditor> createState() =>
      _GamificationBoardEditorState();
}

class _GamificationBoardEditorState extends State<GamificationBoardEditor> {
  late final _viewLease = widget.handle.owner.requests.capture(
    widget.handle.site,
  );
  late final _viewRevision = widget.handle.owner.revision(widget.handle.site);
  bool get _viewCurrent =>
      widget.handle.canManage &&
      widget.handle.owner.current(
        widget.handle.site,
        _viewLease,
        _viewRevision,
        admin: true,
      );

  late final _name = TextEditingController(
    text: (widget.board?.draft ?? widget.handle.pendingCreatedDraft)?.name,
  );
  late final _weights = {
    for (final rule in GamificationRule.values)
      rule: TextEditingController(
        text:
            (widget.board?.draft ?? widget.handle.pendingCreatedDraft)
                ?.scoreOverrides[rule]
                ?.toString() ??
            '',
      ),
  };
  late DCalendarDate? _from =
          (widget.board?.draft ?? widget.handle.pendingCreatedDraft)?.fromDate,
      _to = (widget.board?.draft ?? widget.handle.pendingCreatedDraft)?.toDate;
  late GamificationPeriod _period =
      (widget.board?.draft ?? widget.handle.pendingCreatedDraft)
          ?.defaultPeriod ??
      GamificationPeriod.allTime;
  late bool _disabled =
      (widget.board?.draft ?? widget.handle.pendingCreatedDraft)
          ?.periodFilterDisabled ??
      false;
  late Set<int> _visible =
          (widget.board?.draft ?? widget.handle.pendingCreatedDraft)
              ?.visibleToGroupIds ??
          {},
      _included =
          (widget.board?.draft ?? widget.handle.pendingCreatedDraft)
              ?.includedGroupIds ??
          {},
      _excluded =
          (widget.board?.draft ?? widget.handle.pendingCreatedDraft)
              ?.excludedGroupIds ??
          {},
      _categories =
          (widget.board?.draft ?? widget.handle.pendingCreatedDraft)?.categoryIds ??
          {};
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    for (final field in _weights.values) {
      field.dispose();
    }
    super.dispose();
  }

  Widget _groups(
    String label,
    Set<int> value,
    ValueChanged<Set<int>> changed,
  ) => DMultiSelect<int>.controlled(
    label: Text(label),
    semanticLabel: label,
    value: value.toList(),
    isExpanded: true,
    enabled: widget.handle.mayMutate,
    entries: [
      for (final group in widget.handle.index?.groups ?? <GamificationGroup>[])
        DSelectOption(
          value: group.id,
          label: group.displayName ?? group.name,
          child: Text(group.displayName ?? group.name),
        ),
    ],
    onChanged: (ids) => setState(() => changed(ids.toSet())),
  );
  @override
  Widget build(BuildContext context) {
    if (!_viewCurrent) return gameNotice(context.l10n.gamificationAdminOnly);

    final enabled = widget.handle.mayMutate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.md,
      children: [
        Text(
          widget.board == null
              ? context.l10n.gamificationNewBoard
              : context.l10n.gamificationEdit,
        ),
        if (widget.handle.createdBoardId != null)
          gameNotice(context.l10n.gamificationPartialCreate),
        DInput(
          controller: _name,
          labelText: context.l10n.gamificationName,
          enabled: enabled,
        ),
        Wrap(
          spacing: DSpacing.md,
          runSpacing: DSpacing.md,
          children: [
            DDatePicker.controlled(
              value: _from,
              label: context.l10n.gamificationFromDate,
              enabled: enabled,
              onChanged: (date) => setState(() => _from = date),
            ),
            DDatePicker.controlled(
              value: _to,
              label: context.l10n.gamificationToDate,
              enabled: enabled,
              onChanged: (date) => setState(() => _to = date),
            ),
          ],
        ),
        DSelect<GamificationPeriod>.controlled(
          value: _period,
          enabled: enabled,
          semanticLabel: context.l10n.gamificationDefaultPeriod,
          entries: [
            for (final p in GamificationPeriod.values)
              DSelectOption(
                value: p,
                label: gamePeriodLabel(context, p),
                child: Text(gamePeriodLabel(context, p)),
              ),
          ],
          onChanged: (p) {
            if (p != null) setState(() => _period = p);
          },
        ),
        DToggle(
          pressed: _disabled,
          enabled: enabled,
          onPressedChanged: (v) => setState(() => _disabled = v),
          child: Text(context.l10n.gamificationDisablePeriod),
        ),
        Text(context.l10n.gamificationScopeHelp),
        _groups(
          context.l10n.gamificationVisibleGroups,
          _visible,
          (v) => _visible = v,
        ),
        _groups(
          context.l10n.gamificationIncludedGroups,
          _included,
          (v) => _included = v,
        ),
        _groups(
          context.l10n.gamificationExcludedGroups,
          _excluded,
          (v) => _excluded = v,
        ),
        GamificationCategories(
          handle: widget.handle,
          value: _categories,
          enabled: enabled,
          onChanged: (v) => setState(() => _categories = v),
        ),
        Text(context.l10n.gamificationCategoryScopeHelp),
        Text(context.l10n.gamificationOverrides),
        Text(context.l10n.gamificationInherit),
        for (final rule in GamificationRule.values)
          DInput(
            controller: _weights[rule],
            labelText: gameRuleLabel(context, rule),
            helperText: gameRuleHelp(context, rule),
            keyboardType: TextInputType.number,
            enabled: enabled,
          ),
        if (_error != null) gameNotice(_error!),
        Wrap(
          spacing: DSpacing.sm,
          children: [
            DButton(
              label: Text(context.l10n.gamificationSave),
              onPressed: enabled ? _save : null,
            ),
            DButton(
              label: Text(context.l10n.gamificationCancel),
              onPressed:
                  widget.handle.busy ||
                      widget.handle.mutation.status ==
                          GamificationMutationStatus.unknown
                  ? null
                  : () async {
                      await widget.handle.finishCreateLater();
                      if (mounted) widget.onFinished();
                    },
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_viewCurrent) return;
    final overrides = <GamificationRule, int>{};
    for (final e in _weights.entries) {
      if (e.value.text.trim().isEmpty) continue;
      final parsed = int.tryParse(e.value.text.trim());
      if (parsed == null || parsed < 0) {
        setState(() => _error = context.l10n.gamificationInvalid);
        return;
      }
      overrides[e.key] = parsed;
    }
    final draft = GamificationBoardDraft(
      name: _name.text,
      fromDate: _from,
      toDate: _to,
      defaultPeriod: _period,
      periodFilterDisabled: _disabled,
      visibleToGroupIds: _visible,
      includedGroupIds: _included,
      excludedGroupIds: _excluded,
      categoryIds: _categories,
      scoreOverrides: overrides,
    );
    if (!draft.valid) {
      setState(() => _error = context.l10n.gamificationInvalid);
      return;
    }
    setState(() => _error = null);
    final result = widget.board == null
        ? await widget.handle.createAndConfigure(draft)
        : await widget.handle.saveBoard(widget.board!.board.id, draft);
    if (mounted && result.status == GamificationMutationStatus.saved) {
      widget.onFinished();
    }
  }
}
