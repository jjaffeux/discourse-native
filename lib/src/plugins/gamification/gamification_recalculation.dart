import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'gamification_controller.dart';
import 'gamification_fields.dart';
import 'gamification_models.dart';

class GamificationRecalculation extends StatefulWidget {
  const GamificationRecalculation({super.key, required this.handle});
  final GamificationAdminHandle handle;
  @override
  State<GamificationRecalculation> createState() =>
      _GamificationRecalculationState();
}

class _GamificationRecalculationState extends State<GamificationRecalculation> {
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

  RecalculationPreset _preset = RecalculationPreset.tenDays;
  DCalendarDate? _custom;
  String? _error;
  String _label(RecalculationPreset p) => switch (p) {
    RecalculationPreset.tenDays => context.l10n.gamificationTenDays,
    RecalculationPreset.thirtyDays => context.l10n.gamificationThirtyDays,
    RecalculationPreset.ninetyDays => context.l10n.gamificationNinetyDays,
    RecalculationPreset.lastYear => context.l10n.gamificationYearly,
    RecalculationPreset.allTime => context.l10n.gamificationAllTime,
    RecalculationPreset.custom => context.l10n.gamificationCustom,
  };
  @override
  Widget build(BuildContext context) {
    if (!_viewCurrent) return gameNotice(context.l10n.gamificationAdminOnly);

    final h = widget.handle;
    final today = DCalendarDate.fromDateTime(h.owner.now().toUtc());
    final from = recalculationDate(_preset, h.owner.now(), custom: _custom);
    final waiting =
        h.recalculation is RecalculationQueued ||
        h.recalculation is RecalculationSubmitting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.md,
      children: [
        Text(context.l10n.gamificationRecalculateHelp),
        Text(
          context.l10n.gamificationRemaining(
            h.index?.recalculationsRemaining ?? 0,
          ),
        ),
        DSelect<RecalculationPreset>.controlled(
          value: _preset,
          semanticLabel: context.l10n.gamificationPreset,
          entries: [
            for (final p in RecalculationPreset.values)
              DSelectOption(value: p, label: _label(p), child: Text(_label(p))),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _preset = v);
          },
        ),
        if (_preset == RecalculationPreset.custom)
          DDatePicker.controlled(
            value: _custom,
            today: today,
            label: context.l10n.gamificationFromDate,
            disabled: (date) => date.isAfter(today),
            onChanged: (v) => setState(() => _custom = v),
          ),
        Text('${context.l10n.gamificationFromDate}: $from'),
        gameNotice(switch (h.recalculation) {
          RecalculationSubmitting() ||
          RecalculationQueued() => context.l10n.gamificationQueued,
          RecalculationObserved() => context.l10n.gamificationObserved,
          RecalculationUnknown() => context.l10n.gamificationCompletionUnknown,
          RecalculationFailed() => context.l10n.gamificationRecalcFailed,
          _ => context.l10n.gamificationRecalcIdle,
        }),
        if (_error != null) gameNotice(_error!),
        DButton(
          label: Text(context.l10n.gamificationRecalculate),
          onPressed:
              h.mayMutate &&
                  !waiting &&
                  (h.index?.recalculationsRemaining ?? 0) > 0
              ? () => _submit(from, today)
              : null,
        ),
      ],
    );
  }

  Future<void> _submit(DCalendarDate from, DCalendarDate today) async {
    if (!_viewCurrent) return;
    if ((_preset == RecalculationPreset.custom && _custom == null) ||
        from.isAfter(today)) {
      setState(() => _error = context.l10n.gamificationInvalidDate);
      return;
    }
    final h = widget.handle,
        lease = widget.handle.owner.requests.capture(widget.handle.site),
        revision = widget.handle.owner.revision(widget.handle.site);
    final confirmed = await showDDialog<bool>(
      context: context,
      builder: (context, dialog) => DDialogContent(
        children: [
          Text(context.l10n.gamificationRecalculateConfirm),
          Text('$from'),
          DDialogFooter(
            children: [
              DButton(
                label: Text(context.l10n.gamificationCancel),
                onPressed: () => dialog.close(false),
              ),
              DButton(
                label: Text(context.l10n.gamificationRecalculate),
                onPressed: () => dialog.close(true),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed == true &&
        mounted &&
        h.owner.current(h.site, lease, revision, admin: true)) {
      await h.recalculate(from);
    }
  }
}
