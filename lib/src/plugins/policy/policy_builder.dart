import 'dart:async';
import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'policy_definition.dart';
import 'policy_groups.dart';

Future<PolicyDefinition?> showPolicyBuilder(
  BuildContext context, {
  required PolicyDefinition initial,
  required Future<List<PolicyGroup>> Function() loadGroups,
  required bool Function() isCurrent,
  bool insert = false,
  required PolicyDefinition? persistedDefinition,
}) => showDSheet<PolicyDefinition>(
  context: context,
  side: context.isTouch ? DSheetSide.bottom : DSheetSide.right,
  variant: context.isTouch ? DSheetVariant.menu : DSheetVariant.standard,
  initiallyExpanded: true,
  fillAvailableHeight: true,
  builder: (context, sheet) => DSheetContent(
    side: context.isTouch ? DSheetSide.bottom : DSheetSide.right,
    variant: context.isTouch ? DSheetVariant.menu : DSheetVariant.standard,
    fillAvailableHeight: true,
    initiallyExpanded: true,
    topBottomMaxHeightFactor: context.isTouch ? .9 : null,
    scrollWholeSheet: false,
    children: [
      DSheetHeader(
        children: [
          DSheetTitle(
            child: Text(
              insert
                  ? context.l10n.policyCreate
                  : context.l10n.policyEditSettings,
            ),
          ),
        ],
      ),
      Expanded(
        child: PolicyBuilder(
          initial: initial,
          loadGroups: loadGroups,
          isCurrent: isCurrent,
          insert: insert,
          persistedDefinition: persistedDefinition,
          onClose: sheet.close,
        ),
      ),
    ],
  ),
);

class PolicyBuilder extends StatefulWidget {
  const PolicyBuilder({
    super.key,
    required this.initial,
    required this.loadGroups,
    required this.isCurrent,
    required this.onClose,
    this.insert = false,
    this.persistedDefinition,
  });
  final PolicyDefinition initial;
  final Future<List<PolicyGroup>> Function() loadGroups;
  final bool Function() isCurrent;
  final ValueChanged<PolicyDefinition?> onClose;
  final bool insert;
  final PolicyDefinition? persistedDefinition;
  @override
  State<PolicyBuilder> createState() => _PolicyBuilderState();
}

