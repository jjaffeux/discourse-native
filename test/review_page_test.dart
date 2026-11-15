import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/models/reviewable.dart';
import 'package:discourse_native/src/shell/review_controller.dart';
import 'package:discourse_native/src/shell/review_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/review_fixture.dart';

const site = 'https://forum.example/discuss';
final items = ReviewablePage.fromJson(reviewListFixture()).items;
Reviewable item(int id) => items.firstWhere((item) => item.id == id);

Widget app(Widget page) => MaterialApp(
  theme: AppTheme.light,
  debugShowCheckedModeBanner: false,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: page),
);

Widget queue({
  ReviewState? state,
  bool permitted = true,
  ValueChanged<ReviewFilters>? onFilters,
  ValueChanged<Reviewable>? onOpen,
  Future<void> Function()? onRefresh,
  VoidCallback? onLoadMore,
}) => app(
  ReviewQueuePage(
    state: state ?? ReviewState(items: items, loaded: true),
    permitted: permitted,
    categories: const [(id: 5, name: 'Sailing')],
    onRefresh: onRefresh ?? () async {},
    onFilters: onFilters ?? (_) {},
    onLoadMore: onLoadMore ?? () {},
    onOpen: onOpen ?? (_) {},
  ),
);

Widget detail({
  ReviewState? state,
  void Function(Reviewable, ReviewableAction)? onPerform,
  VoidCallback? onBrowser,
  VoidCallback? onBack,
}) => app(
  ReviewItemPage(
    state: state ?? ReviewState(selectedId: 77, selected: item(77)),
    siteUrl: site,
    onBack: onBack ?? () {},
    onPerform: onPerform ?? (_, _) {},
    onOpenInBrowser: onBrowser ?? () {},
  ),
);

