import 'dart:async';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'gamification_controller.dart';
import 'gamification_fields.dart';
import 'gamification_models.dart';

class GamificationScoreEvents extends StatefulWidget {
  const GamificationScoreEvents({super.key, required this.handle});
  final GamificationAdminHandle handle;
  @override
  State<GamificationScoreEvents> createState() =>
      _GamificationScoreEventsState();
}

class _GamificationScoreEventsState extends State<GamificationScoreEvents> {
  final _id = TextEditingController(), _user = TextEditingController();
  DCalendarDate? _date;
  GamificationScoreEvent? _editing;
  bool _creating = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(widget.handle.queryEvents(const ScoreEventQuery()));
  }

  @override
  void dispose() {
    _id.dispose();
    _user.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_creating || _editing != null) {
      return GamificationScoreEventEditor(
        key: ValueKey(_editing?.id ?? 0),
        handle: widget.handle,
        event: _editing,
        onFinished: () {
          if (mounted) {
            setState(() {
              _editing = null;
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
        DInput(
          controller: _id,
          labelText: context.l10n.gamificationEventId,
          keyboardType: TextInputType.number,
        ),
        DInput(
          controller: _user,
          labelText: context.l10n.gamificationUserId,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
        ),
        DDatePicker.controlled(
          value: _date,
          label: context.l10n.gamificationFromDate,
          onChanged: (v) => setState(() => _date = v),
        ),
        Wrap(
          spacing: DSpacing.sm,
          children: [
            DButton(
              label: Text(context.l10n.gamificationFilter),
              onPressed: _filter,
            ),
            DButton(
              label: Text(context.l10n.gamificationNewEvent),
              onPressed: widget.handle.mayMutate
                  ? () => setState(() => _creating = true)
                  : null,
            ),
          ],
        ),
        Text(context.l10n.gamificationEventLimit),
        if (_error != null) gameNotice(_error!),
        for (final event in widget.handle.events ?? <GamificationScoreEvent>[])
          DCard(
            children: [
              DCardContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DSpacing.sm,
                  children: [
                    Text(
                      '${context.l10n.gamificationEventId} ${event.id} · ${event.date}',
                    ),
                    Text(
                      '${context.l10n.gamificationUserId} ${event.userId} · ${context.l10n.gamificationPoints} ${event.points}',
                    ),
                    if (event.categoryId != null)
                      Text(
                        '${context.l10n.gamificationCategory} ${event.categoryId}',
                      ),
                    if (event.description?.isNotEmpty == true)
                      Text(event.description!),
                    DButton(
                      label: Text(context.l10n.gamificationEdit),
                      onPressed: widget.handle.mayMutate
                          ? () => setState(() => _editing = event)
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

  void _filter() {
    final id = _id.text.trim().isEmpty ? null : int.tryParse(_id.text.trim());
    final user = _user.text.trim().isEmpty
        ? null
        : int.tryParse(_user.text.trim());
    if ((_id.text.trim().isNotEmpty && (id == null || id <= 0)) ||
        (_user.text.trim().isNotEmpty && user == null)) {
      setState(() => _error = context.l10n.gamificationEventValidation);
      return;
    }
    setState(() => _error = null);
    unawaited(
      widget.handle.queryEvents(
        ScoreEventQuery(id: id, userId: user, date: _date),
      ),
    );
  }
}

class GamificationScoreEventEditor extends StatefulWidget {
  const GamificationScoreEventEditor({
    super.key,
    required this.handle,
    this.event,
    required this.onFinished,
  });
  final GamificationAdminHandle handle;
  final GamificationScoreEvent? event;
  final VoidCallback onFinished;
  @override
  State<GamificationScoreEventEditor> createState() =>
      _GamificationScoreEventEditorState();
}

class _GamificationScoreEventEditorState
    extends State<GamificationScoreEventEditor> {
  late final _user = TextEditingController(
        text: widget.event?.userId.toString(),
      ),
      _points = TextEditingController(text: widget.event?.points.toString()),
      _description = TextEditingController(text: widget.event?.description);
  late DCalendarDate _date =
      widget.event?.date ??
      DCalendarDate.fromDateTime(widget.handle.owner.now().toUtc());
  late Set<int> _category = widget.event?.categoryId == null
      ? {}
      : {widget.event!.categoryId!};
  String? _error;
  @override
  void dispose() {
    _user.dispose();
    _points.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.handle.mayMutate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.md,
      children: [
        if (widget.event != null) Text(context.l10n.gamificationEventImmutable),
        DInput(
          controller: _user,
          labelText: context.l10n.gamificationUserId,
          enabled: enabled && widget.event == null,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
        ),
        DDatePicker.controlled(
          value: _date,
          label: context.l10n.gamificationFromDate,
          enabled: enabled && widget.event == null,
          onChanged: (v) {
            if (v != null) setState(() => _date = v);
          },
        ),
        DInput(
          controller: _points,
          labelText: context.l10n.gamificationPoints,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
        ),
        DTextarea(
          controller: _description,
          labelText: context.l10n.gamificationDescription,
          enabled: enabled,
        ),
        GamificationCategories(
          handle: widget.handle,
          single: true,
          value: _category,
          enabled: enabled,
          onChanged: (v) => setState(() => _category = v),
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
              onPressed: widget.handle.busy ? null : widget.onFinished,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _save() async {
    final user = int.tryParse(_user.text.trim()),
        points = int.tryParse(_points.text.trim());
    if (user == null || points == null) {
      setState(() => _error = context.l10n.gamificationEventValidation);
      return;
    }
    final result = widget.event == null
        ? await widget.handle.createEvent(
            CreateScoreEvent(
              userId: user,
              date: _date,
              points: points,
              description: _description.text,
              categoryId: _category.firstOrNull,
            ),
          )
        : await widget.handle.editEvent(
            EditScoreEvent(
              id: widget.event!.id,
              points: points,
              description: _description.text,
              categoryId: _category.firstOrNull,
            ),
          );
    if (!mounted) return;
    if (result.status == GamificationMutationStatus.saved) {
      DToast.show(context, context.l10n.gamificationEventSaved);
      widget.onFinished();
    }
  }
}
