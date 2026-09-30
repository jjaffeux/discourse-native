import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../composer_sheet_layout.dart';
import 'poll_composer_editor.dart';
import 'poll_composer_parser.dart';

enum PollComposerSheetActionType { apply, remove }

@immutable
class PollComposerSheetAction {
  const PollComposerSheetAction._(this.type, this.draft);

  const PollComposerSheetAction.apply(PollComposerDraft draft)
    : this._(PollComposerSheetActionType.apply, draft);

  const PollComposerSheetAction.remove()
    : this._(PollComposerSheetActionType.remove, null);

  final PollComposerSheetActionType type;
  final PollComposerDraft? draft;
}

/// Returns an action for verified source helpers to apply; [isCurrent] rejects
/// stale or disposed composers before the sheet closes.
Future<PollComposerSheetAction?> showPollComposerSheet({
  required BuildContext context,
  required PollComposerDraft draft,
  required int maximumOptions,
  required bool isStaff,
  required bool isPublished,
  int? voterCount,
  bool Function()? isCurrent,
}) {
  final title = draft.isNew ? appL10n.addPoll : appL10n.editPoll;
  Widget editor(BuildContext context) => PollComposerSheet(
    mobileLayout: context.isTouch,
    draft: draft,
    maximumOptions: maximumOptions,
    isStaff: isStaff,
    isPublished: isPublished,
    voterCount: voterCount,
    isCurrent: isCurrent,
  );
  if (context.isTouch) {
    return showDSheet<PollComposerSheetAction>(
      context: context,
      side: DSheetSide.bottom,
      inset: true,
      fillAvailableHeight: true,
      builder: (context, sheet) => DSheetContent(
        side: DSheetSide.bottom,
        semanticLabel: title,
        showCloseButton: false,
        topBottomMaxHeightFactor: 1,
        scrollWholeSheet: false,
        children: [Expanded(child: editor(context))],
      ),
    );
  }

  return showDialog<PollComposerSheetAction>(
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
                    child: DText(
                      title,
                      variant: DTextVariant.h4,
                      headingLevel: 1,
                    ),
                  ),
                  DButton.iconOnly(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    variant: DButtonVariant.ghost,
                    tooltip: appL10n.close,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            DSeparator(color: Theme.of(dialogContext).shell.divider, space: 1),
            Flexible(
              child: SingleChildScrollView(child: editor(dialogContext)),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> confirmPublishedPollRemoval(
  BuildContext context, {
  int? voterCount,
}) async {
  final detail = voterCount == null
      ? appL10n.thisPollMayAlreadyHaveVotes
      : appL10n.thisPollHas(voterCount);
  return await showDiscourseAlertDialog<bool>(
        context: context,
        title: Text(appL10n.removePublishedPoll),
        description: Text(
          appL10n.removingItWillRemoveThePollFromThePost((detail).toString()),
        ),
        cancelLabel: Text(appL10n.cancel),
        actionLabel: Text(appL10n.removePoll),
        cancelResult: false,
        actionResult: true,
        actionVariant: DButtonVariant.destructive,
      ) ??
      false;
}

class PollComposerSheet extends StatefulWidget {
  const PollComposerSheet({
    super.key,
    required this.draft,
    required this.maximumOptions,
    required this.isStaff,
    required this.isPublished,
    this.voterCount,
    this.isCurrent,
    this.mobileLayout = false,
  });

  final PollComposerDraft draft;
  final int maximumOptions;
  final bool isStaff;
  final bool isPublished;
  final int? voterCount;
  final bool Function()? isCurrent;
  final bool mobileLayout;

  @override
  State<PollComposerSheet> createState() => _PollComposerSheetState();
}

class _PollComposerSheetState extends State<PollComposerSheet> {
  late final TextEditingController _title;
  late final TextEditingController _minimum;
  late final TextEditingController _maximum;
  late final TextEditingController _step;
  late final TextEditingController _close;
  final List<TextEditingController> _options = [];

  late ComposerPollType _type;
  late PollResultMode _results;
  late bool _publicVoters;
  late bool _automaticClose;
  String? _error;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    _title = TextEditingController(text: draft.title);
    _minimum = TextEditingController(text: '${draft.minimum}');
    _maximum = TextEditingController(text: '${draft.maximum}');
    _step = TextEditingController(text: '${draft.step}');
    _close = TextEditingController(text: draft.close);
    _options.addAll(
      draft.options.map((option) => TextEditingController(text: option)),
    );
    _type = draft.type;
    _results = draft.results;
    _publicVoters = draft.publicVoters;
    _automaticClose = draft.close.isNotEmpty;
  }

  @override
  void dispose() {
    _title.dispose();
    _minimum.dispose();
    _maximum.dispose();
    _step.dispose();
    _close.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  bool get _isNumber => _type == ComposerPollType.number;
  bool get _isMultiple => _type == ComposerPollType.multiple;
  bool get _isRanked => _type == ComposerPollType.rankedChoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error == null
        ? null
        : Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              _error!,
              key: const ValueKey('poll-sheet-error'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          );
    final fields = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.mobileLayout ? DSpacing.lg : DSpacing.xl,
        vertical: widget.mobileLayout ? DSpacing.sm : DSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DInput(
            controller: _title,
            labelText: context.l10n.titleOptional,
            hintText: context.l10n.lunchChoice,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          _typeField(),
          if (_isRanked) ...[
            const SizedBox(height: 6),
            Text(
              context
                  .l10n
                  .rankedChoicePollsKeepTheirTypeVotingRemainsAvailableOnThe,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (_isNumber) _numberFields() else _optionFields(),
          const SizedBox(height: 20),
          _resultsField(),
          const SizedBox(height: 8),
          DSwitchTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            title: DLabel(child: Text(context.l10n.publicVoterIdentities)),
            subtitle: Text(
              context.l10n.theVoterListItselfIsShownOnTheWebInThis,
            ),
            value: _publicVoters,
            onChanged: (value) => setState(() => _publicVoters = value),
          ),
          DSwitchTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            title: DLabel(child: Text(context.l10n.automaticClose)),
            value: _automaticClose,
            onChanged: (value) => setState(() => _automaticClose = value),
          ),
          if (_automaticClose)
            DInput(
              controller: _close,
              labelText: context.l10n.closeDateAndTime,
              hintText: '2026-08-30T18:00:00Z',
              helperText: context.l10n.iSO8601InThisDeviceSTimeZoneUnlessOneIs,
              keyboardType: TextInputType.datetime,
            ),
          if (!widget.mobileLayout && error != null) ...[
            const SizedBox(height: DSpacing.lg),
            error,
          ],
          if (!widget.mobileLayout) ...[const SizedBox(height: 24), _actions()],
        ],
      ),
    );
    if (!widget.mobileLayout) return fields;
    return ComposerSheetLayout(
      title: widget.draft.isNew ? context.l10n.addPoll : context.l10n.editPoll,
      onApply: _apply,
      onRemove: widget.draft.isNew ? null : () => unawaited(_remove()),
      removeLabel: context.l10n.removeLocaldatecomposersheet,
      error: error,
      child: fields,
    );
  }

  Widget _typeField() {
    final choices = <ComposerPollType>[
      ComposerPollType.regular,
      ComposerPollType.multiple,
      ComposerPollType.number,
      if (_isRanked) ComposerPollType.rankedChoice,
    ];
    return DSelect<ComposerPollType>.controlled(
      isExpanded: true,
      value: _type,
      label: Text(appL10n.pollType),
      entries: [
        for (final type in choices)
          DSelectOption(
            value: type,
            label: _typeLabel(type),
            child: Text(_typeLabel(type)),
          ),
      ],
      onChanged: _isRanked
          ? null
          : (type) {
              if (type == null) return;
              setState(() {
                _type = type;
                _error = null;
              });
            },
      initialValue: _type,
      enabled: !_isRanked,
    );
  }

  static String _typeLabel(ComposerPollType type) => switch (type) {
    ComposerPollType.regular => appL10n.singleChoice,
    ComposerPollType.multiple => appL10n.multipleChoice,
    ComposerPollType.number => appL10n.number,
    ComposerPollType.rankedChoice => appL10n.rankedChoice,
    ComposerPollType.unknown => appL10n.unknown,
  };

  Widget _optionFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(appL10n.options, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      for (var index = 0; index < _options.length; index++)
        Padding(
          key: ObjectKey(_options[index]),
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: DInput(
                  controller: _options[index],
                  labelText: appL10n.optionPollcomposersheet(
                    (index + 1).toString(),
                  ),
                ),
              ),
              DButton.iconOnly(
                onPressed: index == 0 ? null : () => _moveOption(index, -1),
                variant: DButtonVariant.ghost,
                tooltip: appL10n.moveOptionUp,
                icon: const Icon(Icons.arrow_upward),
              ),
              DButton.iconOnly(
                onPressed: index == _options.length - 1
                    ? null
                    : () => _moveOption(index, 1),
                variant: DButtonVariant.ghost,
                tooltip: appL10n.moveOptionDown,
                icon: const Icon(Icons.arrow_downward),
              ),
              DButton.iconOnly(
                onPressed: () => _removeOption(index),
                variant: DButtonVariant.ghost,
                tooltip: appL10n.removeOption,
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: DButton(
          label: Text(appL10n.addOption),
          onPressed: _options.length >= widget.maximumOptions
              ? null
              : _addOption,
          icon: const Icon(Icons.add),
        ),
      ),
      if (_isMultiple) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _integerField(_minimum, appL10n.minimumChoices)),
            const SizedBox(width: 12),
            Expanded(child: _integerField(_maximum, appL10n.maximumChoices)),
          ],
        ),
      ],
    ],
  );

  Widget _numberFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(appL10n.numberRange, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(child: _integerField(_minimum, appL10n.minimum)),
          const SizedBox(width: 12),
          Expanded(child: _integerField(_maximum, appL10n.maximum)),
          const SizedBox(width: 12),
          Expanded(child: _integerField(_step, appL10n.step)),
        ],
      ),
      const SizedBox(height: 8),
      Text(appL10n.optionsAreGeneratedInclusivelyFromThisRange),
    ],
  );

  Widget _integerField(TextEditingController controller, String label) =>
      DInput(
        controller: controller,
        labelText: label,
        keyboardType: TextInputType.number,
      );

  Widget _resultsField() {
    final choices = <PollResultMode>[
      PollResultMode.always,
      PollResultMode.onVote,
      PollResultMode.onClose,
      if (widget.isStaff || _results == PollResultMode.staffOnly)
        PollResultMode.staffOnly,
      if (_results == PollResultMode.unknown) PollResultMode.unknown,
    ];
    return DSelect<PollResultMode>.controlled(
      isExpanded: true,
      value: _results,
      label: Text(appL10n.showResults),
      entries: [
        for (final result in choices)
          DSelectOption(
            value: result,
            enabled: result != PollResultMode.unknown,
            label: result == PollResultMode.unknown
                ? appL10n.preserve((widget.draft.resultsSource).toString())
                : result.label,
            child: Text(
              result == PollResultMode.unknown
                  ? appL10n.preserve((widget.draft.resultsSource).toString())
                  : result.label,
            ),
          ),
      ],
      onChanged: (result) {
        if (result == null || result == PollResultMode.unknown) return;
        setState(() {
          _results = result;
          _error = null;
        });
      },
      initialValue: _results,
    );
  }

  Widget _actions() => Wrap(
    alignment: WrapAlignment.end,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: DSpacing.controlGap,
    runSpacing: 8,
    children: [
      if (!widget.draft.isNew) ...[
        DButton(
          label: Text(appL10n.removeLocaldatecomposersheet),
          onPressed: () => unawaited(_remove()),
          variant: DButtonVariant.destructive,
        ),
      ],
      DButton(
        label: Text(appL10n.cancel),
        onPressed: () => Navigator.of(context).pop(),
      ),
      DButton(
        label: Text(appL10n.apply),
        onPressed: _apply,
        variant: DButtonVariant.primary,
      ),
    ],
  );

  void _addOption() {
    if (_options.length >= widget.maximumOptions) return;
    setState(() => _options.add(TextEditingController()));
  }

  void _removeOption(int index) {
    final removed = _options.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  void _moveOption(int index, int delta) {
    final next = index + delta;
    if (next < 0 || next >= _options.length) return;
    setState(() {
      final option = _options.removeAt(index);
      _options.insert(next, option);
    });
  }

  void _apply() {
    if (!_checkCurrent()) return;
    final close = _close.text;
    final preservingExistingClose =
        !widget.draft.isNew &&
        widget.draft.sourceBlock?.attribute('close') != null &&
        close == widget.draft.close;
    if (_automaticClose && close.trim().isEmpty && !preservingExistingClose) {
      setState(() => _error = appL10n.automaticCloseNeedsADateAndTime);
      return;
    }
    final minimum = int.tryParse(_minimum.text.trim());
    final maximum = int.tryParse(_maximum.text.trim());
    final step = int.tryParse(_step.text.trim());
    if ((_isMultiple || _isNumber) && (minimum == null || maximum == null) ||
        _isNumber && step == null) {
      setState(() => _error = appL10n.minimumMaximumAndStepMustBeWholeNumbers);
      return;
    }

    final draft = widget.draft.copyWith(
      title: _title.text,
      type: _type,
      options: _options.map((option) => option.text).toList(),
      minimum: minimum ?? widget.draft.minimum,
      maximum: maximum ?? widget.draft.maximum,
      step: step ?? widget.draft.step,
      results: _results,
      publicVoters: _publicVoters,
      close: _automaticClose ? close : '',
    );
    final validation = draft.validate(
      maximumOptions: widget.maximumOptions,
      isStaff: widget.isStaff,
    );
    if (!validation.isValid) {
      setState(() => _error = validation.firstError);
      return;
    }
    Navigator.of(context).pop(PollComposerSheetAction.apply(draft));
  }

  bool _checkCurrent() {
    if (widget.isCurrent?.call() ?? true) return true;
    setState(
      () => _error =
          appL10n.theComposerChangedWhileThisPollWasOpenNothingWasChanged,
    );
    return false;
  }

  Future<void> _remove() async {
    if (!_checkCurrent()) return;
    if (widget.isPublished) {
      final confirmed = await confirmPublishedPollRemoval(
        context,
        voterCount: widget.voterCount,
      );
      if (!confirmed || !mounted || !_checkCurrent()) return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(const PollComposerSheetAction.remove());
  }
}
