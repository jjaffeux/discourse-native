import 'dart:async';

import 'package:discourse_native/src/plugins/poll/poll_composer_editor.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_parser.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_sheet.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Completer<PollComposerSheetAction?>> openSheet(
    WidgetTester tester,
    PollComposerDraft draft, {
    TargetPlatform platform = TargetPlatform.android,
    bool isStaff = false,
    bool isPublished = false,
    int? voterCount,
    bool Function()? isCurrent,
  }) async {
    final result = Completer<PollComposerSheetAction?>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: platform),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result.complete(
                  await showPollComposerSheet(
                    context: context,
                    draft: draft,
                    maximumOptions: 20,
                    isStaff: isStaff,
                    isPublished: isPublished,
                    voterCount: voterCount,
                    isCurrent: isCurrent,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return result;
  }

  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
    description: 'TextField labelled $label',
  );

  Future<void> tapSheetAction(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('uses a modal on desktop', (tester) async {
    final draft = PollComposerDraft.newPoll(name: 'poll', defaultPublic: false);

    final desktopResult = await openSheet(
      tester,
      draft,
      platform: TargetPlatform.macOS,
    );
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(await desktopResult.future, isNull);
  });

  testWidgets('keeps the sheet on touch platforms', (tester) async {
    await openSheet(
      tester,
      PollComposerDraft.newPoll(name: 'poll', defaultPublic: false),
    );

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(PollComposerSheet), findsOneWidget);
  });

  testWidgets('creates a regular poll through the sheet', (tester) async {
    PollComposerSheetAction? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showPollComposerSheet(
                  context: context,
                  draft: PollComposerDraft.newPoll(
                    name: 'poll',
                    defaultPublic: true,
                  ),
                  maximumOptions: 20,
                  isStaff: false,
                  isPublished: false,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Add poll'), findsOneWidget);
    await tester.enterText(field('Title (optional)'), 'Lunch');
    await tester.enterText(field('Option 1'), 'Soup');
    await tester.enterText(field('Option 2'), 'Salad');
    await tapSheetAction(tester, 'Apply');

    expect(result?.type, PollComposerSheetActionType.apply);
    expect(result?.draft?.title, 'Lunch');
    expect(result?.draft?.options, ['Soup', 'Salad']);
    expect(result?.draft?.publicVoters, isTrue);
  });

  testWidgets('shows validation without closing the sheet', (tester) async {
    await openSheet(
      tester,
      PollComposerDraft.newPoll(name: 'poll', defaultPublic: false),
    );
    await tester.enterText(field('Option 1'), 'Same');
    await tester.enterText(field('Option 2'), 'Same');
    await tapSheetAction(tester, 'Apply');

    expect(find.text('Poll options must be unique.'), findsOneWidget);
    expect(find.text('Add poll'), findsOneWidget);
  });

  testWidgets('automatic close requires a date and time', (tester) async {
    await openSheet(
      tester,
      PollComposerDraft.newPoll(name: 'poll', defaultPublic: false),
    );
    await tester.enterText(field('Option 1'), 'A');
    await tester.enterText(field('Option 2'), 'B');
    final automaticClose = find.text('Automatic close');
    await tester.ensureVisible(automaticClose);
    await tester.pumpAndSettle();
    await tester.tap(automaticClose);
    await tester.pumpAndSettle();
    await tapSheetAction(tester, 'Apply');

    expect(find.text('Automatic close needs a date and time.'), findsOneWidget);
  });

  testWidgets('an untouched existing close value remains exact', (
    tester,
  ) async {
    const source =
        '[poll close=" 2026-08-30T18:00:00Z "]\n'
        '* A\n'
        '* B\n'
        '[/poll]';
    final result = await openSheet(
      tester,
      PollComposerDraft.fromBlock(parsePollComposerBlocks(source).single),
    );

    await tapSheetAction(tester, 'Apply');
    final action = await result.future;

    expect(action?.draft?.close, ' 2026-08-30T18:00:00Z ');
    expect(action?.draft?.serialize(), source);
  });

  testWidgets('edits and reorders a multiple-choice poll', (tester) async {
    final result = await openSheet(
      tester,
      PollComposerDraft.newPoll(name: 'poll', defaultPublic: false).copyWith(
        type: ComposerPollType.multiple,
        options: ['A', 'B', 'C'],
        minimum: 1,
        maximum: 2,
      ),
    );

    await tester.tap(find.byTooltip('Move option down').first);
    await tester.pump();
    final removeLast = find.byTooltip('Remove option').last;
    await tester.ensureVisible(removeLast);
    await tester.pumpAndSettle();
    await tester.tap(removeLast);
    await tester.pump();
    await tapSheetAction(tester, 'Apply');

    final action = await result.future;
    expect(action?.draft?.type, ComposerPollType.multiple);
    expect(action?.draft?.options, ['B', 'A']);
    expect(action?.draft?.minimum, 1);
    expect(action?.draft?.maximum, 2);
  });

  testWidgets('creates a number poll from its inclusive range fields', (
    tester,
  ) async {
    final result = await openSheet(
      tester,
      PollComposerDraft.newPoll(name: 'poll', defaultPublic: true).copyWith(
        type: ComposerPollType.number,
        minimum: 0,
        maximum: 10,
        step: 2,
      ),
    );

    await tester.enterText(field('Minimum'), '2');
    await tester.enterText(field('Maximum'), '8');
    await tester.enterText(field('Step'), '2');
    await tapSheetAction(tester, 'Apply');

    final action = await result.future;
    expect(action?.draft?.type, ComposerPollType.number);
    expect(action?.draft?.minimum, 2);
    expect(action?.draft?.maximum, 8);
    expect(action?.draft?.step, 2);
  });

  testWidgets('a stale composer is a safe no-op with an explanation', (
    tester,
  ) async {
    await openSheet(
      tester,
      PollComposerDraft.newPoll(name: 'poll', defaultPublic: false),
      isCurrent: () => false,
    );
    await tester.enterText(field('Option 1'), 'A');
    await tester.enterText(field('Option 2'), 'B');
    await tapSheetAction(tester, 'Apply');

    expect(
      find.text(
        'The composer changed while this poll was open. Nothing was changed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('ranked choice is locked and can escape to raw source', (
    tester,
  ) async {
    const source =
        '[poll type=ranked_choice]\n'
        '* A\n'
        '* B\n'
        '[/poll]';
    PollComposerSheetAction? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showPollComposerSheet(
                  context: context,
                  draft: PollComposerDraft.fromBlock(
                    parsePollComposerBlocks(source).single,
                  ),
                  maximumOptions: 20,
                  isStaff: false,
                  isPublished: false,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Ranked choice'), findsOneWidget);
    expect(
      find.textContaining('Ranked-choice polls keep their type'),
      findsOneWidget,
    );
    await tapSheetAction(tester, 'Edit as raw');
    expect(result?.type, PollComposerSheetActionType.editRaw);
  });

  testWidgets('published removal confirms and names the voter count', (
    tester,
  ) async {
    const source = '[poll]\n* A\n* B\n[/poll]';
    PollComposerSheetAction? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showPollComposerSheet(
                  context: context,
                  draft: PollComposerDraft.fromBlock(
                    parsePollComposerBlocks(source).single,
                  ),
                  maximumOptions: 20,
                  isStaff: false,
                  isPublished: true,
                  voterCount: 12,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tapSheetAction(tester, 'Remove');

    expect(find.textContaining('12 voters'), findsOneWidget);
    await tester.tap(find.text('Remove poll'));
    await tester.pumpAndSettle();
    expect(result?.type, PollComposerSheetActionType.remove);
  });
}
