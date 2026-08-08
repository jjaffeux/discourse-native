import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/poll/poll_card.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

Poll poll({
  String name = 'poll',
  PollType type = PollType.regular,
  PollStatus status = PollStatus.open,
  PollResults results = PollResults.always,
  bool isPublic = false,
  bool isDynamic = false,
  int? min,
  int? max,
  int? step,
  List<PollOption> options = const [
    PollOption(id: 'a', html: 'Alpha'),
    PollOption(id: 'b', html: 'Beta'),
  ],
  int voters = 0,
  DateTime? closeAt,
  PollChartType chartType = PollChartType.bar,
  List<String> groups = const [],
  String? title,
  RankedChoiceOutcome? rankedChoiceOutcome,
  PollSelection selection = PollSelection.none,
}) => Poll(
  name: name,
  type: type,
  status: status,
  results: results,
  isPublic: isPublic,
  isDynamic: isDynamic,
  min: min,
  max: max,
  step: step,
  options: options,
  voters: voters,
  closeAt: closeAt,
  chartType: chartType,
  groups: groups,
  title: title,
  rankedChoiceOutcome: rankedChoiceOutcome,
  selection: selection,
);

Future<void> pumpPoll(
  WidgetTester tester,
  Poll value, {
  bool signedIn = true,
  bool archived = false,
  Iterable<String>? groups = const [],
  bool pending = false,
  PollVoteCallback? onVote,
  PollVoteRemovalCallback? onRemoveVote,
  ValueChanged<Object>? onVoteError,
  VoidCallback? onVoteOnWeb,
  VoidCallback? onConnectAccount,
  DateTime? now,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 640,
          child: PollCard(
            poll: value,
            signedIn: signedIn,
            archived: archived,
            currentUserGroups: groups,
            pending: pending,
            onVote: onVote,
            onRemoveVote: onRemoveVote,
            onVoteError: onVoteError,
            onVoteOnWeb: onVoteOnWeb,
            onConnectAccount: onConnectAccount,
            now: now,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test('percentages use voters and preserve upstream rounding', () {
    expect(
      calculatePollPercentages(
        poll(
          voters: 3,
          options: const [
            PollOption(id: 'a', html: 'A', votes: 1),
            PollOption(id: 'b', html: 'B', votes: 1),
            PollOption(id: 'c', html: 'C', votes: 1),
          ],
        ),
      ),
      [34, 33, 33],
    );
    expect(
      calculatePollPercentages(
        poll(
          type: PollType.multiple,
          voters: 2,
          options: const [
            PollOption(id: 'a', html: 'A', votes: 2),
            PollOption(id: 'b', html: 'B', votes: 1),
          ],
        ),
      ),
      [100, 50],
    );
    expect(
      calculatePollPercentages(
        poll(
          voters: 0,
          options: const [
            PollOption(id: 'a', html: 'A', votes: 0),
            PollOption(id: 'b', html: 'B', votes: 0),
          ],
        ),
      ),
      [0, 0],
    );
  });

  test('number average uses the serialized voter count', () {
    expect(
      calculateNumberPollAverage(
        poll(
          type: PollType.number,
          voters: 4,
          options: const [
            PollOption(id: 'one', html: '1', votes: 1),
            PollOption(id: 'three', html: '3', votes: 3),
          ],
        ),
      ),
      2.5,
    );
  });

  testWidgets('cooked content and accessible tallies render for pie markup', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await pumpPoll(
      tester,
      poll(
        title: '<strong>Lunch choice</strong>',
        chartType: PollChartType.pie,
        voters: 2,
        options: const [
          PollOption(id: 'soup', html: '<em>Soup</em>', votes: 2),
          PollOption(id: 'salad', html: 'Salad', votes: 0),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Lunch choice', findRichText: true), findsOneWidget);
    expect(find.text('Soup', findRichText: true), findsOneWidget);
    expect(find.text('2 votes'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.bySemanticsLabel('Soup, 2 votes, 100 percent'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('missing counts stay confidential rather than becoming zero', (
    tester,
  ) async {
    await pumpPoll(
      tester,
      poll(
        voters: 12,
        results: PollResults.staffOnly,
        options: const [
          PollOption(id: 'a', html: 'Alpha'),
          PollOption(id: 'b', html: 'Beta'),
        ],
      ),
    );
    await tester.pump();

    expect(find.textContaining('12 voters'), findsOneWidget);
    expect(find.textContaining('0 votes'), findsNothing);
    expect(find.text('Results are visible to staff.'), findsOneWidget);
  });

  testWidgets(
    'regular polls save immediately and tapping the saved vote removes it',
    (tester) async {
      List<String>? cast;
      var removals = 0;

      await pumpPoll(
        tester,
        poll(),
        onVote: (_, options) => cast = options,
        onRemoveVote: (_) => removals += 1,
      );
      await tester.tap(find.byKey(const ValueKey('poll-poll-option-a')));
      await tester.pump();
      expect(cast, ['a']);

      await pumpPoll(
        tester,
        poll(selection: const PollSelection(optionIds: ['a'])),
        onVote: (_, options) => cast = options,
        onRemoveVote: (_) => removals += 1,
      );
      await tester.tap(find.byKey(const ValueKey('poll-poll-option-a')));
      await tester.pump();
      expect(removals, 1);
    },
  );

  testWidgets('a failed immediate vote restores the authoritative selection', (
    tester,
  ) async {
    Object? reported;
    await pumpPoll(
      tester,
      poll(selection: const PollSelection(optionIds: ['a'])),
      onVote: (_, _) => throw StateError('reconcile'),
      onRemoveVote: (_) {},
      onVoteError: (error) => reported = error,
    );

    await tester.tap(find.byKey(const ValueKey('poll-poll-option-b')));
    await tester.pump();

    expect(reported, isA<StateError>());
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('poll-poll-option-a')),
        matching: find.byIcon(Icons.radio_button_checked),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('poll-poll-option-b')),
        matching: find.byIcon(Icons.radio_button_unchecked),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'multiple-choice polls stage a bounded selection until Cast votes',
    (tester) async {
      List<String>? cast;
      await pumpPoll(
        tester,
        poll(
          type: PollType.multiple,
          min: 1,
          max: 2,
          options: const [
            PollOption(id: 'a', html: 'Alpha'),
            PollOption(id: 'b', html: 'Beta'),
            PollOption(id: 'c', html: 'Gamma'),
          ],
        ),
        onVote: (_, options) => cast = options,
        onRemoveVote: (_) {},
      );

      await tester.tap(find.byKey(const ValueKey('poll-poll-option-a')));
      await tester.tap(find.byKey(const ValueKey('poll-poll-option-b')));
      await tester.tap(find.byKey(const ValueKey('poll-poll-option-c')));
      await tester.pump();
      expect(cast, isNull);

      await tester.tap(find.byKey(const ValueKey('poll-poll-cast')));
      await tester.pump();
      expect(cast, ['a', 'b']);
    },
  );

  testWidgets('an existing multiple-choice ballot can be removed', (
    tester,
  ) async {
    var removals = 0;
    await pumpPoll(
      tester,
      poll(
        type: PollType.multiple,
        min: 1,
        max: 2,
        selection: const PollSelection(optionIds: ['a']),
      ),
      onVote: (_, _) {},
      onRemoveVote: (_) => removals += 1,
    );

    await tester.tap(find.byKey(const ValueKey('poll-poll-option-a')));
    await tester.pump();
    expect(find.text('Remove votes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('poll-poll-cast')));
    await tester.pump();
    expect(removals, 1);
  });

  testWidgets(
    'group matching is case insensitive and unknown membership is safe',
    (tester) async {
      List<String>? cast;
      final restricted = poll(groups: const ['Team Members']);
      await pumpPoll(
        tester,
        restricted,
        groups: const ['team members'],
        onVote: (_, options) => cast = options,
        onRemoveVote: (_) {},
      );
      await tester.tap(find.byKey(const ValueKey('poll-poll-option-a')));
      await tester.pump();
      expect(cast, ['a']);

      cast = null;
      await pumpPoll(
        tester,
        restricted,
        groups: null,
        onVote: (_, options) => cast = options,
        onRemoveVote: (_) {},
      );
      await tester.pump();
      expect(
        find.textContaining('group membership could not be confirmed'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('poll-poll-option-a')));
      await tester.pump();
      expect(cast, isNull);
    },
  );

  testWidgets('ranked-choice polls show their outcome and vote on web', (
    tester,
  ) async {
    var opened = false;
    await pumpPoll(
      tester,
      poll(
        type: PollType.rankedChoice,
        rankedChoiceOutcome: const RankedChoiceOutcome(
          winner: true,
          winningCandidate: PollRankedCandidate(
            digest: 'a',
            html: '<strong>Alpha</strong>',
          ),
        ),
        selection: const PollSelection(
          rankedChoices: [RankedPollSelection(digest: 'b', rank: 1)],
        ),
      ),
      onVoteOnWeb: () => opened = true,
    );
    await tester.pump();

    expect(find.text('Winner'), findsOneWidget);
    expect(find.text('Alpha', findRichText: true), findsAtLeastNWidgets(1));
    expect(find.text('1.'), findsOneWidget);
    await tester.tap(find.text('Vote on web'));
    expect(opened, isTrue);
  });

  testWidgets('signed-out and archived polls explain why they are read only', (
    tester,
  ) async {
    var connected = false;
    await pumpPoll(
      tester,
      poll(),
      signedIn: false,
      onVote: (_, _) {},
      onRemoveVote: (_) {},
      onConnectAccount: () => connected = true,
    );
    await tester.pump();
    expect(find.text('Connect an account to vote.'), findsOneWidget);
    await tester.tap(find.text('Connect account'));
    expect(connected, isTrue);

    await pumpPoll(
      tester,
      poll(),
      archived: true,
      onVote: (_, _) {},
      onRemoveVote: (_) {},
    );
    await tester.pump();
    expect(
      find.text('Voting is unavailable because this topic is archived.'),
      findsOneWidget,
    );
  });

  testWidgets('the cooked fallback omits the skeleton zero tally', (
    tester,
  ) async {
    final fragment = html_parser.parseFragment('''
      <div class="poll" data-poll-name="missing">
        <div class="poll-title">Favorite <em>berry</em>?</div>
        <div class="poll-container"><ul>
          <li data-poll-option-id="a"><strong>Strawberry</strong></li>
          <li data-poll-option-id="b">Blueberry</li>
        </ul></div>
        <div class="poll-info"><span class="info-number">0</span>
          <span class="info-label">voters</span></div>
      </div>
    ''');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PollFallbackCard.fromCooked(fragment.querySelector('.poll')!),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Favorite berry?', findRichText: true), findsOneWidget);
    expect(find.text('Strawberry', findRichText: true), findsOneWidget);
    expect(find.textContaining('voters'), findsNothing);
    expect(find.text('0'), findsNothing);
  });
}
