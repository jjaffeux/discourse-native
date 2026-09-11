import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';

import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/assign/assign_services.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/plugins/assign/assignment_sheet.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/button_surface.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _sam = AssignmentUser(id: 7, username: 'sam', name: 'Sam Example');
const _support = AssignmentGroup(
  id: 4,
  name: 'support',
  fullName: 'Support team',
);

FilledButton _materialButton(WidgetTester tester, Key key) =>
    tester.widget<FilledButton>(
      find.descendant(of: find.byKey(key), matching: find.byType(FilledButton)),
    );

void main() {
  group('editor presentation', () {
    testWidgets('uses a focused Native dialog on desktop', (tester) async {
      final controller = await _openAssignmentEditor(
        tester,
        platform: TargetPlatform.macOS,
      );
      addTearDown(controller.dispose);

      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      final picker = find.byKey(const Key('assignment-dialog'));
      expect(picker, findsOneWidget);
      expect(tester.getSize(picker).width, 480);
      expect(find.byType(DDrawerContent), findsNothing);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(
        find.descendant(
          of: picker,
          matching: find.byKey(const Key('assignment-search')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: picker,
          matching: find.byKey(const Key('assignment-note-toggle')),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('assignment-close')));
      await tester.pumpAndSettle();
      expect(picker, findsNothing);
    });

    testWidgets('uses a Native drawer without opening the keyboard on mobile', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await _openAssignmentEditor(tester);
      addTearDown(controller.dispose);

      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(DDrawerContent), findsOneWidget);
      expect(find.text('Assign topic'), findsOneWidget);
      expect(find.byType(DDrawerSwipeHandle), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        isFalse,
      );
      await tester.drag(find.byType(DDrawerSwipeHandle), const Offset(0, 650));
      await tester.pumpAndSettle();
      expect(find.byType(AssignmentEditor), findsNothing);
    });

    testWidgets('uses a boxed note textarea and an icon-free danger action', (
      tester,
    ) async {
      await tester.pumpWidget(
        _editor(
          suggestions: AssignmentSuggestions(users: const [_sam]),
          existing: const Assignment(assignee: _sam),
          remove: () async => null,
        ),
      );
      await tester.pumpAndSettle();

      await _showNote(tester);
      final note = tester.widget<DTextarea>(
        find.byKey(const Key('assignment-note')),
      );
      expect(note.minLines, 3);
      expect(note.labelText, isNull);
      expect(note.hintText, 'Add context for the assignee…');

      final unassignFinder = find.byKey(const Key('assignment-unassign'));
      final destructive = DTokens.of(
        tester.element(unassignFinder),
      ).destructive;
      expect(
        buttonSurface(tester, of: unassignFinder).color,
        destructive.withValues(alpha: destructive.a * .1),
      );
      expect(
        find.descendant(of: unassignFinder, matching: find.byType(DIcon)),
        findsNothing,
      );
    });

    testWidgets(
      'keeps search focus and text when the keyboard moves the header',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final controller = await _openAssignmentEditor(tester);
        addTearDown(controller.dispose);
        final search = find.byKey(const Key('assignment-search'));
        await tester.enterText(search, 'sam');
        await tester.pumpAndSettle();
        final searchFocus = tester.widget<DInputGroupInput>(search).focusNode!;
        expect(searchFocus.hasFocus, isTrue);

        tester.view.viewInsets = const FakeViewPadding(bottom: 334);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.widget<DInputGroupInput>(search).controller!.text, 'sam');
        expect(searchFocus.hasFocus, isTrue);
      },
    );

    testWidgets('keeps the narrow large-text form usable with the keyboard', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var keyboardInset = 0.0;
      late StateSetter updateMedia;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => StatefulBuilder(
            builder: (context, setState) {
              updateMedia = setState;
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  viewInsets: EdgeInsets.only(bottom: keyboardInset),
                  disableAnimations: true,
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: child!,
                ),
              );
            },
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => DButton(
                label: const Text('Open'),
                onPressed: () => showDDrawer<void>(
                  context: context,
                  showSwipeHandle: true,
                  requestInitialFocus: false,
                  builder: (_, modal) => AssignmentEditor(
                    drawer: true,
                    title: 'Edit topic assignment',
                    existing: const Assignment(assignee: _sam, note: 'Draft'),
                    statusesEnabled: true,
                    statuses: const ['Open', 'Waiting for another team'],
                    loadSuggestions: () async => AssignmentSuggestions(
                      users: const [_sam],
                      assignAllowedForGroups: const ['support'],
                    ),
                    searchAssignees: (_, _) async => const [],
                    save: (_, {note, status}) async => 'Please try again.',
                    remove: () async => null,
                    onCancel: modal.close,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      updateMedia(() => keyboardInset = 220);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('assignment-note')));
      await tester.enterText(find.byKey(const Key('assignment-note')), 'Kept');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      updateMedia(() => keyboardInset = 0);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Waiting for another team'));
      await tester.tap(find.text('Waiting for another team'));
      await tester.tap(find.byKey(const Key('assignment-save')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Please try again.').hitTestable(), findsOneWidget);
      expect(
        tester
            .widget<DTextarea>(find.byKey(const Key('assignment-note')))
            .controller!
            .text,
        'Kept',
      );
      expect(
        find.byKey(const Key('assignment-cancel')).hitTestable(),
        findsOneWidget,
      );
    });
  });

  group('assignment submission', () {
    testWidgets(
      'saves the selected assignee with a trimmed note and configured status',
      (tester) async {
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
        await _showNote(tester);
        await tester.enterText(
          find.byKey(const Key('assignment-note')),
          '  Needs triage  ',
        );
        await tester.ensureVisible(find.text('In progress'));
        await tester.tap(find.text('In progress').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('assignment-save')));
        await tester.pumpAndSettle();

        expect(savedAssignee, const AssignmentGroup(name: 'support'));
        expect(savedNote, 'Needs triage');
        expect(savedStatus, 'In progress');
        expect(completed, isTrue);
      },
    );

    testWidgets('keeps selection staged until Save', (tester) async {
      var saves = 0;

      await tester.pumpWidget(
        _editor(
          suggestions: AssignmentSuggestions(users: const [_sam]),
          save: (assignee, {note, status}) async {
            saves++;
            return null;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('assignment-assignee-user:sam')));
      await tester.pump();
      expect(saves, 0);

      await tester.tap(find.byKey(const Key('assignment-save')));
      await tester.pumpAndSettle();
      expect(saves, 1);
    });

    testWidgets('clears an existing note when only whitespace is saved', (
      tester,
    ) async {
      String? savedNote = 'not saved';

      await tester.pumpWidget(
        _editor(
          suggestions: AssignmentSuggestions(users: const [_sam]),
          existing: const Assignment(assignee: _sam, note: 'Held note'),
          save: (assignee, {note, status}) async {
            savedNote = note;
            return null;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('assignment-note')), '   ');
      await tester.tap(find.byKey(const Key('assignment-save')));
      await tester.pumpAndSettle();

      expect(savedNote, isNull);
    });
  });

  group('assignee discovery', () {
    testWidgets('retains a selected assignee outside empty search results', (
      tester,
    ) async {
      AssignmentAssignee? saved;
      await tester.pumpWidget(
        _editor(
          suggestions: AssignmentSuggestions(users: const [_sam]),
          searchDebounce: Duration.zero,
          save: (assignee, {note, status}) async {
            saved = assignee;
            return null;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assignment-assignee-user:sam')));
      await tester.enterText(
        find.byKey(const Key('assignment-search')),
        'nobody',
      );
      await tester.pumpAndSettle();
      expect(find.text('No matching users or groups.'), findsOneWidget);
      expect(find.text('Selected: @sam'), findsOneWidget);
      expect(find.text('Assign to @sam'), findsOneWidget);
      await tester.tap(find.byKey(const Key('assignment-save')));
      await tester.pumpAndSettle();
      expect(saved, _sam);
    });

    testWidgets(
      'retries a failed search without clearing the selected assignee',
      (tester) async {
        var searches = 0;
        await tester.pumpWidget(
          _editor(
            suggestions: AssignmentSuggestions(users: const [_sam]),
            searchDebounce: Duration.zero,
            search: (_, term) async {
              searches++;
              if (searches == 1) throw Exception('Search unavailable');
              return const [_support];
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('assignment-assignee-user:sam')));
        await tester.enterText(
          find.byKey(const Key('assignment-search')),
          'support',
        );
        await tester.pumpAndSettle();
        final retry = find.byKey(const Key('assignment-retry-search'));
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(searches, 2);
        expect(find.text('Support team'), findsOneWidget);
        expect(find.text('Selected: @sam'), findsOneWidget);
        expect(find.byKey(const Key('assignment-error')), findsNothing);
      },
    );

    testWidgets(
      'queues a newer search behind the active response and publishes only its results',
      (tester) async {
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
          _materialButton(tester, const Key('assignment-save')).onPressed,
          isNotNull,
        );

        await tester.enterText(
          find.byKey(const Key('assignment-search')),
          'old',
        );
        await tester.pump();
        final staleChoice = tester.widget<DRadioGroup<String>>(
          find.ancestor(
            of: find.byKey(const Key('assignment-assignee-user:sam')),
            matching: find.byType(DRadioGroup<String>),
          ),
        );
        expect(staleChoice.enabled, isFalse);
        expect(
          _materialButton(tester, const Key('assignment-save')).onPressed,
          isNull,
        );
        await tester.enterText(
          find.byKey(const Key('assignment-search')),
          'new',
        );
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
          _materialButton(tester, const Key('assignment-save')).onPressed,
          isNotNull,
        );
      },
    );

    testWidgets('announces an empty asynchronous search result', (
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
          isSemantics(
            label:
                'No matching users or groups.\nTry a different name or username.',
            isLiveRegion: true,
          ),
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('offers an in-place retry after initial suggestions fail', (
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
      expect(
        find.byKey(const Key('assignment-retry-suggestions')),
        findsNothing,
      );
    });
  });

  group('assignment mutations', () {
    testWidgets('keeps the optional note through collapse and a failed save', (
      tester,
    ) async {
      var attempts = 0;
      String? savedNote;
      await tester.pumpWidget(
        _editor(
          suggestions: AssignmentSuggestions(users: const [_sam]),
          save: (assignee, {note, status}) async {
            attempts++;
            savedNote = note;
            return attempts == 1 ? 'Please retry' : null;
          },
        ),
      );
      await tester.pumpAndSettle();
      final note = find.byKey(const Key('assignment-note'));
      expect(note.hitTestable(), findsNothing);
      await _showNote(tester);
      await tester.enterText(note, 'A useful handoff');
      final toggle = find.byKey(const Key('assignment-note-toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(note.hitTestable(), findsNothing);
      await tester.ensureVisible(
        find.byKey(const Key('assignment-assignee-user:sam')),
      );
      await tester.tap(find.byKey(const Key('assignment-assignee-user:sam')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('assignment-save')));
      await tester.pumpAndSettle();
      expect(find.text('Please retry'), findsOneWidget);
      await _showNote(tester);
      expect(
        tester.widget<DTextarea>(note).controller!.text,
        'A useful handoff',
      );
      await tester.tap(find.byKey(const Key('assignment-save')));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(savedNote, 'A useful handoff');
    });

    testWidgets(
      'keep write errors inline and prevent duplicate pending saves',
      (tester) async {
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
        final button = _materialButton(tester, const Key('assignment-save'));
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
      },
    );

    testWidgets('keep unassign available and report an inline refusal', (
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
  });

  group('assignment accessibility', () {
    testWidgets('keeps visually hidden controls semantically tappable', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _editor(suggestions: AssignmentSuggestions(users: const [_sam])),
      );
      await tester.pumpAndSettle();

      final choiceSemantics = tester
          .getSemantics(find.byType(RawRadio<String>).first)
          .getSemanticsData();
      expect(choiceSemantics.hasAction(SemanticsAction.tap), isTrue);
      expect(
        choiceSemantics.flagsCollection.isInMutuallyExclusiveGroup,
        isTrue,
      );
      semantics.dispose();

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
  });

  group('assignment metadata', () {
    testWidgets(
      'shows configured statuses as radio choices with wrapping labels',
      (tester) async {
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

        final group = tester.widget<DRadioGroup<String>>(
          find.byKey(const Key('assignment-status')),
        );
        expect(group.groupValue, longStatus);
        expect(find.byType(DSelect<String>), findsNothing);
        expect(tester.widget<Text>(find.text(longStatus)).maxLines, isNull);
        expect(tester.takeException(), isNull);
      },
    );

    test('includes user and group identities in summaries', () {
      expect(
        assignmentSummary(const Assignment(assignee: _sam), 'Topic'),
        'Topic assigned to Sam Example, user @sam',
      );
      expect(
        assignmentSummary(const Assignment(assignee: _support), 'Post #2'),
        'Post #2 assigned to Support team, group @support',
      );
    });

    testWidgets(
      'preserves an existing status while site settings are unknown',
      (tester) async {
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
      },
    );

    testWidgets('preserves an existing status absent from advertised values', (
      tester,
    ) async {
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

      final group = tester.widget<DRadioGroup<String>>(
        find.byKey(const Key('assignment-status')),
      );
      expect(group.groupValue, 'Waiting on legacy review');
      expect(
        find.descendant(
          of: find.byKey(const Key('assignment-status')),
          matching: find.text('Waiting on legacy review'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('assignment-save')));
      await tester.pumpAndSettle();

      expect(savedStatus, 'Waiting on legacy review');
    });
  });
}

Future<void> _showNote(WidgetTester tester) async {
  final toggle = find.byKey(const Key('assignment-note-toggle'));
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('assignment-note')));
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
    plugins: installedPlugins,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark.copyWith(platform: platform),
      home: ShellScope(
        controller: controller,
        child: PluginScope(
          session: controller.pluginSession,
          registry: installedPlugins.registry,
          child: PluginUiScope.own(
            assignPluginId,
            Scaffold(
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
