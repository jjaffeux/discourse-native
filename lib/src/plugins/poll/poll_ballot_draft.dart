import 'poll.dart';

final class PollBallotDraft {
  PollBallotDraft(Poll poll, {Iterable<String>? selection})
    : _poll = poll,
      selection = Set.unmodifiable(selection ?? poll.selectedOptionIds);

  final Poll _poll;
  final Set<String> selection;

  int get minimum {
    final value = _poll.min ?? 1;
    return value < 1 ? 1 : value;
  }

  int get maximum {
    final value = _poll.max ?? _poll.options.length;
    if (value < 1) return 1;
    return value > _poll.options.length ? _poll.options.length : value;
  }

  bool get hasChanges => !_sameSet(selection, _poll.selectedOptionIds.toSet());

  bool canToggleMultiple(String optionId) =>
      selection.contains(optionId) || selection.length < maximum;

  PollBallotDraft reconcile(Poll next) {
    final oldOptions = _poll.options.map((option) => option.id).toSet();
    final newOptions = next.options.map((option) => option.id).toSet();
    if (_poll.name != next.name ||
        _poll.type != next.type ||
        !_sameSet(
          _poll.selectedOptionIds.toSet(),
          next.selectedOptionIds.toSet(),
        ) ||
        !_sameSet(oldOptions, newOptions)) {
      return PollBallotDraft(next);
    }

    return PollBallotDraft(
      next,
      selection: selection.where(newOptions.contains),
    );
  }

  PollBallotDraft chooseSingle(String optionId) => PollBallotDraft(
    _poll,
    selection: _poll.selectedOptionIds.contains(optionId)
        ? const <String>{}
        : <String>{optionId},
  );

  PollBallotDraft toggleMultiple(String optionId) {
    final next = Set<String>.of(selection);
    if (!next.remove(optionId) && next.length < maximum) {
      next.add(optionId);
    }
    return PollBallotDraft(_poll, selection: next);
  }

  PollBallotSubmission? get submission {
    if (!hasChanges) return null;
    if (selection.isEmpty) return const PollBallotWithdrawal();
    if (_poll.type == PollType.multiple &&
        (selection.length < minimum || selection.length > maximum)) {
      return null;
    }
    if (_poll.type != PollType.multiple) return PollBallotCast(selection);

    return PollBallotCast([
      for (final option in _poll.options)
        if (selection.contains(option.id)) option.id,
    ]);
  }
}

sealed class PollBallotSubmission {
  const PollBallotSubmission();
}

final class PollBallotCast extends PollBallotSubmission {
  PollBallotCast(Iterable<String> optionIds)
    : optionIds = List.unmodifiable(optionIds);

  final List<String> optionIds;
}

final class PollBallotWithdrawal extends PollBallotSubmission {
  const PollBallotWithdrawal();
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);
