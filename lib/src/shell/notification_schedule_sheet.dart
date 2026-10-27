import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/notification_schedule.dart';
import '../models/user_preferences.dart';
import '../theme/d_icons.dart';
import 'shell_controller.dart';
import 'shell_sheet.dart';

String notificationScheduleSummary(
  BuildContext context,
  NotificationSchedule? schedule,
) {
  if (schedule == null || !schedule.enabled) {
    return context.l10n.notificationScheduleNotSet;
  }
  final days = schedule.activeDays;
  final label = listEquals(days, [0, 1, 2, 3, 4])
      ? context.l10n.notificationScheduleWeekdays
      : days.length == 7
      ? context.l10n.everyDay
      : context.l10n.notificationScheduleCustomDays;
  final windows = days.map((i) => schedule.days[i]).toSet();
  if (windows.length != 1) return label;
  final window = windows.single;
  return '$label · ${_time(context, window.start)}–${_time(context, window.end)}';
}

String _time(BuildContext context, int minutes) => minutes == 1440
    ? context.l10n.notificationScheduleMidnight
    : DateFormat.Hm(
        context.l10n.localeName,
      ).format(DateTime(2026, 1, 5, minutes ~/ 60, minutes % 60));

Future<void> showNotificationScheduleSheet({
  required BuildContext context,
  required String siteUrl,
  required ShellController controller,
  required bool Function() ownsAccount,
}) async {
  var saving = false;
  NotificationSchedule? attempted;
  await showShellSheet<bool>(
    context: context,
    title: context.l10n.notificationSchedule,
    nested: true,
    dialogOnDesktop: true,
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
    desktopDialogConstraints: const BoxConstraints(
      maxWidth: 420,
      maxHeight: 640,
    ),
    canDismiss: () => !saving || !ownsAccount(),
    builder: (context) => _NotificationScheduleEditor(
      siteUrl: siteUrl,
      controller: controller,
      ownsAccount: ownsAccount,
      onSaving: (value) => saving = value,
      onAttempt: (value) => attempted = value,
    ),
  );
  // Cancel also discards a failed save's shared draft, without retiring an edit
  // that a different preferences view made after this one.
  if (!ownsAccount() || attempted == null) return;
  final preferences = controller.preferences;
  final state = preferences.stateFor(siteUrl);
  if (state?.draft?.notificationSchedule == attempted &&
      state?.confirmed?.notificationSchedule != attempted) {
    preferences.edit(
      siteUrl,
      PreferenceSection.notificationSchedule,
      (draft) => draft.copyWith(
        notificationSchedule: state?.confirmed?.notificationSchedule,
      ),
    );
  }
}

enum _Days {
  weekdays,
  everyDay,
  custom;

  String get label => switch (this) {
    weekdays => appL10n.notificationScheduleWeekdays,
    everyDay => appL10n.everyDay,
    custom => appL10n.notificationScheduleCustomDays,
  };
}

class _NotificationScheduleEditor extends StatefulWidget {
  const _NotificationScheduleEditor({
    required this.siteUrl,
    required this.controller,
    required this.ownsAccount,
    required this.onSaving,
    required this.onAttempt,
  });
  final String siteUrl;
  final ShellController controller;
  final bool Function() ownsAccount;
  final ValueChanged<bool> onSaving;
  final ValueChanged<NotificationSchedule> onAttempt;
  @override
  State<_NotificationScheduleEditor> createState() =>
      _NotificationScheduleEditorState();
}

