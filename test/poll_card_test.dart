import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/poll/poll_card.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  group('poll models', () {
    test('normalize cooked labels once on immutable values', () {
      final value = Poll.fromJson({
        'name': 'lunch',
        'type': 'ranked_choice',
        'title': '<strong>  Lunch&nbsp; choice </strong>',
        'options': [
          {'id': 'soup', 'html': '<span> Soup &amp; <em>bread</em> </span>'},
        ],
        'ranked_choice_outcome': {
          'winner': true,
          'winning_candidate': {
            'digest': 'soup',
            'html': '<span> Soup &amp; <em>bread</em> </span>',
          },
        },
      }, 'https://site.test')!;

      expect(value.options.single.plainText, 'Soup & bread');
      expect(
        value.rankedChoiceOutcome!.winningCandidate!.plainText,
        'Soup & bread',
      );
    });

    test('calculate voter-based percentages with upstream rounding', () {
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

    test('calculate number averages from the serialized voter count', () {
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
  });

  group('poll presentation', () {
    testWidgets(
      'renders cooked content and accessible tallies for pie markup',
      (tester) async {
        final semantics = tester.ensureSemantics();
        var semanticsDisposed = false;
        void disposeSemantics() {
          if (semanticsDisposed) return;
          semantics.dispose();
          semanticsDisposed = true;
        }

        addTearDown(disposeSemantics);
        try {
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
          expect(
            find.bySemanticsLabel('Soup, 2 votes, 100 percent'),
            findsOneWidget,
          );
        } finally {
          disposeSemantics();
        }
      },
    );

    testWidgets('refreshes title semantics when the model title changes', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var semanticsDisposed = false;
      void disposeSemantics() {
        if (semanticsDisposed) return;
        semantics.dispose();
        semanticsDisposed = true;
      }

      addTearDown(disposeSemantics);
      try {
        await pumpPoll(tester, poll(title: '<strong>First title</strong>'));
        expect(find.bySemanticsLabel('Poll: First title'), findsOneWidget);

        await pumpPoll(tester, poll(title: '<em>Second &amp; final</em>'));
        expect(find.bySemanticsLabel('Poll: Second & final'), findsOneWidget);
      } finally {
        disposeSemantics();
      }
    });

    testWidgets('exposes 44-pixel options as native keyboard buttons', (
      tester,
    ) async {
      List<String>? cast;
      final semantics = tester.ensureSemantics();
      try {
        await pumpPoll(
          tester,
          poll(),
          onVote: (_, options) => cast = options,
          onRemoveVote: (_) {},
        );
        await tester.pumpAndSettle();

        final option = find.byKey(const ValueKey('poll-poll-option-a'));
        final target = find.bySemanticsLabel('Alpha');
        expect(option, findsOneWidget);
        expect(target, findsOneWidget);
        expect(tester.getSize(option).height, 44);
        expect(
          tester.getSemantics(target),
          isSemantics(
            label: 'Alpha',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasSelectedState: true,
            isSelected: false,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          tester.getSemantics(target),
          isSemantics(isFocusable: true, isFocused: true),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(cast, ['a']);
        expect(
          tester.getSemantics(target),
          isSemantics(label: 'Alpha', hasSelectedState: true, isSelected: true),
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets(
      'keeps unavailable counts confidential instead of showing zero',
      (tester) async {
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
      },
    );

    testWidgets('renders a ranked-choice winner and existing rank', (
      tester,
    ) async {
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
      );
      await tester.pump();

      expect(find.text('Winner'), findsOneWidget);
      expect(find.text('Alpha', findRichText: true), findsNWidgets(2));
      expect(find.text('1.'), findsOneWidget);
    });
  });

  group('voting lifecycle', () {
    testWidgets('casts a regular choice immediately', (tester) async {
      List<String>? cast;

      await pumpPoll(
        tester,
        poll(),
        onVote: (_, options) => cast = options,
        onRemoveVote: (_) {},
      );
      await tester.tap(find.byKey(const ValueKey('poll-poll-option-a')));
      await tester.pump();
      expect(cast, ['a']);
    });

    testWidgets('removes a saved regular vote on repeat tap', (tester) async {
      var removals = 0;

      await pumpPoll(
        tester,
        poll(selection: const PollSelection(optionIds: ['a'])),
        onVote: (_, _) {},
        onRemoveVote: (_) => removals += 1,
      );
      await tester.tap(find.byKey(const ValueKey('poll-poll-option-a')));
      await tester.pump();
      expect(removals, 1);
    });

    testWidgets(
      'restores the authoritative selection and forwards the same vote failure',
      (tester) async {
        final failure = StateError('reconcile');
        Object? reported;
        await pumpPoll(
          tester,
          poll(selection: const PollSelection(optionIds: ['a'])),
          onVote: (_, _) => throw failure,
          onRemoveVote: (_) {},
          onVoteError: (error) => reported = error,
        );

        await tester.tap(find.byKey(const ValueKey('poll-poll-option-b')));
        await tester.pump();

        expect(reported, same(failure));
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('poll-poll-option-a')),
            matching: find.byWidgetPredicate(
              (widget) => widget is DIcon && widget.icon == DIcons.circleDot,
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('poll-poll-option-b')),
            matching: find.byWidgetPredicate(
              (widget) => widget is DIcon && widget.icon == DIcons.circle,
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('stages a bounded multiple-choice selection until Cast votes', (
      tester,
    ) async {
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
    });

    testWidgets('removes an existing multiple-choice ballot', (tester) async {
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

    testWidgets('delegates ranked-choice voting to the web', (tester) async {
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

      await tester.tap(find.text('Vote on web'));
      expect(opened, isTrue);
    });
  });

  group('voting eligibility', () {
    testWidgets('matches group names case-insensitively', (tester) async {
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
    });

    testWidgets('denies voting when group membership is unknown', (
      tester,
    ) async {
      List<String>? cast;
      await pumpPoll(
        tester,
        poll(groups: const ['Team Members']),
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
    });

    testWidgets('offers account connection when signed out', (tester) async {
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
    });

    testWidgets('explains why archived-topic voting is unavailable', (
      tester,
    ) async {
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
  });

  group('cooked fallback', () {
    testWidgets('renders cooked labels without the skeleton zero tally', (
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
  });
}
