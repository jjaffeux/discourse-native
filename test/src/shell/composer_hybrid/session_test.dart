import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/shell/composer_document/component.dart'
    as document;
import 'package:discourse_native/src/shell/composer_document/document.dart';
import 'package:discourse_native/src/shell/composer_document/interaction.dart';
import 'package:discourse_native/src/shell/composer_document/selection.dart';
import 'package:discourse_native/src/shell/composer_document/source.dart';
import 'package:discourse_native/src/shell/composer_hybrid/component_registration.dart';
import 'package:discourse_native/src/shell/composer_hybrid/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = PluginId('hybrid-test');
const _dateKind = ComposerSyntaxKind(owner: _owner, name: 'date');
const _pollKind = ComposerSyntaxKind(owner: _owner, name: 'poll');

void main() {
  testWidgets(
    'freezes heterogeneous registrations and preserves typed render actions',
    (tester) async {
      ComposerComponentInstance<_PollValue>? removedPoll;
      PluginId? dateBuilderOwner;
      PluginId? dateDescendantOwner;
      PluginId? dateLabelOwner;
      PluginId? pollActionOwner;
      final date = ComposerComponent<String>.inline(
        kind: _dateKind,
        find: _findDates,
        builder: (context, component) {
          dateBuilderOwner = PluginUiScope.maybeOwnerOf(context);
          return Builder(
            builder: (context) {
              dateDescendantOwner = PluginUiScope.maybeOwnerOf(context);
              return Text(
                'date ${component.value}',
                style: component.baseStyle,
              );
            },
          );
        },
        semanticLabel: (context, component) {
          dateLabelOwner = PluginUiScope.maybeOwnerOf(context);
          return 'Date ${component.value}';
        },
      );
      final poll = ComposerComponent<_PollValue>.block(
        kind: _pollKind,
        find: _findPolls,
        builder: (context, component) {
          return Text(
            'poll ${component.value.options.join(', ')}',
            style: component.baseStyle,
          );
        },
        semanticLabel: (context, component) {
          return 'Poll with ${component.value.options.length} choices';
        },
        onRemove: (context, editor, component) {
          pollActionOwner = PluginUiScope.maybeOwnerOf(context);
          removedPoll = component;
        },
      );
      final registrations = <ComposerHybridComponentRegistration>[
        ComposerHybridComponentRegistration.from(date),
        ComposerHybridComponentRegistration.from(poll),
      ];
      const markdown =
          'Before [date:2026-09-01] middle\n[poll:Tea|Coffee]\nafter';
      final session = ComposerHybridEditingSession(
        markdown: markdown,
        registrations: registrations,
      );
      addTearDown(session.dispose);
      registrations.clear();

      final matches = session.snapshot.projection.components;
      expect(matches, hasLength(2));
      expect(session.markdown, markdown);
      expect(session.snapshot.projection.reconstructedSource, markdown);
      expect(matches.first.source, '[date:2026-09-01]');
      expect(matches.last.source, '[poll:Tea|Coffee]');
      expect(matches.first.layout, document.ComposerComponentLayout.inline);
      expect(matches.last.layout, document.ComposerComponentLayout.block);

      final dateRenderer = session.rendererFor(matches.first.kind)!;
      final pollRenderer = session.rendererForSyntaxKind(_pollKind)!;
      late BuildContext actionContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              actionContext = context;
              return Column(
                children: [
                  dateRenderer.build(
                    context,
                    match: matches.first,
                    baseStyle: const TextStyle(fontSize: 16),
                    selected: true,
                    hovered: false,
                  ),
                  pollRenderer.build(
                    context,
                    match: matches.last,
                    baseStyle: const TextStyle(fontSize: 18),
                    selected: false,
                    hovered: true,
                  ),
                ],
              );
            },
          ),
        ),
      );

      expect(find.text('date 2026-09-01'), findsOneWidget);
      expect(find.text('poll Tea, Coffee'), findsOneWidget);
      expect(find.textContaining('[date:'), findsNothing);
      expect(find.textContaining('[poll:'), findsNothing);
      expect(dateBuilderOwner, _owner);
      expect(dateDescendantOwner, _owner);
      expect(
        dateRenderer.semanticLabel(actionContext, matches.first),
        'Date 2026-09-01',
      );
      expect(dateLabelOwner, _owner);
      expect(
        pollRenderer.semanticLabel(actionContext, matches.last),
        'Poll with 2 choices',
      );

      final pollActions = session.actionsForSyntaxKind(_pollKind)!;
      expect(pollActions.canEdit, isFalse);
      expect(pollActions.canRemove, isTrue);
      await pollActions.remove(actionContext, _FakeEditorHost(), matches.last);
      expect(pollActionOwner, _owner);
      expect(removedPoll?.source, '[poll:Tea|Coffee]');
      expect(removedPoll?.value.options, ['Tea', 'Coffee']);

      expect(
        () => dateRenderer.build(
          actionContext,
          match: matches.last,
          baseStyle: const TextStyle(),
          selected: false,
          hovered: false,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'dispatches atomic navigation and history with precise notifications',
    () {
      const markdown = 'a[date:x]b\n[poll:Tea|Coffee]\nz';
      final session = ComposerHybridEditingSession(
        markdown: markdown,
        registrations: [
          ComposerHybridComponentRegistration.from(
            const ComposerComponent<String>.inline(
              kind: _dateKind,
              find: _findDates,
              builder: _unusedDateBuilder,
              semanticLabel: _unusedDateLabel,
            ),
          ),
          ComposerHybridComponentRegistration.from(
            const ComposerComponent<_PollValue>.block(
              kind: _pollKind,
              find: _findPolls,
              builder: _unusedPollBuilder,
              semanticLabel: _unusedPollLabel,
            ),
          ),
        ],
        selection: const ComposerCaretSelection(1),
      );
      addTearDown(session.dispose);
      var notifications = 0;
      session.addListener(() => notifications++);

      final passThrough = session.dispatch(
        const ComposerMoveIntent(ComposerMoveDirection.left),
      );
      expect(passThrough, isA<ComposerHybridPassThrough>());
      expect(notifications, 0);

      final unchanged = session.dispatch(
        const ComposerSelectIntent(anchor: 1, focus: 1),
      );
      expect(unchanged.handled, isTrue);
      expect(unchanged.changed, isFalse);
      expect(notifications, 0);

      session.dispatch(const ComposerMoveIntent(ComposerMoveDirection.right));
      expect(session.selection, isA<ComposerComponentSelection>());
      expect(notifications, 1);

      session.dispatch(const ComposerMoveIntent(ComposerMoveDirection.right));
      expect(session.selection, const ComposerCaretSelection(9));
      expect(notifications, 2);

      session.dispatch(const ComposerMoveIntent(ComposerMoveDirection.left));
      expect(session.selection, isA<ComposerComponentSelection>());
      expect(notifications, 3);

      final deleted = session.dispatch(
        const ComposerDeleteIntent(ComposerDeleteDirection.backward),
      );
      expect(deleted, isA<ComposerHybridTransactionHandled>());
      expect(deleted.changed, isTrue);
      expect(session.markdown, 'ab\n[poll:Tea|Coffee]\nz');
      expect(session.revision, const ComposerRevision(1));
      expect(session.selection, const ComposerCaretSelection(1));
      expect(session.canUndo, isTrue);
      expect(session.canRedo, isFalse);
      expect(notifications, 4);

      final stale = session.commit(
        ComposerTransaction(
          baseRevision: const ComposerRevision(0),
          edits: const [
            ComposerSourceEdit(
              range: ComposerSourceRange(0, 1),
              expectedSource: 'a',
              replacement: 'A',
            ),
          ],
          selectionAfter: const ComposerCaretSelection(1),
        ),
      );
      expect(stale, isA<ComposerCommitRejected>());
      expect(
        (stale as ComposerCommitRejected).failure.code,
        ComposerTransactionFailureCode.staleRevision,
      );
      expect(notifications, 4);

      final undone = session.undo();
      expect(undone?.source, markdown);
      expect(undone?.revision, const ComposerRevision(2));
      expect(undone?.selection, isA<ComposerComponentSelection>());
      expect(session.canRedo, isTrue);
      expect(notifications, 5);

      final redone = session.redo();
      expect(redone?.source, 'ab\n[poll:Tea|Coffee]\nz');
      expect(redone?.revision, const ComposerRevision(3));
      expect(redone?.selection, const ComposerCaretSelection(1));
      expect(notifications, 6);

      expect(session.redo(), isNull);
      expect(notifications, 6);
    },
  );

  testWidgets('retained matches are stale after edit and undo', (tester) async {
    var invocations = 0;
    final session = _actionSession((context, editor, component) {
      invocations += 1;
    });
    addTearDown(session.dispose);
    final context = await _pumpActionContext(tester);
    final retainedMatch = session.snapshot.projection.components.single;
    final retainedActions = session.actionsFor(retainedMatch.kind)!;
    expect(retainedActions.canEdit, isTrue);

    _editThenUndo(session);
    expect(session.markdown, 'a[date:x]b');
    expect(session.revision, const ComposerRevision(2));
    expect(retainedActions.canEdit, isFalse);

    await retainedActions.edit(context, _RecordingEditorHost(), retainedMatch);

    expect(invocations, 0);
  });

  testWidgets(
    'an asynchronously retained lease rejects every mutation after edit and undo',
    (tester) async {
      ComposerEditorHost? retainedLease;
      final session = _actionSession((context, editor, component) async {
        await Future<void>.value();
        retainedLease = editor;
      });
      addTearDown(session.dispose);
      final context = await _pumpActionContext(tester);
      final match = session.snapshot.projection.components.single;
      final delegate = _RecordingEditorHost();

      await session.actionsFor(match.kind)!.edit(context, delegate, match);
      expect(retainedLease, isNotNull);
      expect(retainedLease!.isCurrent, isTrue);

      _editThenUndo(session);
      final expected = delegate.value;
      expect(retainedLease!.isCurrent, isFalse);
      expect(
        retainedLease!.commit(
          expectedValue: expected,
          value: expected.copyWith(text: 'commit'),
        ),
        isFalse,
      );
      expect(
        retainedLease!.commitText(
          expectedText: expected.text,
          value: expected.copyWith(text: 'commitText'),
        ),
        isFalse,
      );
      expect(
        retainedLease!.insertBlock(
          expectedValue: expected,
          markdown: '\nblock',
        ),
        isFalse,
      );
      expect(delegate.commitCalls, 0);
      expect(delegate.commitTextCalls, 0);
      expect(delegate.insertBlockCalls, 0);
      retainedLease!.requestFocus();
      expect(delegate.requestFocusCalls, 0);
      expect(delegate.value, expected);
    },
  );

  testWidgets('a current action gets one successful host mutation', (
    tester,
  ) async {
    bool? currentBefore;
    bool? firstCommit;
    bool? currentAfter;
    bool? secondCommit;
    late ComposerHybridEditingSession session;
    session = _actionSession((context, editor, component) {
      currentBefore = editor.isCurrent;
      final expected = editor.value;
      firstCommit = editor.commit(
        expectedValue: expected,
        value: expected.copyWith(text: 'changed'),
      );
      currentAfter = editor.isCurrent;
      secondCommit = editor.commitText(
        expectedText: 'changed',
        value: expected.copyWith(text: 'changed again'),
      );
      editor.requestFocus();
    });
    addTearDown(session.dispose);
    final context = await _pumpActionContext(tester);
    final match = session.snapshot.projection.components.single;
    final delegate = _RecordingEditorHost(
      onSuccessfulMutation: () =>
          _replaceLeadingCharacter(session, expected: 'a', replacement: 'A'),
    );

    await session.actionsFor(match.kind)!.edit(context, delegate, match);

    expect(currentBefore, isTrue);
    expect(firstCommit, isTrue);
    expect(currentAfter, isFalse);
    expect(secondCommit, isFalse);
    expect(delegate.commitCalls, 1);
    expect(delegate.commitTextCalls, 0);
    expect(delegate.requestFocusCalls, 1);
    expect(delegate.value.text, 'changed');
    expect(session.markdown, 'A[date:x]b');
    expect(session.revision, const ComposerRevision(1));
  });

  testWidgets('a later source edit invalidates post-commit focus restoration', (
    tester,
  ) async {
    ComposerEditorHost? retainedLease;
    late ComposerHybridEditingSession session;
    session = _actionSession((context, editor, component) {
      retainedLease = editor;
      final expected = editor.value;
      expect(
        editor.commit(
          expectedValue: expected,
          value: expected.copyWith(text: 'changed'),
        ),
        isTrue,
      );
    });
    addTearDown(session.dispose);
    final context = await _pumpActionContext(tester);
    final match = session.snapshot.projection.components.single;
    final delegate = _RecordingEditorHost(
      onSuccessfulMutation: () =>
          _replaceLeadingCharacter(session, expected: 'a', replacement: 'A'),
    );

    await session.actionsFor(match.kind)!.edit(context, delegate, match);
    _replaceLeadingCharacter(session, expected: 'A', replacement: 'B');
    retainedLease!.requestFocus();

    expect(session.revision, const ComposerRevision(2));
    expect(delegate.requestFocusCalls, 0);
  });

  testWidgets('selection-only session changes preserve an action lease', (
    tester,
  ) async {
    bool? committed;
    final session = _actionSession((context, editor, component) {
      final expected = editor.value;
      committed = editor.commit(
        expectedValue: expected,
        value: expected.copyWith(text: 'selected action'),
      );
    });
    addTearDown(session.dispose);
    final context = await _pumpActionContext(tester);
    final match = session.snapshot.projection.components.single;
    final actions = session.actionsFor(match.kind)!;
    final revisionBefore = session.revision;
    final selectionResult = session.dispatch(
      const ComposerSelectIntent(anchor: 0, focus: 0),
    );
    expect(selectionResult.changed, isTrue);
    expect(session.revision, revisionBefore);
    final delegate = _RecordingEditorHost();

    await actions.edit(context, delegate, match);

    expect(committed, isTrue);
    expect(delegate.commitCalls, 1);
    expect(delegate.value.text, 'selected action');
  });
}

