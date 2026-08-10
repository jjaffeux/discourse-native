import 'dart:async';

import 'package:flutter/material.dart';

import '../../shell/adaptive_dialog_action.dart';
import '../../shell/shell_sheet.dart';
import '../../theme/app_theme.dart';
import 'poll_composer_editor.dart';
import 'poll_composer_parser.dart';

enum PollComposerSheetActionType { apply, remove, editRaw }

@immutable
class PollComposerSheetAction {
  const PollComposerSheetAction._(this.type, this.draft);

  const PollComposerSheetAction.apply(PollComposerDraft draft)
    : this._(PollComposerSheetActionType.apply, draft);

  const PollComposerSheetAction.remove()
    : this._(PollComposerSheetActionType.remove, null);

  const PollComposerSheetAction.editRaw()
    : this._(PollComposerSheetActionType.editRaw, null);

  final PollComposerSheetActionType type;
  final PollComposerDraft? draft;
}

/// Opens the add/edit poll editor without mutating the composer itself.
///
/// The caller applies the returned action through the verified source helpers
/// in `poll_composer_editor.dart`. [isCurrent] adds an earlier UI guard, so a
/// disposed or changed composer can explain the safe no-op before this closes.
Future<PollComposerSheetAction?> showPollComposerSheet({
  required BuildContext context,
  required PollComposerDraft draft,
  required int maximumOptions,
  required bool isStaff,
  required bool isPublished,
  int? voterCount,
  bool Function()? isCurrent,
}) {
  final title = draft.isNew ? 'Add poll' : 'Edit poll';
  Widget editor(BuildContext context) => PollComposerSheet(
    draft: draft,
    maximumOptions: maximumOptions,
    isStaff: isStaff,
    isPublished: isPublished,
    voterCount: voterCount,
    isCurrent: isCurrent,
  );
  final isTouch = switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    _ => false,
  };

  if (isTouch) {
    return showShellSheet<PollComposerSheetAction>(
      context: context,
      title: title,
      padding: EdgeInsets.zero,
      builder: editor,
    );
  }

  return showDialog<PollComposerSheetAction>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Theme.of(dialogContext).shell.floating,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(dialogContext).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Divider(color: Theme.of(dialogContext).shell.divider, height: 1),
            Flexible(
              child: SingleChildScrollView(child: editor(dialogContext)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Confirms removal when an existing post may already have poll votes.
Future<bool> confirmPublishedPollRemoval(
  BuildContext context, {
  int? voterCount,
}) async {
  final detail = voterCount == null
      ? 'This poll may already have votes.'
      : 'This poll has $voterCount '
            '${voterCount == 1 ? 'voter' : 'voters'}.';
  return await showAdaptiveDialog<bool>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: const Text('Remove published poll?'),
          content: Text(
            '$detail Removing it will remove the poll from the post.',
          ),
          actions: [
            AdaptiveDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            AdaptiveDialogAction(
              onPressed: () => Navigator.of(context).pop(true),
              kind: AdaptiveDialogActionKind.destructive,
              child: const Text('Remove poll'),
            ),
          ],
        ),
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
  });

  final PollComposerDraft draft;
  final int maximumOptions;
  final bool isStaff;
  final bool isPublished;
  final int? voterCount;
  final bool Function()? isCurrent;

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Title (optional)',
              hintText: 'Lunch choice',
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          _typeField(),
          if (_isRanked) ...[
            const SizedBox(height: 6),
            Text(
              'Ranked-choice polls keep their type. Voting remains available '
              'on the web.',
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
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Public voter identities'),
            subtitle: const Text(
              'The voter list itself is shown on the web in this version.',
            ),
            value: _publicVoters,
            onChanged: (value) => setState(() => _publicVoters = value),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Automatic close'),
            value: _automaticClose,
            onChanged: (value) => setState(() => _automaticClose = value),
          ),
          if (_automaticClose)
            TextField(
              controller: _close,
              decoration: const InputDecoration(
                labelText: 'Close date and time',
                hintText: '2026-08-30T18:00:00Z',
                helperText: 'ISO 8601, including a time zone',
              ),
              keyboardType: TextInputType.datetime,
            ),
          if (_error case final error?) ...[
            const SizedBox(height: 16),
            Text(
              error,
              key: const ValueKey('poll-sheet-error'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 24),
          _actions(),
        ],
      ),
    );
  }

  Widget _typeField() {
    final choices = <ComposerPollType>[
      ComposerPollType.regular,
      ComposerPollType.multiple,
      ComposerPollType.number,
      if (_isRanked) ComposerPollType.rankedChoice,
    ];
    return DropdownButtonFormField<ComposerPollType>(
      initialValue: _type,
      decoration: const InputDecoration(labelText: 'Poll type'),
      items: [
        for (final type in choices)
          DropdownMenuItem(value: type, child: Text(_typeLabel(type))),
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
    );
  }

  static String _typeLabel(ComposerPollType type) => switch (type) {
    ComposerPollType.regular => 'Single choice',
    ComposerPollType.multiple => 'Multiple choice',
    ComposerPollType.number => 'Number',
    ComposerPollType.rankedChoice => 'Ranked choice',
    ComposerPollType.unknown => 'Unknown',
  };

  Widget _optionFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Options', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      for (var index = 0; index < _options.length; index++)
        Padding(
          key: ObjectKey(_options[index]),
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _options[index],
                  decoration: InputDecoration(labelText: 'Option ${index + 1}'),
                ),
              ),
              IconButton(
                onPressed: index == 0 ? null : () => _moveOption(index, -1),
                icon: const Icon(Icons.arrow_upward),
                tooltip: 'Move option up',
              ),
              IconButton(
                onPressed: index == _options.length - 1
                    ? null
                    : () => _moveOption(index, 1),
                icon: const Icon(Icons.arrow_downward),
                tooltip: 'Move option down',
              ),
              IconButton(
                onPressed: () => _removeOption(index),
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Remove option',
              ),
            ],
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: _options.length >= widget.maximumOptions
              ? null
              : _addOption,
          icon: const Icon(Icons.add),
          label: const Text('Add option'),
        ),
      ),
      if (_isMultiple) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _integerField(_minimum, 'Minimum choices')),
            const SizedBox(width: 12),
            Expanded(child: _integerField(_maximum, 'Maximum choices')),
          ],
        ),
      ],
    ],
  );

  Widget _numberFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Number range', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(child: _integerField(_minimum, 'Minimum')),
          const SizedBox(width: 12),
          Expanded(child: _integerField(_maximum, 'Maximum')),
          const SizedBox(width: 12),
          Expanded(child: _integerField(_step, 'Step')),
        ],
      ),
      const SizedBox(height: 8),
      const Text('Options are generated inclusively from this range.'),
    ],
  );

  Widget _integerField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
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
    return DropdownButtonFormField<PollResultMode>(
      initialValue: _results,
      decoration: const InputDecoration(labelText: 'Show results'),
      items: [
        for (final result in choices)
          DropdownMenuItem(
            value: result,
            enabled: result != PollResultMode.unknown,
            child: Text(
              result == PollResultMode.unknown
                  ? 'Preserve “${widget.draft.resultsSource}”'
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
    );
  }

  Widget _actions() => Wrap(
    alignment: WrapAlignment.end,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    runSpacing: 8,
    children: [
      if (!widget.draft.isNew) ...[
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(const PollComposerSheetAction.editRaw()),
          child: const Text('Edit as raw'),
        ),
        TextButton(
          onPressed: () => unawaited(_remove()),
          child: const Text('Remove'),
        ),
      ],
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _apply, child: const Text('Apply')),
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
      setState(() => _error = 'Automatic close needs a date and time.');
      return;
    }
    final minimum = int.tryParse(_minimum.text.trim());
    final maximum = int.tryParse(_maximum.text.trim());
    final step = int.tryParse(_step.text.trim());
    if ((_isMultiple || _isNumber) && (minimum == null || maximum == null) ||
        _isNumber && step == null) {
      setState(
        () => _error = 'Minimum, maximum, and step must be whole numbers.',
      );
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
          'The composer changed while this poll was open. Nothing was changed.',
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