void main() {
  group('queue', () {
    testWidgets('an account that may not review sees why, and no filters', (
      tester,
    ) async {
      await tester.pumpWidget(queue(permitted: false, state: ReviewState()));
      expect(
        find.text(
          'Only staff and category moderators can see the review queue.',
        ),
        findsOneWidget,
      );
      expect(find.byType(DSelect<ReviewStatusFilter>), findsNothing);
      expect(find.byType(DSpinner), findsNothing);
    });

    testWidgets('a queue that has not landed announces that it is loading', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(queue(state: ReviewState()));
      expect(find.bySemanticsLabel('Loading review queue'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('each row is one labelled button naming what it is about', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      Reviewable? opened;
      await tester.pumpWidget(queue(onOpen: (item) => opened = item));

      final flagged = find.bySemanticsLabel(
        RegExp(
          r'^Review item: Dock lines, Flagged post · Pending · '
          r'Written by @spammer.*, Spam, Inappropriate$',
        ),
      );
      expect(flagged, findsOneWidget);
      expect(
        tester.getSemantics(flagged),
        matchesSemantics(
          label: tester.getSemantics(flagged).label,
          isButton: true,
        ),
      );
      expect(
        find.bySemanticsLabel(
          RegExp('^Review item: Hello harbour, Queued topic'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('^Review item: @newbie, User')),
        findsOneWidget,
      );

      await tester.tap(find.text('Dock lines'));
      expect(opened?.id, 77);
      handle.dispose();
    });

    testWidgets('a type with no dedicated view still gets a readable row', (
      tester,
    ) async {
      final plugin = Reviewable(id: 5, type: 'ReviewableAiToolAction');
      await tester.pumpWidget(
        queue(state: ReviewState(items: [plugin, item(80)], loaded: true)),
      );
      expect(find.textContaining('Ai Tool Action'), findsWidgets);
      expect(find.textContaining('Flagged chat message'), findsWidgets);
    });

    testWidgets('an empty queue and a failed one say different things', (
      tester,
    ) async {
      await tester.pumpWidget(queue(state: ReviewState(loaded: true)));
      expect(find.text('There are no items to review.'), findsOneWidget);

      var retries = 0;
      await tester.pumpWidget(
        queue(
          state: ReviewState(failure: ReviewFailure.unavailable),
          onRefresh: () async => retries++,
        ),
      );
      expect(find.text('The review queue couldn’t be loaded.'), findsOneWidget);
      expect(find.text('There are no items to review.'), findsNothing);
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
    });

    testWidgets('a refused queue offers no retry', (tester) async {
      await tester.pumpWidget(
        queue(state: ReviewState(failure: ReviewFailure.forbidden)),
      );
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('choosing a status asks for that queue', (tester) async {
      ReviewFilters? chosen;
      await tester.pumpWidget(queue(onFilters: (filters) => chosen = filters));
      await tester.tap(find.byType(DSelect<ReviewStatusFilter>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All reviewed').last);
      await tester.pumpAndSettle();
      expect(chosen?.status, ReviewStatusFilter.reviewed);
    });

    testWidgets('a submitted username filters by the author', (tester) async {
      ReviewFilters? chosen;
      await tester.pumpWidget(queue(onFilters: (filters) => chosen = filters));
      await tester.enterText(find.byType(EditableText), ' sam ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      expect(chosen?.username, 'sam');
    });

    testWidgets('the outcome of the last action is said above the rows', (
      tester,
    ) async {
      await tester.pumpWidget(
        queue(
          state: ReviewState(
            items: items,
            loaded: true,
            notice: const ReviewPerformed('Flag agreed.'),
          ),
        ),
      );
      expect(find.text('Flag agreed.'), findsOneWidget);
    });

    testWidgets('more rows are requested from the foot of the list', (
      tester,
    ) async {
      var loads = 0;
      await tester.pumpWidget(
        queue(
          state: ReviewState(items: items, loaded: true, nextOffset: 10),
          onLoadMore: () => loads++,
        ),
      );
      await tester.pump();
      expect(loads, greaterThan(0));
    });
  });

  group('item', () {
    testWidgets('shows the content, who flagged it and why', (tester) async {
      await tester.pumpWidget(detail());
      await tester.pumpAndSettle();
      expect(find.text('Dock lines'), findsOneWidget);
      expect(
        find.textContaining('Buy cheap rope here', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Written by @spammer'), findsOneWidget);
      expect(find.text('Spam'), findsOneWidget);
      expect(find.textContaining('Flagged by @flagger'), findsOneWidget);
      expect(find.textContaining('Agreed'), findsOneWidget);
    });

    testWidgets('an account under review shows its details', (tester) async {
      await tester.pumpWidget(
        detail(state: ReviewState(selectedId: 79, selected: item(79))),
      );
      await tester.pumpAndSettle();
      expect(find.text('@newbie'), findsOneWidget);
      expect(find.text('newbie@example.com'), findsOneWidget);
      expect(find.text('No reasons were recorded.'), findsOneWidget);
    });

    testWidgets('an unknown type says so and still shows what the site sent', (
      tester,
    ) async {
      await tester.pumpWidget(
        detail(state: ReviewState(selectedId: 80, selected: item(80))),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('This kind of item can’t be shown in full here yet.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('chat text', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text('There is nothing left to do on this item.'),
        findsOneWidget,
      );
    });

    testWidgets('a plain action is sent as soon as it is pressed', (
      tester,
    ) async {
      final performed = <String>[];
      await tester.pumpWidget(
        detail(onPerform: (_, action) => performed.add(action.serverAction)),
      );
      await tester.tap(find.text('Keep post'));
      await tester.pumpAndSettle();
      expect(performed, ['agree_and_keep']);
      expect(find.byType(DAlertDialogContent), findsNothing);
    });

    testWidgets('a destructive action is only sent once confirmed', (
      tester,
    ) async {
      final performed = <String>[];
      await tester.pumpWidget(
        detail(onPerform: (_, action) => performed.add(action.serverAction)),
      );
      await tester.ensureVisible(find.text('Delete post'));
      await tester.tap(find.text('Delete post'));
      await tester.pumpAndSettle();
      expect(find.byType(DAlertDialogContent), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(performed, isEmpty);

      await tester.tap(find.text('Delete user'));
      await tester.pumpAndSettle();
      expect(
        find.text('Are you sure you want to delete @spammer?'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('review-confirm-action')));
      await tester.pumpAndSettle();
      expect(performed, ['delete_user']);
    });

    testWidgets('an action needing more input opens the site instead', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final performed = <String>[];
      var browser = 0;
      await tester.pumpWidget(
        detail(
          onPerform: (_, action) => performed.add(action.serverAction),
          onBrowser: () => browser++,
        ),
      );
      expect(
        find.bySemanticsLabel('Suspend user, opens in browser'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Suspend user'));
      await tester.tap(find.text('Suspend user'));
      await tester.pumpAndSettle();
      expect(browser, 1);
      expect(performed, isEmpty);
      expect(find.byType(DAlertDialogContent), findsNothing);
      handle.dispose();
    });

    testWidgets('a plugin\'s item hands every action to the site', (
      tester,
    ) async {
      final plugin = Reviewable(
        id: 5,
        type: 'ReviewableCategoryExpertSuggestion',
        status: ReviewableStatus.pending,
        bundles: [
          ReviewableActionBundle(
            id: '5-approve',
            actions: const [
              ReviewableAction(
                id: '5-approve',
                serverAction: 'approve_category_expert',
                label: 'Approve expert',
              ),
            ],
          ),
        ],
      );
      final performed = <String>[];
      var browser = 0;
      await tester.pumpWidget(
        detail(
          state: ReviewState(selectedId: 5, selected: plugin),
          onPerform: (_, action) => performed.add(action.serverAction),
          onBrowser: () => browser++,
        ),
      );
      await tester.tap(find.text('Approve expert'));
      await tester.pumpAndSettle();
      expect(browser, 1);
      expect(performed, isEmpty);
    });

    testWidgets('every action is held while one is being sent', (tester) async {
      final performed = <String>[];
      await tester.pumpWidget(
        detail(
          state: ReviewState(
            selectedId: 77,
            selected: item(77),
            performing: '77-post-agree_and_keep',
          ),
          onPerform: (_, action) => performed.add(action.serverAction),
        ),
      );
      await tester.tap(find.text('No').last, warnIfMissed: false);
      await tester.pump();
      expect(performed, isEmpty);
    });

    testWidgets('a conflict and a missing item are each said plainly', (
      tester,
    ) async {
      await tester.pumpWidget(
        detail(
          state: ReviewState(
            selectedId: 77,
            selected: item(77),
            notice: const ReviewConflict(),
          ),
        ),
      );
      expect(
        find.text(
          'Someone else acted on this item first. It now shows their result.',
        ),
        findsOneWidget,
      );

      var back = 0;
      await tester.pumpWidget(
        detail(
          state: ReviewState(
            selectedId: 5,
            selectedFailure: ReviewFailure.missing,
          ),
          onBack: () => back++,
        ),
      );
      expect(
        find.text('This item no longer exists or isn’t visible to you.'),
        findsOneWidget,
      );
      expect(find.byType(DSpinner), findsNothing);
      await tester.tap(find.text('Back to queue'));
      expect(back, 1);
    });
  });
}