ComposerHybridEditingSession _actionSession(
  ComposerComponentAction<String> action,
) {
  return ComposerHybridEditingSession(
    markdown: 'a[date:x]b',
    registrations: [
      ComposerHybridComponentRegistration.from(
        ComposerComponent<String>.inline(
          kind: _dateKind,
          find: _findDates,
          builder: _unusedDateBuilder,
          semanticLabel: _unusedDateLabel,
          onEdit: action,
        ),
      ),
    ],
  );
}

Future<BuildContext> _pumpActionContext(WidgetTester tester) async {
  late BuildContext result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          result = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return result;
}

void _editThenUndo(ComposerHybridEditingSession session) {
  _replaceLeadingCharacter(session, expected: 'a', replacement: 'A');
  expect(session.undo(), isNotNull);
}

void _replaceLeadingCharacter(
  ComposerHybridEditingSession session, {
  required String expected,
  required String replacement,
}) {
  final committed = session.commit(
    ComposerTransaction(
      baseRevision: session.revision,
      edits: [
        ComposerSourceEdit(
          range: const ComposerSourceRange(0, 1),
          expectedSource: expected,
          replacement: replacement,
        ),
      ],
      selectionAfter: const ComposerCaretSelection(1),
    ),
  );
  expect(committed, isA<ComposerCommitApplied>());
}

