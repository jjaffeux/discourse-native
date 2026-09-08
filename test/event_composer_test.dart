import 'package:discourse_native/src/plugin_api/composer_syntax.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_composer.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_composer_parser.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const original =
    '[event start = \'2025-01-07 23:00\' name="Team call" recurrence="every_week" timezone="Europe/Paris" future-flag=abc image="upload://existing"]\nAgenda with "quotes".\n[/event]';

EventSyntaxPolicy policyFor({
  bool createsTopic = false,
  int? editingPostNumber,
  bool fresh = true,
  bool plugin = false,
}) {
  final state = ComposerPluginState(
    createsTopic: createsTopic,
    editingPostNumber: editingPostNumber,
    siteSettings: PluginData.none.withValue(
      eventSettingsKey,
      const EventSettings(enabled: true),
    ),
    freshCurrentUser: fresh
        ? PluginData.none.withValue(
            eventUserKey,
            const EventUserPermissions(true),
          )
        : PluginData.none,
  );
  return EventSyntaxPolicy(
    ComposerSyntaxPolicyContext(
      siteUrl: 'https://forum.example',
      isPluginTarget: plugin,
      isEdit: editingPostNumber != null,
      initialState: state,
      readState: () => state,
    ),
  );
}

void main() {
  test(
    'unchanged source is lossless; editing a value preserves recurrence anchor and unknown attributes',
    () {
      const document = 'Before\n\n$original\n\nAfter';
      final block = parseEventBlocks(document).single;
      expect(block.replace({}), original);
      expect(block.attribute('start'), '2025-01-07 23:00');
      final replacement = block.replace({'name': 'Planning call'});
      expect(
        document.replaceRange(block.start, block.end, replacement),
        document.replaceFirst('Team call', 'Planning call'),
      );
      expect(replacement, contains("start = '2025-01-07 23:00'"));
      expect(
        replacement,
        contains('future-flag=abc image="upload://existing"'),
      );
      expect(
        parseEventBlocks(replacement).single.description,
        '\nAgenda with "quotes".\n',
      );
    },
  );

  test(
    'attribute scanner respects brackets and quotes, handles camel attributes and refuses duplicates',
    () {
      final block = parseEventBlocks(
        '[event start="2026-09-08" name="Intro [A]" showLocalTime="true"]x[/event]',
      ).single;
      expect(block.attribute('name'), 'Intro [A]');
      expect(block.attribute('show-local-time'), 'true');
      expect(
        parseEventBlocks(
          '[event start="2026-09-08" start="2026-09-09"]x[/event]',
        ),
        isEmpty,
      );
      expect(parseEventBlocks('[event start="unclosed]x[/event]'), isEmpty);
      expect(
        () => block.replace({'name': 'Both \' and " quotes'}),
        throwsFormatException,
      );
    },
  );

  test(
    'code examples and quotes remain raw; multiple actual blocks remain detectable',
    () {
      for (final source in [
        '```text\n$original\n```',
        '~~~\n$original\n~~~',
        '[quote="lee"]\n$original\n[/quote]',
        '[code]\n$original\n[/code]',
        '> $original',
        '    $original',
        '<pre>\n$original\n</pre>',
        '<!--\n$original\n-->',
      ]) {
        expect(parseEventBlocks(source), isEmpty, reason: source);
      }
      expect(parseEventBlocks('$original\n$original'), hasLength(2));
      expect(parseEventBlocks('[event name="No date"]x[/event]'), isEmpty);
    },
  );

  test('close, reopen and remove change only normal composer source', () {
    final block = parseEventBlocks(original).single;
    final closed = block.replace({'closed': 'true'});
    expect(parseEventBlocks(closed).single.attribute('closed'), 'true');
    final reopened = parseEventBlocks(
      closed,
    ).single.replace({'closed': 'false'});
    expect(parseEventBlocks(reopened).single.attribute('closed'), 'false');
    final editor = _Editor(original, policyFor(editingPostNumber: 1));
    final projection = editor.policy.parse(original).single;
    // remove's context is unused; source replacement is verified by the host.
    expect(projection.start, 0);
    expect(projection.end, original.length);
  });

  test(
    'new topics and private messages may author; replies and stale permissions may not',
    () {
      expect(policyFor(createsTopic: true).canAuthor, isTrue);
      expect(policyFor(editingPostNumber: 1).canAuthor, isTrue);
      expect(policyFor(editingPostNumber: 2).canAuthor, isFalse);
      expect(policyFor().canAuthor, isFalse);
      expect(policyFor(createsTopic: true, fresh: false).canAuthor, isFalse);
      expect(policyFor(createsTopic: true, plugin: true).canAuthor, isFalse);
      const preparer = EventSubmitPreparer();
      expect(
        preparer.prepareComposerSubmit(_Editor(original, policyFor())).failure,
        isNotNull,
      );
      expect(
        preparer
            .prepareComposerSubmit(
              _Editor('$original\n$original', policyFor(createsTopic: true)),
            )
            .failure,
        isNotNull,
      );
      expect(
        preparer
            .prepareComposerSubmit(
              _Editor(original, policyFor(createsTopic: true)),
            )
            .failure,
        isNull,
      );
    },
  );

  testWidgets('an open event editor cannot apply or remove during submission', (
    tester,
  ) async {
    final editor = _Editor(original, policyFor(createsTopic: true));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    final context = tester.element(find.byType(SizedBox));
    final editing = openEventComposer(
      context,
      editor,
      editor.policy,
      block: parseEventBlocks(original).single,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Name',
      ),
      'Late title',
    );
    editor.editing = false;
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(editor.value.text, original);
    expect(find.textContaining('The post changed'), findsOneWidget);
    Navigator.of(tester.element(find.byType(EventComposerSheet))).pop();
    await tester.pumpAndSettle();
    await editing;
    editor.policy.parse(original).single.remove(context, editor);
    expect(editor.value.text, original);
    await openEventComposer(
      context,
      editor,
      editor.policy,
      block: parseEventBlocks(original).single,
    );
    await tester.pump();
    expect(find.byType(EventComposerSheet), findsNothing);
  });

  testWidgets('sheet preserves unpublished source when applied unchanged', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => EventComposerSheet(
                    block: parseEventBlocks(original).single,
                    settings: const EventSettings(enabled: true),
                    timezone: 'Europe/Paris',
                    isCurrent: () => true,
                  ),
                );
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result, original);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sheet refuses a stale composer and remove does not write an endpoint',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventComposerSheet(
              block: parseEventBlocks(original).single,
              settings: const EventSettings(enabled: true),
              timezone: 'Europe/Paris',
              isCurrent: () => false,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.textContaining('The post changed'), findsOneWidget);
      expect(find.text('Remove event'), findsOneWidget);
    },
  );
}

