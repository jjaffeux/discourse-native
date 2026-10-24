import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/poll/poll_ballot_draft.dart';
import 'package:flutter_test/flutter_test.dart';

Poll ballot({
  String name = 'poll',
  PollType type = PollType.multiple,
  int? min,
  int? max,
  List<String> ids = const ['a', 'b', 'c'],
  List<String> saved = const [],
  int? votes,
  String label = 'Option',
}) => Poll(
  name: name,
  type: type,
  min: min,
  max: max,
  selection: PollSelection(optionIds: saved),
  options: [
    for (final id in ids) PollOption(id: id, html: label, votes: votes),
  ],
);

void main() {
  test('snapshots selection without sharing mutable caller state', () {
    final selected = <String>{'a'};
    final draft = PollBallotDraft(ballot(), selection: selected);
    selected.add('b');
    expect(draft.selection, {'a'});
    expect(() => draft.selection.add('b'), throwsUnsupportedError);
    final cast = draft.submission as PollBallotCast;
    expect(() => cast.optionIds.add('b'), throwsUnsupportedError);
  });

  test('normalizes the existing minimum and maximum rules', () {
    for (final (min, max, ids, expectedMin, expectedMax) in [
      (null, null, ['a', 'b', 'c'], 1, 3),
      (0, 0, ['a', 'b'], 1, 1),
      (-2, -2, ['a', 'b'], 1, 1),
      (5, 8, ['a', 'b'], 5, 2),
      (null, null, <String>[], 1, 1),
      (1, 2, <String>[], 1, 0),
    ]) {
      final draft = PollBallotDraft(ballot(min: min, max: max, ids: ids));
      expect((draft.minimum, draft.maximum), (expectedMin, expectedMax));
    }
  });

  test('bounds additions while always permitting deselection', () {
    final empty = PollBallotDraft(ballot(max: 1));
    final full = empty.toggleMultiple('b');
    expect(empty.selection, isEmpty);
    expect(full.canToggleMultiple('a'), isFalse);
    expect(full.toggleMultiple('a').selection, {'b'});
    expect(full.canToggleMultiple('b'), isTrue);
    expect(full.toggleMultiple('b').selection, isEmpty);
  });

  test('submits only changed valid selections in current option order', () {
    final original = PollBallotDraft(ballot(min: 2, max: 2));
    expect(original.submission, isNull);
    final one = original.toggleMultiple('c');
    expect(one.submission, isNull);
    final two = one.toggleMultiple('a');
    expect(two.hasChanges, isTrue);
    expect((two.submission as PollBallotCast).optionIds, ['a', 'c']);
    expect(two.toggleMultiple('b').selection, {'a', 'c'});
    expect(
      PollBallotDraft(ballot(min: 1, max: 1), selection: ['a', 'b']).submission,
      isNull,
    );
    final saved = PollBallotDraft(ballot(saved: ['b', 'a']));
    expect(saved.hasChanges, isFalse);
    expect(saved.submission, isNull);
    expect(saved.toggleMultiple('a').toggleMultiple('a').submission, isNull);
  });

  test('withdraws an existing ballot even below minimum', () {
    final draft = PollBallotDraft(
      ballot(min: 2, saved: ['a', 'b']),
    ).toggleMultiple('a').toggleMultiple('b');
    expect(draft.submission, isA<PollBallotWithdrawal>());
    expect(PollBallotDraft(ballot(min: 2)).submission, isNull);
  });

  test('single choice casts immediately and repeat saved choice withdraws', () {
    for (final type in [PollType.regular, PollType.number]) {
      final draft = PollBallotDraft(ballot(type: type, saved: ['a']));
      final next = draft.chooseSingle('b');
      expect(next.selection, {'b'});
      expect((next.submission as PollBallotCast).optionIds, ['b']);
      final withdrawn = draft.chooseSingle('a');
      expect(withdrawn.selection, isEmpty);
      expect(withdrawn.submission, isA<PollBallotWithdrawal>());
    }
  });

  test(
    'keeps an uncast ballot through counts, labels, limits and ordering',
    () {
      final draft = PollBallotDraft(
        ballot(max: 3),
      ).toggleMultiple('c').toggleMultiple('a');
      final updated = draft.reconcile(
        ballot(
          votes: 20,
          label: 'Renamed option',
          ids: ['c', 'b', 'a'],
          min: 2,
          max: 2,
        ),
      );
      expect(updated.selection, {'a', 'c'});
      expect((updated.minimum, updated.maximum), (2, 2));
      expect((updated.submission as PollBallotCast).optionIds, ['c', 'a']);
    },
  );

  test('saved membership order does not replace an uncast ballot', () {
    final draft = PollBallotDraft(
      ballot(saved: ['a', 'b']),
    ).toggleMultiple('b').toggleMultiple('c');
    final updated = draft.reconcile(ballot(saved: ['b', 'a'], votes: 5));
    expect(updated.selection, {'a', 'c'});
  });

  test(
    'poll identity, type, saved membership and option membership reset the draft',
    () {
      final draft = PollBallotDraft(ballot()).toggleMultiple('b');
      for (final updated in [
        ballot(name: 'replacement'),
        ballot(type: PollType.regular),
        ballot(saved: ['a']),
        ballot(ids: ['a', 'b']),
        ballot(ids: ['a', 'b', 'c', 'd']),
      ]) {
        expect(
          draft.reconcile(updated).selection,
          updated.selectedOptionIds.toSet(),
        );
      }
    },
  );
}