Iterable<ComposerComponentCandidate<String>> _findDates(String markdown) {
  return RegExp(r'\[date:([^\]]+)\]').allMatches(markdown).map((match) {
    return ComposerComponentCandidate<String>(
      range: TextRange(start: match.start, end: match.end),
      value: match.group(1)!,
    );
  });
}

Iterable<ComposerComponentCandidate<_PollValue>> _findPolls(String markdown) {
  return RegExp(r'\[poll:([^\]]+)\]').allMatches(markdown).map((match) {
    return ComposerComponentCandidate<_PollValue>(
      range: TextRange(start: match.start, end: match.end),
      value: _PollValue(match.group(1)!.split('|')),
    );
  });
}

Widget _unusedDateBuilder(
  BuildContext context,
  ComposerComponentRenderContext<String> component,
) {
  return Text(component.value);
}

String _unusedDateLabel(
  BuildContext context,
  ComposerComponentPresentation<String> component,
) {
  return component.value;
}

Widget _unusedPollBuilder(
  BuildContext context,
  ComposerComponentRenderContext<_PollValue> component,
) {
  return Text(component.value.options.join(', '));
}

String _unusedPollLabel(
  BuildContext context,
  ComposerComponentPresentation<_PollValue> component,
) {
  return '${component.value.options.length} choices';
}

