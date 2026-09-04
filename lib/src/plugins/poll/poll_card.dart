import 'dart:async';

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../shell/cooked_html.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'poll.dart';

typedef PollVoteCallback =
    FutureOr<void> Function(Poll poll, List<String> optionIds);

typedef PollVoteRemovalCallback = FutureOr<void> Function(Poll poll);

/// Treats missing [PollOption.votes] as confidential, not zero. Multiple-choice
/// polls keep a local draft; other types save immediately.
class PollCard extends StatefulWidget {
  const PollCard({
    super.key,
    required this.poll,
    required this.signedIn,
    required this.archived,
    this.siteUrl,
    this.currentUserGroups,
    this.pending = false,
    this.onVote,
    this.onRemoveVote,
    this.onVoteError,
    this.onVoteOnWeb,
    this.onConnectAccount,
    this.now,
  });

  final Poll poll;
  final String? siteUrl;

  final bool signedIn;

  /// Freshly loaded group names. `null` means membership has not been
  /// confirmed yet; an empty iterable means it has and the account is in none.
  final Iterable<String>? currentUserGroups;

  final bool archived;

  final bool pending;

  final PollVoteCallback? onVote;
  final PollVoteRemovalCallback? onRemoveVote;

  final ValueChanged<Object>? onVoteError;

  final VoidCallback? onVoteOnWeb;

  final VoidCallback? onConnectAccount;

  final DateTime? now;

  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  late Set<String> _selection;
  String? _plainTitle;
  var _submitting = false;

  Poll get _poll => widget.poll;

  Set<String> get _savedSelection => _poll.selectedOptionIds.toSet();

  bool get _isMultiple => _poll.type == PollType.multiple;

  bool get _isRankedChoice => _poll.type == PollType.rankedChoice;

  DateTime get _now => widget.now ?? DateTime.now();

  bool get _automaticallyClosed =>
      _poll.closeAt != null && !_poll.closeAt!.isAfter(_now);

  bool get _effectivelyOpen => _poll.isOpen && !_automaticallyClosed;

  bool get _hasVisibleResults =>
      _poll.options.isNotEmpty &&
      _poll.options.every((option) => option.votes != null);

  int get _multipleMin {
    final value = _poll.min ?? 1;
    return value < 1 ? 1 : value;
  }

  int get _multipleMax {
    final value = _poll.max ?? _poll.options.length;
    if (value < 1) return 1;
    return value > _poll.options.length ? _poll.options.length : value;
  }

  @override
  void initState() {
    super.initState();
    _selection = _savedSelection;
    _plainTitle = _poll.title == null ? null : _plainText(_poll.title!);
  }

  @override
  void didUpdateWidget(PollCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.poll.title != _poll.title) {
      _plainTitle = _poll.title == null ? null : _plainText(_poll.title!);
    }

    final oldSaved = oldWidget.poll.selectedOptionIds.toSet();
    final newSaved = _savedSelection;
    final oldOptions = oldWidget.poll.options
        .map((option) => option.id)
        .toSet();
    final newOptions = _poll.options.map((option) => option.id).toSet();

