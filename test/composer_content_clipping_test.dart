import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/poll/poll_plugin.dart';
import 'package:discourse_native/src/shell/composer_block_surface.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _formerMember = r'\* - Former team member';
const _lastParagraph =
    'And for those taking the train to Seville, here are the groups/departure '
    'times at Atocha station:';
const _target = ComposerTarget(
  siteUrl: 'https://example.test',
  topicId: 1,
  slug: 'clipping',
  topicTitle: 'Travel plans',
);
final _table = [
  '| Name | Day | Arrival | Departure | Notes |',
  '| --- | --- | --- | --- | --- |',
  for (var row = 0; row < 12; row++)
    '| Member $row | Sunday 27th | 18:00 | 20:39 | Train |',
].join('\n');

void main() {
  setUpAll(() async {
    await (FontLoader(
      'ClippingSans',
    )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
  });

  final components = {
    'paragraph': 'The last paragraph has descenders: gyjpq.',
    'heading': '## Last heading',
    'table': _table,
    'details with a table': '[details="Travel plans"]\n$_table\n[/details]',
    'quote': '[quote="Sam, post:1, topic:1"]\nTravel plans\n[/quote]',
    'blockquote': '> Travel plans\n> Last quoted line',
    'image': '![Train|320x200](upload://train.png)',
    'gallery': '[grid]\n![Train|320x200](upload://train.png)\n[/grid]',
    'bullet list': '- First destination\n- Last destination',
    'ordered list': '1. First destination\n2. Last destination',
    'todo': '[] First destination\n[x] Last destination',
    'code': '```text\nFirst destination\nLast destination\n```',
    'plugin poll': '[poll]\n* Train\n* Plane\n[/poll]',
  };
  for (final entry in components.entries) {
    testWidgets(
      'a short composer reveals its last ${entry.key} and following text',
      (tester) async {
        final harness = await _Harness.create();
        final composer = harness.composer;
        final source = '${'Travel plans\n\n' * 8}${entry.value}';
        composer.text.value = TextEditingValue(
          text: source,
          selection: const TextSelection.collapsed(offset: 0),
        );
        await harness.mount(tester, height: 280, scale: 1.5);
        await _expectEndVisible(tester, composer);

        composer.text.value = TextEditingValue(
          text: '$source\n\n$_lastParagraph',
          selection: const TextSelection.collapsed(offset: 0),
        );
        await tester.pumpAndSettle();
        await _expectEndVisible(tester, composer);
        expect(composer.raw, '$source\n\n$_lastParagraph');
        composer.text.value = TextEditingValue(
          text: '$source\n\n$_formerMember',
          selection: const TextSelection.collapsed(offset: 0),
        );
        await tester.pumpAndSettle();
        await _expectEndVisible(tester, composer);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      // Theme.platform alone does not select the platform's default density.
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.android,
      }),
    );
  }

  testWidgets('resizing and table edits keep the final line reachable', (
    tester,
  ) async {
    final harness = await _Harness.create();
    final composer = harness.composer;
    composer.text.value = TextEditingValue(
      text: 'Travel plans\n\n$_table\n\n$_lastParagraph',
      selection: const TextSelection.collapsed(offset: 0),
    );
    await harness.mount(tester, height: 550);
    final editor = tester.state(find.byType(ComposerEditor).first);
    for (final (height, width, scale) in [
      (550.0, 760.0, 1.0),
      (250.0, 760.0, 1.0),
      (350.0, 420.0, 1.5),
      (350.0, 760.0, 2.0),
      (550.0, 760.0, 1.0),
    ]) {
      await harness.mount(tester, height: height, width: width, scale: scale);
      expect(tester.state(find.byType(ComposerEditor).first), same(editor));
      await _expectEndVisible(tester, composer);
    }

    final cell = find.descendant(
      of: find.byKey(const ValueKey('table-cell-12-4')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(cell, 'Changed departure information ' * 6);
    await tester.pumpAndSettle();
    await _expectEndVisible(tester, composer);
    expect(composer.raw, contains('Changed departure information'));
    expect(composer.raw, endsWith(_lastParagraph));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final target in [
    const ComposerTarget(
      siteUrl: 'https://example.test',
      topicId: 0,
      slug: '',
      topicTitle: '',
      mode: ComposerMode.newTopic,
    ),
    const ComposerTarget(
      siteUrl: 'https://example.test',
      topicId: 1,
      slug: 'clipping',
      topicTitle:
          'A long topic title that may wrap when editing in a narrow composer',
      mode: ComposerMode.postEdit,
      editingPostId: 1,
    ),
  ]) {
    testWidgets(
      '${target.mode.name} fields leave the editor above the footer',
      (tester) async {
        final harness = await _Harness.create(target: target);
        harness.composer.text.value = TextEditingValue(
          text: '$_table\n\n$_lastParagraph',
          selection: const TextSelection.collapsed(offset: 0),
        );
        await harness.mount(tester, height: 350, width: 420, scale: 1.5);
        await _expectEndVisible(tester, harness.composer);
        harness.composer.text.value = TextEditingValue(
          text: '$_table\n\n$_formerMember',
          selection: const TextSelection.collapsed(offset: 0),
        );
        await harness.mount(tester, height: 350);
        await _expectEndVisible(tester, harness.composer);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.android,
      }),
    );
  }
}

Future<void> _expectEndVisible(
  WidgetTester tester,
  ComposerController composer,
) async {
  final scroll = composer.text.imageScrollController!;
  scroll.jumpTo(scroll.position.maxScrollExtent);
  await tester.pumpAndSettle();
  expect(scroll.position.extentAfter, 0);
  final editor = tester.getRect(find.byType(ComposerEditor).first);
  final footer = tester.getRect(find.byKey(const ValueKey('composer-footer')));
  expect(editor.bottom, lessThanOrEqualTo(footer.top));
  final surface = tester.widget<ComposerBlockSurface>(
    find.byType(ComposerBlockSurface).first,
  );
  final lastBlock = surface.blockRect(composer.blocks.index.blocks.last)!;
  expect(lastBlock.bottom, lessThanOrEqualTo(editor.bottom + 1));
  expect(lastBlock.bottom, greaterThan(editor.top));
  if (composer.raw.endsWith(_lastParagraph) ||
      composer.raw.endsWith(_formerMember)) {
    final editable = tester
        .state<EditableTextState>(
          find.byWidgetPredicate(
            (widget) =>
                widget is EditableText &&
                identical(widget.controller, composer.text),
          ),
        )
        .renderEditable;
    final viewport = tester.getRect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DInput && identical(widget.controller, composer.text),
      ),
    );
    expect(
      editable.localToGlobal(editable.size.bottomRight(Offset.zero)).dy,
      lessThanOrEqualTo(viewport.bottom + .01),
    );
    final lastCharacter = editable
        .getBoxesForSelection(
          TextSelection(
            baseOffset: composer.raw.length - 1,
            extentOffset: composer.raw.length,
          ),
        )
        .single
        .toRect()
        .shift(editable.localToGlobal(Offset.zero));
    expect(lastCharacter.top, greaterThanOrEqualTo(editor.top));
    expect(lastCharacter.bottom, lessThanOrEqualTo(editor.bottom + 1));
  }
  expect(tester.takeException(), isNull);
}

class _Harness {
  _Harness(this.composer, this.shell);

  final ComposerController composer;
  final ShellController shell;

  static Future<_Harness> create({ComposerTarget target = _target}) async {
    final composer = ComposerController(
      target,
      syntaxPolicies: const [PollComposerSyntaxPolicy()],
    );
    final shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(composer.dispose);
    addTearDown(shell.dispose);
    await shell.load();
    return _Harness(composer, shell);
  }

  Future<void> mount(
    WidgetTester tester, {
    required double height,
    double width = 760,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.forBrightness(
          Brightness.dark,
          fontFamily: 'ClippingSans',
        ).copyWith(platform: TargetPlatform.macOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ShellScope(
          controller: shell,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: ComposerPanel(composer: composer, height: height),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}