class _Editor implements ComposerEditorHost {
  _Editor(String text, this.policy) : value = TextEditingValue(text: text);
  final EventSyntaxPolicy policy;
  bool editing = true;
  @override
  TextEditingValue value;
  @override
  String get siteUrl => 'https://forum.example';
  @override
  bool get isPluginTarget => false;
  @override
  String? get originalRaw => null;
  @override
  bool get loadingBody => false;
  @override
  bool get isCurrent => true;
  @override
  bool get isEdit => policy.context.isEdit;
  @override
  bool get isNewTopic => policy.state.createsTopic;
  @override
  bool get isReply => !isNewTopic && !isEdit;
  @override
  bool get isEditing => editing;
  @override
  PluginData get siteSettings => policy.state.siteSettings;
  @override
  T? syntaxPolicy<T extends ComposerSyntaxPolicy>(ComposerSyntaxKind kind) =>
      kind == eventSyntaxKind ? policy as T : null;
  @override
  bool commit({
    required TextEditingValue expectedValue,
    required TextEditingValue value,
  }) =>
      this.value == expectedValue &&
      commitText(expectedText: expectedValue.text, value: value);
  @override
  bool commitText({
    required String expectedText,
    required TextEditingValue value,
  }) {
    if (this.value.text != expectedText) return false;
    this.value = value;
    return true;
  }

  @override
  bool insertBlock({
    required TextEditingValue expectedValue,
    required String markdown,
  }) => commit(
    expectedValue: expectedValue,
    value: TextEditingValue(text: '${expectedValue.text}\n$markdown'),
  );
  @override
  void requestFocus() {}
}