    // Count-only live updates must not erase an uncast multiple-choice draft.
    if (oldWidget.poll.name != _poll.name ||
        oldWidget.poll.type != _poll.type ||
        !_sameSet(oldSaved, newSaved) ||
        !_sameSet(oldOptions, newOptions)) {
      _selection = newSaved;
    } else {
      _selection.removeWhere((id) => !newOptions.contains(id));
    }
  }

  String? get _voteRestriction {
    if (_poll.status == PollStatus.closed || _automaticallyClosed) {
      return 'This poll is closed.';
    }
    if (_poll.status != PollStatus.open) {
      return 'This poll has an unsupported status and is read only.';
    }
    if (widget.archived) {
      return 'Voting is unavailable because this topic is archived.';
    }
    if (!widget.signedIn) {
      return 'Connect an account to vote.';
    }
    if (_poll.groups.isNotEmpty) {
      final currentGroups = widget.currentUserGroups;
      if (currentGroups == null) {
        return 'Your group membership could not be confirmed, so this poll is read only.';
      }

      final accountGroups = currentGroups
          .map((name) => name.trim().toLowerCase())
          .where((name) => name.isNotEmpty)
          .toSet();
      final eligible = _poll.groups.any(
        (name) => accountGroups.contains(name.trim().toLowerCase()),
      );
      if (!eligible) {
        return 'Only members of ${_humanList(_poll.groups)} can vote in this poll.';
      }
    }
    return null;
  }

  bool get _canVote =>
      _poll.supportsNativeVoting &&
      _voteRestriction == null &&
      widget.onVote != null &&
      !_submitting &&
      !widget.pending;

  Future<void> _chooseSingle(String optionId) async {
    if (!_canVote) return;

    final saved = _savedSelection;
    final removing = saved.contains(optionId);
    final previous = Set<String>.of(_selection);
    setState(() {
      _selection = removing ? <String>{} : <String>{optionId};
      _submitting = true;
    });

    try {
      if (removing) {
        final remove = widget.onRemoveVote;
        if (remove == null) {
          setState(() => _selection = previous);
          return;
        }
        await Future<void>.sync(() => remove(_poll));
      } else {
        await Future<void>.sync(() => widget.onVote!(_poll, [optionId]));
      }
    } catch (error) {
      if (mounted) setState(() => _selection = _savedSelection);
      widget.onVoteError?.call(error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toggleMultiple(String optionId) {
    if (!_canVote) return;

    setState(() {
      if (!_selection.remove(optionId) && _selection.length < _multipleMax) {
        _selection.add(optionId);
      }
    });
  }

  bool get _multipleChanged => !_sameSet(_selection, _savedSelection);

  bool get _multipleSelectionValid {
    if (!_multipleChanged) return false;
    // The minimum applies to casting, not withdrawing, a ballot.
    if (_selection.isEmpty) return _savedSelection.isNotEmpty;
    return _selection.length >= _multipleMin &&
        _selection.length <= _multipleMax;
  }

  Future<void> _castMultiple() async {
    if (!_canVote || !_multipleSelectionValid) return;

    final previous = Set<String>.of(_selection);
    var succeeded = false;
    setState(() => _submitting = true);
    try {
      if (_selection.isEmpty) {
        final remove = widget.onRemoveVote;
        if (remove == null) {
          if (mounted) setState(() => _selection = _savedSelection);
          return;
        }
        await Future<void>.sync(() => remove(_poll));
      } else {
        final ordered = [
          for (final option in _poll.options)
            if (_selection.contains(option.id)) option.id,
        ];
        await Future<void>.sync(() => widget.onVote!(_poll, ordered));
      }
      succeeded = true;
    } catch (error) {
      if (mounted) setState(() => _selection = _savedSelection);
      widget.onVoteError?.call(error);
    } finally {
      if (mounted) {
        // Keep selection responsive until the owner applies its personalized response.
        setState(() {
          if (succeeded) _selection = previous;
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final restriction = _voteRestriction;
    final unavailableType = !_poll.supportsNativeVoting;
    final disabled = widget.pending || _submitting;

    return Semantics(
      container: true,
      label: _plainTitle == null ? 'Poll' : 'Poll: $_plainTitle',
      child: Card(
        key: ValueKey<String>('poll-${_poll.name}'),
        margin: const EdgeInsets.symmetric(vertical: 8),
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: AbsorbPointer(
          absorbing: disabled,
          child: AnimatedOpacity(
            opacity: disabled ? 0.68 : 1,
            duration: const Duration(milliseconds: 120),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_poll.title != null &&
                      _poll.title!.trim().isNotEmpty) ...[
                    CookedHtml(
                      html: _poll.title!,
                      siteUrl: widget.siteUrl,
                      textStyle: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                  ],
                  _PollMetadata(
                    poll: _poll,
                    effectivelyOpen: _effectivelyOpen,
                    automaticallyClosed: _automaticallyClosed,
                  ),
                  const SizedBox(height: 12),
                  if (_isRankedChoice)
                    _RankedChoiceBody(poll: _poll, siteUrl: widget.siteUrl)
                  else ...[
                    if (_poll.type == PollType.number && _hasVisibleResults)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          'Weighted average: ${_formatAverage(calculateNumberPollAverage(_poll))}',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    for (var index = 0; index < _poll.options.length; index++)
                      _PollOptionRow(
                        key: ValueKey<String>(
                          'poll-${_poll.name}-option-${_poll.options[index].id}',
                        ),
                        option: _poll.options[index],
                        selected: _selection.contains(_poll.options[index].id),
                        multiple: _isMultiple,
                        canSelect:
                            _canVote &&
                            (!_isMultiple ||
                                _selection.contains(_poll.options[index].id) ||
                                _selection.length < _multipleMax),
                        percentage: _hasVisibleResults
                            ? calculatePollPercentages(_poll)[index]
                            : null,
                        siteUrl: widget.siteUrl,
                        onTap: _isMultiple
                            ? () => _toggleMultiple(_poll.options[index].id)
                            : () => _chooseSingle(_poll.options[index].id),
                      ),
                  ],
                  if (_isMultiple &&
                      _poll.supportsNativeVoting &&
                      restriction == null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _multipleMin == _multipleMax
                          ? 'Choose exactly $_multipleMin.'
                          : 'Choose between $_multipleMin and $_multipleMax options.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        key: ValueKey<String>('poll-${_poll.name}-cast'),
                        onPressed: _canVote && _multipleSelectionValid
                            ? _castMultiple
                            : null,
                        child: Text(
                          _selection.isEmpty && _savedSelection.isNotEmpty
                              ? 'Remove votes'
                              : 'Cast votes',
                        ),
                      ),
                    ),
                  ],
                  if (!_hasVisibleResults && !_isRankedChoice) ...[
                    const SizedBox(height: 10),
                    _Guidance(text: _hiddenResultsMessage),
                  ],
                  if (restriction != null) ...[
                    const SizedBox(height: 10),
                    _Guidance(text: restriction),
                  ] else if (unavailableType) ...[
                    const SizedBox(height: 10),
                    _Guidance(
                      text: _isRankedChoice
                          ? 'Ranked-choice voting is available on the web.'
                          : 'This poll type is read only in the app. You can vote on the web.',
                    ),
                  ],
                  if (!_isRankedChoice && _poll.options.isEmpty) ...[
                    const SizedBox(height: 10),
                    const _Guidance(
                      text: 'This poll has no options that can be displayed.',
                    ),
                  ],
                  if (widget.pending || _submitting) ...[
                    const SizedBox(height: 10),
                    const _Guidance(text: 'Saving vote…'),
                  ],
                  if (!_effectivelyOpen && _poll.closeAt != null) ...[
                    const SizedBox(height: 10),
                    _CloseTime(closeAt: _poll.closeAt!, closed: true),
                  ] else if (_effectivelyOpen && _poll.closeAt != null) ...[
                    const SizedBox(height: 10),
                    _CloseTime(closeAt: _poll.closeAt!, closed: false),
                  ],
                  if (unavailableType &&
                      _effectivelyOpen &&
                      widget.onVoteOnWeb != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        key: ValueKey<String>('poll-${_poll.name}-web'),
                        onPressed: widget.onVoteOnWeb,
                        child: const Text('Vote on web'),
                      ),
                    ),
                  ] else if (!widget.signedIn &&
                      _effectivelyOpen &&
                      _poll.supportsNativeVoting &&
                      widget.onConnectAccount != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: ValueKey<String>('poll-${_poll.name}-connect'),
                        onPressed: widget.onConnectAccount,
                        child: const Text('Connect account'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _hiddenResultsMessage {
    if (_poll.results == PollResults.onClose) {
      return _effectivelyOpen
          ? 'Results will be shown when this poll closes.'
          : 'Results are not available.';
    }
    if (_poll.results == PollResults.onVote && !_poll.selection.hasVote) {
      return 'Vote to see results.';
    }
    if (_poll.results == PollResults.staffOnly) {
      return 'Results are visible to staff.';
    }
    return 'Results are not available.';
  }
}

class _PollMetadata extends StatelessWidget {
  const _PollMetadata({
    required this.poll,
    required this.effectivelyOpen,
    required this.automaticallyClosed,
  });

  final Poll poll;
  final bool effectivelyOpen;
  final bool automaticallyClosed;

  @override
  Widget build(BuildContext context) {
    final labels = <String>[
      poll.voters == 1 ? '1 voter' : '${poll.voters} voters',
      effectivelyOpen ? 'Open' : 'Closed',
      poll.isPublic ? 'Public voter identities' : 'Private voter identities',
      if (poll.isDynamic) 'Dynamic options',
      if (poll.groups.isNotEmpty) 'Restricted to ${_humanList(poll.groups)}',
      if (automaticallyClosed) 'Automatically closed',
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (final label in labels) _MetadataChip(label: label)],
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: theme.textTheme.bodyMedium),
    );
  }
}

class _PollOptionRow extends StatelessWidget {
  const _PollOptionRow({
    super.key,
    required this.option,
    required this.selected,
    required this.multiple,
    required this.canSelect,
    required this.percentage,
    required this.siteUrl,
    required this.onTap,
  });

  final PollOption option;
  final bool selected;
  final bool multiple;
  final bool canSelect;
  final int? percentage;
  final String? siteUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final whisper =
        theme.extension<DiscourseColors>()?.whisper ??
        theme.colorScheme.onSurfaceVariant;
    final plain = option.plainText;
    final votes = option.votes;
    final resultLabel = votes == null || percentage == null
        ? ''
        : ', ${votes == 1 ? '1 vote' : '$votes votes'}, $percentage percent';

    return Semantics(
      container: true,
      button: canSelect,
      enabled: canSelect,
      selected: selected,
      label: '$plain$resultLabel',
      child: InkWell(
        onTap: canSelect ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: DIcon(
                        multiple
                            ? (selected ? DIcons.squareCheck : DIcons.square)
                            : (selected ? DIcons.circleDot : DIcons.circle),
                        size: 22,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CookedHtml(
                            html: option.html,
                            siteUrl: siteUrl,
                            textStyle: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (votes != null && percentage != null) ...[
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Text(
                                  votes == 1 ? '1 vote' : '$votes votes',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(color: whisper),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$percentage%',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(color: whisper),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            _ResultBar(percentage: percentage!),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultBar extends StatelessWidget {
  const _ResultBar({required this.percentage});

  final int percentage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = (percentage / 100).clamp(0.0, 1.0);
    return Container(
      height: 7,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: fraction,
        heightFactor: 1,
        child: ColoredBox(color: theme.colorScheme.primary),
      ),
    );
  }
}

class _RankedChoiceBody extends StatelessWidget {
  const _RankedChoiceBody({required this.poll, required this.siteUrl});

  final Poll poll;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final outcome = poll.rankedChoiceOutcome;
    final ranks = {
      for (final choice in poll.selection.rankedChoices)
        choice.digest: choice.rank,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (outcome != null &&
            outcome.tied &&
            outcome.tiedCandidates.isNotEmpty)
          _RankedCandidatesSummary(
            label: 'Tie between',
            candidates: outcome.tiedCandidates,
            siteUrl: siteUrl,
          )
        else if (outcome?.winningCandidate != null)
          _RankedCandidatesSummary(
            label: 'Winner',
            candidates: [outcome!.winningCandidate!],
            siteUrl: siteUrl,
          )
        else
          const _Guidance(text: 'Ranked-choice results are not available yet.'),
        const SizedBox(height: 8),
        for (final option in poll.options)
          Semantics(
            label: ranks[option.id] == null
                ? option.plainText
                : '${option.plainText}, ranked ${ranks[option.id]}',
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        ranks[option.id] == null ? '•' : '${ranks[option.id]}.',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    Expanded(
                      child: CookedHtml(
                        html: option.html,
                        siteUrl: siteUrl,
                        textStyle: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RankedCandidatesSummary extends StatelessWidget {
  const _RankedCandidatesSummary({
    required this.label,
    required this.candidates,
    required this.siteUrl,
  });

  final String label;
  final List<PollRankedCandidate> candidates;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '$label ${candidates.map((candidate) => candidate.plainText).join(', ')}',
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          for (final candidate in candidates)
            CookedHtml(
              html: candidate.html,
              siteUrl: siteUrl,
              textStyle: Theme.of(context).textTheme.titleMedium,
            ),
        ],
      ),
    ),
  );
}

class _Guidance extends StatelessWidget {
  const _Guidance({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: text == 'Saving vote…',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: theme.textTheme.bodyMedium),
      ),
    );
  }
}

class _CloseTime extends StatelessWidget {
  const _CloseTime({required this.closeAt, required this.closed});

  final DateTime closeAt;
  final bool closed;

  @override
  Widget build(BuildContext context) {
    final local = closeAt.toLocal();
    final material = MaterialLocalizations.of(context);
    final date = material.formatShortDate(local);
    final time = material.formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return Text(
      closed
          ? 'Automatically closed $date at $time.'
          : 'Closes $date at $time.',
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

/// Ignores cooked `.poll-info` zeroes, which are JavaScript placeholders.
class PollFallbackCard extends StatelessWidget {
  const PollFallbackCard({
    super.key,
    required this.options,
    this.title,
    this.siteUrl,
  });

  factory PollFallbackCard.fromCooked(
    dom.Element element, {
    Key? key,
    String? siteUrl,
  }) {
    final title = element.querySelector('.poll-title')?.innerHtml.trim();
    final options = element
        .querySelectorAll('.poll-container li[data-poll-option-id]')
        .map((option) => option.innerHtml.trim())
        .where((option) => option.isNotEmpty)
        .toList(growable: false);

    return PollFallbackCard(
      key: key,
      title: title == null || title.isEmpty ? null : title,
      options: options,
      siteUrl: siteUrl,
    );
  }

  final String? title;
  final List<String> options;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: title == null
        ? 'Poll, read only'
        : 'Poll: ${_plainText(title!)}, read only',
    child: Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              CookedHtml(
                html: title!,
                siteUrl: siteUrl,
                textStyle: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
            ],
            for (final option in options)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(
                      child: CookedHtml(
                        html: option,
                        siteUrl: siteUrl,
                        textStyle: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
            if (options.isEmpty)
              const _Guidance(
                text: 'This poll cannot be displayed interactively.',
              ),
          ],
        ),
      ),
    ),
  );
}

/// Uses voters as the denominator; only single-choice polls receive Discourse's
/// even rounding to a visible total of 100.
List<int> calculatePollPercentages(Poll poll) {
  if (poll.options.any((option) => option.votes == null)) return const [];
  if (poll.voters == 0) return List<int>.filled(poll.options.length, 0);

  final exact = [
    for (final option in poll.options) 100 * option.votes! / poll.voters,
  ];
  if (poll.type == PollType.multiple) {
    return exact
        .map((percentage) => percentage.floor())
        .toList(growable: false);
  }

  return _evenRound(exact);
}

/// Uses Discourse's serialized voter count as the weighted-average denominator.
double? calculateNumberPollAverage(Poll poll) {
  if (poll.type != PollType.number ||
      poll.options.any((option) => option.votes == null)) {
    return null;
  }
  if (poll.voters == 0) return 0;

  var total = 0.0;
  for (final option in poll.options) {
    final value = option.numericValue;
    if (value == null) return null;
    total += value * option.votes!;
  }
  return total / poll.voters;
}

List<int> _evenRound(List<double> values) {
  // Poll's `even-round` distributes the remainder by fractional part.
  final working = List<double>.of(values);
  final fractions = [for (final value in working) value - value.floor()];
  final additions = fractions
      .fold<double>(0, (sum, value) => sum + value)
      .ceil();

  for (
    var addition = 0;
    addition < additions && addition < fractions.length;
    addition++
  ) {
    var greatest = 0.0;
    var greatestIndex = 0;
    for (var index = 0; index < fractions.length; index++) {
      if (fractions[index] > greatest) {
        greatest = fractions[index];
        greatestIndex = index;
      }
    }
    working[greatestIndex] += 1;
    fractions[greatestIndex] = 0;
    if (working.fold<int>(0, (sum, value) => sum + value.floor()) == 100) {
      break;
    }
  }
  return working.map((value) => value.floor()).toList(growable: false);
}

String _formatAverage(double? value) {
  if (value == null) return 'Unavailable';
  final fixed = value.toStringAsFixed(2);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _plainText(String html) => (html_parser.parseFragment(html).text ?? html)
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

String _humanList(Iterable<String> values) {
  final names = values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (names.length < 2) return names.join();
  if (names.length == 2) return '${names.first} or ${names.last}';
  return '${names.take(names.length - 1).join(', ')}, or ${names.last}';
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);