final class _PollValue {
  const _PollValue(this.options);

  final List<String> options;
}

final class _RecordingEditorHost implements ComposerEditorHost {
  _RecordingEditorHost({this.onSuccessfulMutation});

  final void Function()? onSuccessfulMutation;
  TextEditingValue _value = const TextEditingValue(
    text: 'host',
    selection: TextSelection.collapsed(offset: 4),
  );
  bool current = true;
  int commitCalls = 0;
  int commitTextCalls = 0;
  int insertBlockCalls = 0;
  int requestFocusCalls = 0;

  @override
  TextEditingValue get value => _value;

  @override
  bool get isCurrent => current;

  @override
  bool commit({
    required TextEditingValue expectedValue,
    required TextEditingValue value,
  }) {
    commitCalls += 1;
    if (!current || expectedValue != _value) return false;
    _value = value;
    onSuccessfulMutation?.call();
    return true;
  }

  @override
  bool commitText({
    required String expectedText,
    required TextEditingValue value,
  }) {
    commitTextCalls += 1;
    if (!current || expectedText != _value.text) return false;
    _value = value;
    onSuccessfulMutation?.call();
    return true;
  }

  @override
  bool insertBlock({
    required TextEditingValue expectedValue,
    required String markdown,
  }) {
    insertBlockCalls += 1;
    if (!current || expectedValue != _value) return false;
    final nextText = '${_value.text}$markdown';
    _value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    onSuccessfulMutation?.call();
    return true;
  }