class _PolicyBuilderState extends State<PolicyBuilder> {
  late final _version = TextEditingController(text: widget.initial.version);
  late final _days = TextEditingController(
    text: widget.initial.renewal is PolicyRenewAfterDays
        ? '${(widget.initial.renewal as PolicyRenewAfterDays).days}'
        : '90',
  );
  late final _accept = TextEditingController(
    text: widget.initial.acceptLabel ?? '',
  );
  late final _revoke = TextEditingController(
    text: widget.initial.revokeLabel ?? '',
  );
  late var _audience = List<String>.of(widget.initial.audienceGroups);
  late var _renewal = widget.initial.renewal is PolicyRenewAfterDays
      ? 'days'
      : widget.initial.renewal.markup ?? 'none';
  late var _reminder = widget.initial.reminder;
  late var _private = widget.initial.privateStatistics;
  late String? _target = widget.initial.targetGroup;
  DCalendarDate? _date;
  var _dateChanged = false;
  List<PolicyGroup> _groups = const [];
  var _loading = true;
  Object? _groupError;
  String? _error;
  @override
  void initState() {
    super.initState();
    final date = DateTime.tryParse(widget.initial.renewStartDate ?? '');
    if (date != null) _date = DCalendarDate(date.year, date.month, date.day);
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _groupError = null;
    });
    try {
      final groups = await widget.loadGroups();
      if (!mounted || !widget.isCurrent()) return;
      setState(() => _groups = groups);
    } catch (error) {
      if (mounted && widget.isCurrent()) setState(() => _groupError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [_version, _days, _accept, _revoke]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    String? error;
    if (!widget.isCurrent()) {
      error = context.l10n.policySourceChanged;
    } else if ((widget.persistedDefinition?.reminder ?? PolicyReminder.none) !=
            PolicyReminder.none &&
        _reminder == PolicyReminder.none) {
      error = context.l10n.policyReminderClearNotice;
    } else if (widget.persistedDefinition?.renewal is PolicyRenewByCalendar &&
        _renewal == 'none') {
      error = context.l10n.policyRenewalClearNotice;
    } else if (_audience.isEmpty) {
      error = context.l10n.policyGroupsRequired;
    } else if (_version.text.trim().isEmpty) {
      error = context.l10n.policyVersionRequired;
    } else if (_renewal == 'days' && (int.tryParse(_days.text) ?? 0) <= 0) {
      error = context.l10n.policyPositiveDays;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final definition = PolicyDefinition(
      audienceGroups: _audience,
      version: _version.text,
      renewal: _renewal == 'days'
          ? PolicyRenewAfterDays(int.parse(_days.text))
          : PolicyCalendarInterval.values.any((v) => v.name == _renewal)
          ? PolicyRenewByCalendar(
              PolicyCalendarInterval.values.firstWhere(
                (v) => v.name == _renewal,
              ),
            )
          : const PolicyNoRenewal(),
      renewStartDate: !_dateChanged
          ? widget.initial.renewStartDate
          : _date == null
          ? null
          : '${_date!.year.toString().padLeft(4, '0')}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}',
      reminder: _reminder,
      acceptLabel: _accept.text.isEmpty ? null : _accept.text,
      revokeLabel: _revoke.text.isEmpty ? null : _revoke.text,
      targetGroup: _target,
      privateStatistics: _private,
    );
    try {
      const PolicySourceCodec().openingTag(definition);
    } on FormatException {
      setState(() => _error = context.l10n.policyInvalidAttribute);
      return;
    }
    widget.onClose(definition);
  }

  Widget _pair(Widget first, Widget second) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 16,
    children: [
      Expanded(child: first),
      Expanded(child: second),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final audience = {
      ..._audience,
      for (final group in _groups) group.name,
    }.toList()..sort();
    final targets = {
      ?_target,
      for (final group in _groups)
        if (!group.automatic) group.name,
    }.toList()..sort();
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 18,
              children: [
                if (_loading) const DSpinner(),
                if (_groupError != null)
                  DAlert(
                    title: DAlertTitle(child: Text(l.policyGroupsUnavailable)),
                    action: DAlertAction(
                      child: DButton(
                        label: Text(l.retry),
                        onPressed: _load,
                        variant: DButtonVariant.outline,
                      ),
                    ),
                  ),
                DMultiSelect<String>(
                  initialValue: _audience,
                  label: Text(l.policyGroups),
                  isExpanded: true,
                  description: Text(l.policyGroupsHelp),
                  entries: [
                    for (final name in audience)
                      DSelectItem(
                        value: name,
                        child: Text(name),
                        textValue: name,
                      ),
                  ],
                  onChanged: (values) => setState(() => _audience = values),
                ),
                DInput(
                  controller: _version,
                  labelText: l.policyVersion,
                  helperText: l.policyVersionHelp,
                ),
                _pair(
                  DSelect<String>(
                    value: _renewal,
                    label: Text(l.policyRenewal),
                    isExpanded: true,
                    entries: [
                      for (final (id, name) in [
                        ('none', l.policyNoRenewal),
                        ('days', l.policyRenewDays),
                        ('monthly', l.policyMonthly),
                        ('quarterly', l.policyQuarterly),
                        ('yearly', l.policyYearly),
                      ])
                        DSelectItem(
                          value: id,
                          child: Text(name),
                          textValue: name,
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _renewal = value);
                    },
                  ),
                  DInput(
                    controller: _days,
                    labelText: l.policyDays,
                    keyboardType: TextInputType.number,
                    enabled: _renewal == 'days',
                  ),
                ),
                _pair(
                  DDatePicker.controlled(
                    value: _date,
                    label: l.policyRenewStart,
                    onChanged: (date) => setState(() {
                      _date = date;
                      _dateChanged = true;
                    }),
                  ),
                  DSelect<PolicyReminder>(
                    value: _reminder,
                    label: Text(l.policyReminder),
                    isExpanded: true,
                    entries: [
                      for (final (value, label) in [
                        (PolicyReminder.none, l.policyNoReminder),
                        (PolicyReminder.daily, l.policyDaily),
                        (PolicyReminder.weekly, l.policyWeekly),
                      ])
                        DSelectItem(
                          value: value,
                          child: Text(label),
                          textValue: label,
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _reminder = value);
                    },
                  ),
                ),
                const DSeparator(),
                _pair(
                  DInput(
                    controller: _accept,
                    labelText: l.policyAcceptLabel,
                    hintText: l.policyAccept,
                  ),
                  DInput(
                    controller: _revoke,
                    labelText: l.policyRevokeLabel,
                    hintText: l.policyRevoke,
                  ),
                ),
                DSelect<String>(
                  value: _target ?? '',
                  label: Text(l.policyTargetGroup),
                  isExpanded: true,
                  entries: [
                    DSelectItem(
                      value: '',
                      child: Text(l.policyNoGroup),
                      textValue: l.policyNoGroup,
                    ),
                    for (final name in targets)
                      DSelectItem(
                        value: name,
                        child: Text(name),
                        textValue: name,
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _target = value == '' ? null : value),
                ),
                DFieldDescription(child: Text(l.policyTargetHelp)),
                const DSeparator(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 6,
                        children: [
                          DFieldTitle(child: Text(l.policyPrivate)),
                          DFieldDescription(child: Text(l.policyPrivateHelp)),
                        ],
                      ),
                    ),
                    DToggle(
                      pressed: _private,
                      semanticLabel: l.policyPrivate,
                      onPressedChanged: (value) =>
                          setState(() => _private = value),
                      variant: DToggleVariant.outline,
                      child: Icon(
                        _private ? Icons.lock_outline : Icons.lock_open,
                        size: 16,
                      ),
                    ),
                  ],
                ),
                if (_error != null) DFieldError(child: Text(_error!)),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(DSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 8,
            children: [
              DButton(
                label: Text(l.cancel),
                variant: DButtonVariant.outline,
                onPressed: () => widget.onClose(null),
              ),
              DButton(
                label: Text(widget.insert ? l.policyInsert : l.saveChanges),
                onPressed: _save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