class _NotificationScheduleEditorState
    extends State<_NotificationScheduleEditor> {
  NotificationSchedule? _draft;
  String _timezone = 'UTC';
  _Days _mode = _Days.weekdays;
  bool _loading = true;
  bool _saving = false;
  bool _disabling = false;
  String? _error;
  bool get _canAct => mounted && widget.ownsAccount() && !_loading && !_saving;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool refresh = false}) async {
    if (!widget.ownsAccount()) return;
    final instance = widget.controller.instanceFor(widget.siteUrl);
    if (instance == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await widget.controller.preferences.load(instance, refresh: refresh);
    if (!mounted || !widget.ownsAccount()) return;
    final state = widget.controller.preferences.stateFor(widget.siteUrl);
    final confirmed = state?.confirmed;
    setState(() {
      _loading = false;
      _error = state?.error;
      if (confirmed == null) return;
      _timezone = confirmed.timezone.isNotEmpty ? confirmed.timezone : 'UTC';
      _draft = confirmed.notificationSchedule ?? NotificationSchedule.initial();
      final days = _draft!.activeDays;
      _mode = listEquals(days, [0, 1, 2, 3, 4])
          ? _Days.weekdays
          : days.length == 7
          ? _Days.everyDay
          : _Days.custom;
    });
  }

  int? _common(bool start) {
    final draft = _draft!;
    final values = draft.activeDays
        .map((i) => start ? draft.days[i].start : draft.days[i].end)
        .toSet();
    return values.length == 1 ? values.single : null;
  }

  void _edit(NotificationSchedule value) {
    if (!_canAct) return;
    setState(() {
      _draft = value;
      _error = null;
    });
  }

  void _setDays(List<int> selected) {
    if (!_canAct) return;
    final start = _common(true) ?? 540, end = _common(false) ?? 1080;
    final days = _draft!.days.toList();
    for (var i = 0; i < 7; i++) {
      if (!selected.contains(i)) {
        days[i] = (start: -1, end: -1);
      } else if (days[i].start < 0) {
        days[i] = (start: start, end: end);
      }
    }
    _edit(_draft!.copyWith(days: days));
  }

  String? get _validation {
    final draft = _draft;
    if (draft == null) return null;
    if (draft.activeDays.isEmpty) {
      return context.l10n.notificationScheduleChooseDay;
    }
    if (draft.activeDays.any((i) => draft.days[i].end <= draft.days[i].start)) {
      return context.l10n.notificationScheduleEndAfterStart;
    }
    return null;
  }

  Future<void> _save({bool enabled = true}) async {
    if (!_canAct || (enabled && _validation != null)) return;
    final instance = widget.controller.instanceFor(widget.siteUrl);
    if (instance == null) return;
    final preferences = widget.controller.preferences;
    if (preferences.stateFor(widget.siteUrl)?.confirmed?.canEdit != true) {
      return;
    }
    final confirmed = preferences
        .stateFor(widget.siteUrl)
        ?.confirmed
        ?.notificationSchedule;
    if (!enabled && confirmed?.enabled != true) return;
    // Turning off changes only the saved schedule's activation, even when the
    // editor contains unsaved changes to its days or hours.
    final value = enabled
        ? _draft!.copyWith(enabled: true)
        : confirmed!.copyWith(enabled: false);
    if (value ==
        preferences.stateFor(widget.siteUrl)?.confirmed?.notificationSchedule) {
      DDialogClose.close<bool>(context, true);
      return;
    }
    setState(() {
      _saving = true;
      _disabling = !enabled;
      _error = null;
    });
    widget.onSaving(true);
    widget.onAttempt(value);
    preferences.edit(
      widget.siteUrl,
      PreferenceSection.notificationSchedule,
      (draft) => draft.copyWith(notificationSchedule: value),
    );
    final saved = await preferences.save(
      instance,
      PreferenceSection.notificationSchedule,
    );
    if (!mounted || !widget.ownsAccount()) return;
    widget.onSaving(false);
    if (saved) {
      DDialogClose.close<bool>(context, true);
    } else {
      setState(() {
        _saving = false;
        _error = preferences.stateFor(widget.siteUrl)?.error;
      });
    }
  }

  Widget _timeField(String label, bool start, bool editable) {
    final selected = _common(start);
    final options = {
      for (
        var minute = start ? 0 : 30;
        minute <= (start ? 1410 : 1440);
        minute += 30
      )
        minute,
      ?selected,
    }.toList()..sort();
    return DField(
      children: [
        DFieldLabel(child: Text(label)),
        DSelect<int>.controlled(
          key: ValueKey(
            start ? 'notification-schedule-from' : 'notification-schedule-to',
          ),
          value: selected,
          isExpanded: true,
          filled: true,
          size: DControlSize.preference,
          enabled: editable,
          semanticLabel: label,
          valueBuilder: (context, value, _) => Text(
            value == null
                ? context.l10n.notificationScheduleVaries
                : _time(context, value),
          ),
          entries: [
            for (final value in options)
              DSelectOption(
                value: value,
                label: _time(context, value),
                child: Text(_time(context, value)),
              ),
          ],
          onChanged: (value) {
            if (!_canAct || value == null) return;
            _edit(
              _draft!.copyWith(
                days: [
                  for (final day in _draft!.days)
                    day.start < 0
                        ? day
                        : (
                            start: start ? value : day.start,
                            end: start ? day.end : value,
                          ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: DSpinner(semanticLabel: context.l10n.loading));
    }
    final draft = _draft;
    if (draft == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DFieldError(errors: [_error]),
          DButton(
            label: Text(context.l10n.retry),
            onPressed: () => unawaited(_load(refresh: true)),
          ),
        ],
      );
    }
    final permitted =
        widget.controller.preferences
            .stateFor(widget.siteUrl)
            ?.confirmed
            ?.canEdit ==
        true;
    final editable = _canAct && permitted;
    final active =
        widget.controller.preferences
            .stateFor(widget.siteUrl)
            ?.confirmed
            ?.notificationSchedule
            ?.enabled ==
        true;
    final locale = context.l10n.localeName;
    final dayLabels = [
      for (var i = 0; i < 7; i++)
        DateFormat.E(locale).format(DateTime(2026, 1, 5 + i)),
    ];
    return DTouchFields(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DField(
            children: [
              DFieldLabel(
                child: Text(context.l10n.notificationScheduleAllowOn),
              ),
              DSelect<_Days>.controlled(
                key: const ValueKey('notification-schedule-days'),
                value: _mode,
                isExpanded: true,
                filled: true,
                size: DControlSize.preference,
                enabled: editable,
                semanticLabel: context.l10n.notificationScheduleAllowOn,
                entries: [
                  for (final mode in _Days.values)
                    DSelectOption(
                      value: mode,
                      label: mode.label,
                      child: Text(mode.label),
                    ),
                ],
                onChanged: (mode) {
                  if (!_canAct || mode == null) return;
                  setState(() => _mode = mode);
                  if (mode != _Days.custom) {
                    _setDays([
                      for (var i = 0; i < (mode == _Days.weekdays ? 5 : 7); i++)
                        i,
                    ]);
                  }
                },
              ),
            ],
          ),
          if (_mode == _Days.custom) ...[
            const SizedBox(height: 12),
            DToggleGroup<int>(
              multiple: true,
              values: draft.activeDays,
              wrap: true,
              scrollable: false,
              variant: DToggleVariant.outline,
              spacing: DSpacing.controlGap,
              semanticLabel: context.l10n.notificationScheduleCustomDays,
              items: [
                for (var i = 0; i < 7; i++)
                  DToggleGroupItem(
                    value: i,
                    semanticLabel: DateFormat.EEEE(
                      locale,
                    ).format(DateTime(2026, 1, 5 + i)),
                    child: Text(dayLabels[i]),
                  ),
              ],
              onChanged: editable ? _setDays : null,
            ),
          ],
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final fields = [
                _timeField(
                  context.l10n.notificationScheduleFrom,
                  true,
                  editable,
                ),
                _timeField(context.l10n.to, false, editable),
              ];
              return MediaQuery.textScalerOf(context).scale(14) > 21 ||
                      constraints.maxWidth < 260
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: fields,
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 12,
                      children: [
                        for (final field in fields) Expanded(child: field),
                      ],
                    );
            },
          ),
          const SizedBox(height: 18),
          Row(
            spacing: 7,
            children: [
              const DIcon(DIcons.globe, size: 14),
              DText(
                context.l10n.notificationScheduleTimeZone,
                variant: DTextVariant.muted,
              ),
              Expanded(child: Text(_timezone, textAlign: TextAlign.end)),
            ],
          ),
          if (_error ?? _validation case final error?) ...[
            const SizedBox(height: 12),
            DFieldError(errors: [error]),
          ],
          const SizedBox(height: 18),
          const DSeparator(),
          const SizedBox(height: 12),
          Row(
            spacing: DSpacing.controlGap,
            children: [
              DButton(
                label: Text(context.l10n.cancel),
                variant: DButtonVariant.ghost,
                size: DButtonSize.action,
                onPressed: _saving
                    ? null
                    : () => DDialogClose.close<bool>(context),
              ),
              Expanded(
                child: DButton(
                  key: const ValueKey('notification-schedule-save'),
                  label: Text(context.l10n.notificationScheduleSave),
                  size: DButtonSize.action,
                  loading: _saving && !_disabling,
                  shape: DButtonShape.pill,
                  onPressed: _canAct && permitted && _validation == null
                      ? () => unawaited(_save())
                      : null,
                ),
              ),
            ],
          ),
          if (active) ...[
            const SizedBox(height: DSpacing.controlGap),
            DButton(
              key: const ValueKey('notification-schedule-turn-off'),
              label: Text(context.l10n.notificationScheduleTurnOff),
              variant: DButtonVariant.ghost,
              size: DButtonSize.action,
              loading: _saving && _disabling,
              onPressed: editable
                  ? () => unawaited(_save(enabled: false))
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}
