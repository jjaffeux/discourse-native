import 'dart:async';

import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/plugins/assign/assignment_sheet.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/shell_sheet.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _sam = AssignmentUser(id: 7, username: 'sam', name: 'Sam Example');
const _support = AssignmentGroup(
  id: 4,
  name: 'support',
  fullName: 'Support team',
);

void main() {
  testWidgets('uses a modal on desktop', (tester) async {
    final controller = await _openAssignmentEditor(
      tester,
      platform: TargetPlatform.macOS,
    );
    addTearDown(controller.dispose);

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Assign topic'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('keeps the bottom sheet on touch platforms', (tester) async {
    final controller = await _openAssignmentEditor(tester);
    addTearDown(controller.dispose);

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Assign topic'), findsOneWidget);
  });

  testWidgets('saves one selected assignee with note and configured status', (
    tester,
  ) async {
    AssignmentAssignee? savedAssignee;
    String? savedNote;
    String? savedStatus;
    var completed = false;

    await tester.pumpWidget(
      _editor(
        suggestions: AssignmentSuggestions(
          users: const [_sam],
          assignAllowedForGroups: const ['support'],
        ),
        statusesEnabled: true,
        statuses: const ['New', 'In progress'],
        save: (assignee, {note, status}) async {
          savedAssignee = assignee;
          savedNote = note;
          savedStatus = status;
          return null;
        },
        onComplete: () => completed = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('assignment-assignee-group:support')),
    );
    await tester.enterText(
      find.byKey(const Key('assignment-note')),
      '  Needs triage  ',
    );
    await tester.tap(find.byKey(const Key('assignment-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In progress').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assignment-save')));
    await tester.pumpAndSettle();

    expect(savedAssignee?.isGroup, isTrue);
    expect(savedAssignee?.groupName, _support.groupName);
    expect(savedNote, 'Needs triage');
    expect(savedStatus, 'In progress');
    expect(completed, isTrue);
  });

  testWidgets('a newer search waits for the active response and owns results', (
    tester,
  ) async {
    final oldResult = Completer<List<AssignmentAssignee>>();
    final newResult = Completer<List<AssignmentAssignee>>();
    final terms = <String>[];

    await tester.pumpWidget(
      _editor(
        suggestions: AssignmentSuggestions(users: const [_sam]),
        searchDebounce: Duration.zero,
        search: (_, term) {
          terms.add(term);
          return term == 'old' ? oldResult.future : newResult.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assignment-assignee-user:sam')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('assignment-save')))
          .onPressed,
      isNotNull,
    );

    await tester.enterText(find.byKey(const Key('assignment-search')), 'old');
    await tester.pump();
    final staleChoice = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const Key('assignment-assignee-user:sam')),
        matching: find.byType(ListTile),
      ),
    );
    expect(staleChoice.enabled, isFalse);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('assignment-save')))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('assignment-search')), 'new');
    await tester.pump();
    expect(terms, ['old']);

    oldResult.complete(const [
      AssignmentUser(username: 'old-user', name: 'Old result'),
    ]);
    await tester.pump();
    expect(terms, ['old', 'new']);
    newResult.complete(const [
      AssignmentUser(username: 'new-user', name: 'New result'),
    ]);
    await tester.pump();
    expect(find.text('New result'), findsOneWidget);
    expect(find.text('Old result'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('assignment-save')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('an empty asynchronous search result is announced', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _editor(
          suggestions: AssignmentSuggestions(users: const [_sam]),
          searchDebounce: Duration.zero,
          search: (_, _) async => const <AssignmentAssignee>[],
        ),
      );
      await tester.pumpAndSettle();

      final search = find.byKey(const Key('assignment-search'));
      await tester.tap(search);
      await tester.enterText(search, 'nobody');
      await tester.pumpAndSettle();

      final editable = tester.widget<EditableText>(
        find.descendant(of: search, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);

      final empty = find.byKey(const Key('assignment-empty-results'));
      expect(
        tester.getSemantics(empty),
        isSemantics(label: 'No matching users or groups.', isLiveRegion: true),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('write errors stay inline and a pending write cannot duplicate', (
    tester,
  ) async {
    final result = Completer<String?>();
    var calls = 0;

    await tester.pumpWidget(
      _editor(
        suggestions: AssignmentSuggestions(users: const [_sam]),
        save: (assignee, {note, status}) {
          calls++;
          return result.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assignment-assignee-user:sam')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('assignment-save')));
    await tester.tap(find.byKey(const Key('assignment-save')));
    await tester.pump();

    expect(calls, 1);
    expect(
      tester
          .widget<PopScope>(
            find.descendant(
              of: find.byType(AssignmentEditor),
              matching: find.byType(PopScope),
            ),
          )
          .canPop,
      isFalse,
    );
    result.complete('The assignment could not be saved.');
    await tester.pumpAndSettle();

    expect(find.text('The assignment could not be saved.'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('assignment-save')),
    );
    expect(button.onPressed, isNotNull);
    expect(
      tester
          .widget<PopScope>(
            find.descendant(
              of: find.byType(AssignmentEditor),
              matching: find.byType(PopScope),
            ),
          )
          .canPop,
      isTrue,
    );
  });

  testWidgets('failed initial suggestions can be retried in place', (
    tester,
  ) async {
    var calls = 0;

    await tester.pumpWidget(
      _editor(
        suggestions: AssignmentSuggestions(users: const [_sam]),
        loadSuggestions: () async {
          calls++;
          if (calls == 1) throw Exception('Suggestions are unavailable.');
          return AssignmentSuggestions(users: const [_sam]);
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Suggestions are unavailable.'), findsOneWidget);
    expect(
      find.byKey(const Key('assignment-retry-suggestions')),
      findsOneWidget,
    );
    expect(find.text('No matching users or groups.'), findsNothing);

    await tester.tap(find.byKey(const Key('assignment-retry-suggestions')));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Sam Example'), findsOneWidget);
    expect(find.byKey(const Key('assignment-retry-suggestions')), findsNothing);
  });

  testWidgets('hidden visual controls retain semantic tap actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _editor(suggestions: AssignmentSuggestions(users: const [_sam])),
    );
    await tester.pumpAndSettle();

    final choiceSemantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const Key('assignment-assignee-user:sam')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(choiceSemantics.properties.onTap, isNotNull);

    var edited = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AssignmentDetailRow(
            key: const Key('assignment-detail-row'),
            assignment: const Assignment(assignee: _sam),
            targetLabel: 'Topic',
            onTap: () => edited = true,
          ),
        ),
      ),
    );
    final detailSemantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const Key('assignment-detail-row')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(detailSemantics.properties.onTap, isNotNull);
    detailSemantics.properties.onTap!();
    expect(edited, isTrue);
  });

  testWidgets('status picker expands and ellipsizes long configured values', (
    tester,
  ) async {
    const longStatus =
        'Waiting for a response from the external infrastructure team';
    await tester.pumpWidget(
      _editor(
        suggestions: AssignmentSuggestions(users: const [_sam]),
        statusesEnabled: true,
        statuses: const [longStatus, 'Done'],
      ),
    );
    await tester.pumpAndSettle();

    final dropdown = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const Key('assignment-status')),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    expect(dropdown.isExpanded, isTrue);
    final label = tester.widget<Text>(find.text(longStatus).first);
    expect(label.maxLines, 1);
    expect(label.overflow, TextOverflow.ellipsis);
  });

  testWidgets('shell sheet reserves the mobile keyboard inset', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => unawaited(
                showShellSheet<void>(
                  context: context,
                  title: 'Keyboard test',
                  builder: (_) => const TextField(),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();

    final inset = tester.widget<AnimatedPadding>(
      find.byKey(const ValueKey('shell-sheet-keyboard-inset')),
    );
    expect(inset.padding, const EdgeInsets.only(bottom: 280));
  });

  test('assignment summaries include user and group identities', () {
    expect(
      assignmentSummary(const Assignment(assignee: _sam), 'Topic'),
      contains('user @sam'),
    );
    expect(
      assignmentSummary(const Assignment(assignee: _support), 'Post #2'),
      contains('group @support'),
    );
  });

  testWidgets('preserves an existing status while site settings are unknown', (
    tester,
  ) async {
    String? savedStatus;
    const existing = Assignment(
      assignee: _sam,
      note: 'Held note',
      status: 'Done',
    );

    await tester.pumpWidget(
      _editor(
        suggestions: AssignmentSuggestions(users: const [_sam]),
        existing: existing,
        save: (assignee, {note, status}) async {
          savedStatus = status;
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assignment-save')));
    await tester.pumpAndSettle();

    expect(savedStatus, 'Done');
    expect(find.byKey(const Key('assignment-status')), findsNothing);
  });

  testWidgets(
    'preserves an existing status missing from cached advertised statuses',
    (tester) async {
      String? savedStatus;
      const existing = Assignment(
        assignee: _sam,
        status: 'Waiting on legacy review',
      );

      await tester.pumpWidget(
        _editor(
          suggestions: AssignmentSuggestions(users: const [_sam]),
          existing: existing,
          statusesEnabled: true,
          statuses: const ['New', 'Done'],
          save: (assignee, {note, status}) async {
            savedStatus = status;
            return null;
          },
        ),
      );
      await tester.pumpAndSettle();

      final dropdown = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byKey(const Key('assignment-status')),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(dropdown.value, 'Waiting on legacy review');
      expect(
        dropdown.items?.map((item) => item.value),
        contains('Waiting on legacy review'),
      );

      await tester.tap(find.byKey(const Key('assignment-save')));
      await tester.pumpAndSettle();

      expect(savedStatus, 'Waiting on legacy review');
    },
  );

  testWidgets('unassign stays available and reports an inline refusal', (
    tester,
  ) async {
    var calls = 0;

    await tester.pumpWidget(
      _editor(
        suggestions: AssignmentSuggestions(users: const [_sam]),
        existing: const Assignment(assignee: _sam),
        remove: () async {
          calls++;
          return 'This assignment cannot be removed.';
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assignment-unassign')));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('This assignment cannot be removed.'), findsOneWidget);
  });
}

Future<ShellController> _openAssignmentEditor(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.android,
}) async {
  final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
  final controller = ShellController(
    instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
    api: FakeDiscourseApi(),
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark.copyWith(platform: platform),
      home: ShellScope(
        controller: controller,
        child: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => unawaited(
                showAssignmentEditor(
                  context: context,
                  siteUrl: _site,
                  target: const AssignmentTarget.topic(7),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return controller;
}

Widget _editor({
  required AssignmentSuggestions suggestions,
  Future<AssignmentSuggestions> Function()? loadSuggestions,
  Future<List<AssignmentAssignee>> Function(AssignmentSuggestions, String)?
  search,
  Future<String?> Function(
    AssignmentAssignee assignee, {
    String? note,
    String? status,
  })?
  save,
  Future<String?> Function()? remove,
  Assignment? existing,
  bool statusesEnabled = false,
  List<String> statuses = const [],
  VoidCallback? onComplete,
  Duration searchDebounce = const Duration(milliseconds: 300),
}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: SingleChildScrollView(
      child: AssignmentEditor(
        loadSuggestions: loadSuggestions ?? () async => suggestions,
        searchAssignees: search ?? (_, _) async => const <AssignmentAssignee>[],
        save: save ?? (assignee, {note, status}) async => null,
        remove: remove,
        existing: existing,
        statusesEnabled: statusesEnabled,
        statuses: statuses,
        onComplete: onComplete,
        searchDebounce: searchDebounce,
      ),
    ),
  ),
);