  @override
  bool get isEdit => false;

  @override
  bool get isPluginTarget => false;

  @override
  bool get loadingBody => false;

  @override
  String? get originalRaw => null;

  @override
  PluginData get siteSettings => PluginData.none;

  @override
  String get siteUrl => 'https://example.test';

  @override
  T? syntaxPolicy<T extends ComposerSyntaxPolicy>(ComposerSyntaxKind kind) {
    return null;
  }

  @override
  void requestFocus() {
    requestFocusCalls += 1;
  }
}

final class _FakeEditorHost implements ComposerEditorHost {
  @override
  bool commit({
    required TextEditingValue expectedValue,
    required TextEditingValue value,
  }) {
    return false;
  }

  @override
  bool commitText({
    required String expectedText,
    required TextEditingValue value,
  }) {
    return false;
  }

  @override
  bool get isCurrent => true;

  @override
  bool get isEdit => false;

  @override
  bool get isPluginTarget => false;

  @override
  bool get loadingBody => false;

  @override
  String? get originalRaw => null;

  @override
  void requestFocus() {}

  @override
  PluginData get siteSettings => PluginData.none;

  @override
  String get siteUrl => 'https://example.test';

  @override
  T? syntaxPolicy<T extends ComposerSyntaxPolicy>(ComposerSyntaxKind kind) {
    return null;
  }

  @override
  TextEditingValue get value => TextEditingValue.empty;

  @override
  bool insertBlock({
    required TextEditingValue expectedValue,
    required String markdown,
  }) {
    return false;
  }
}
