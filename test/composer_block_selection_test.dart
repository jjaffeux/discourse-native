import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugin_api/composer_syntax.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_composer.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_mermaid/mermaid_composer.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_plugin.dart';
import 'package:discourse_native/src/plugins/poll/poll_plugin.dart';
import 'package:discourse_native/src/shell/composer_block_surface.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_list_editor.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const _target = ComposerTarget(
  siteUrl: 'https://example.test',
  topicId: 1,
  slug: 'topic',
  topicTitle: 'Topic',
);
const _table = '| Name | Cost |\n| --- | --- |\n| Tea | 12 |';
const _blocks = {
  'table': _table,
  'code': '```dart\nprint("hello");\n```',
  'event': '[event start="2026-09-22 12:00" name="Meeting"]\nAgenda\n[/event]',
  'mermaid': '```mermaid\nflowchart TD\n  A --> B\n```',
  'details': '[details="Summary"]\nBody\n[/details]',
  'quote': '[quote="sam, post:1, topic:1"]\nQuoted text\n[/quote]',
  'image': '![Photo|100x100](upload://photo)',
  'gallery': '[grid]\n![Photo|100x100](upload://photo)\n[/grid]',
  'poll': '[poll]\n* Tea\n* Coffee\n[/poll]',
};

final _eventState = ComposerPluginState(
  createsTopic: true,
  siteSettings: PluginData.none.withValue(
    eventSettingsKey,
    const EventSettings(enabled: true),
  ),
  freshCurrentUser: PluginData.none.withValue(
    eventUserKey,
    const EventUserPermissions(true),
  ),
);

Finder _field(ComposerController composer) => find.byWidgetPredicate(
  (widget) => widget is EditableText && widget.controller == composer.text,
);

Future<ComposerController> _pump(
  WidgetTester tester,
  String source, {
  ThemeData? theme,
}) async {
  late final ComposerController composer;
  composer = ComposerController(
    _target,
    syntaxPolicies: [
      LocalDateComposerSyntaxPolicy(environment: LocalDateEnvironment.instance),
      const PollComposerSyntaxPolicy(),
      EventSyntaxPolicy(
        ComposerSyntaxPolicyContext(
          siteUrl: _target.siteUrl,
          isPluginTarget: false,
          isEdit: false,
          initialState: _eventState,
          readState: () => _eventState,
        ),
      ),
      MermaidComposerPolicy(() => composer),
    ],
  );
  addTearDown(composer.dispose);
  composer.text.value = TextEditingValue(
    text: source,
    selection: TextSelection.collapsed(offset: source.length),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(
        body: SizedBox(
          width: 760,
          child: ComposerEditor(
            composer: composer,
            hintText: 'Write a reply',
            textStyle: const TextStyle(fontSize: 16, height: 1.5),
            hintStyle: null,
          ),
        ),
      ),
    ),
  );
  composer.requestFocus();
  await tester.pumpAndSettle();
  return composer;
}

void main() {
  setUpAll(() async {
    LocalDateEnvironment.instance.ensureDatabase();
    LocalDateEnvironment.instance.setDeviceTimezone('Etc/UTC');
    await initializeDateFormatting('en');
  });

  for (final entry in {
    ..._blocks,
    'date': '[date=2026-09-30 timezone=Etc/UTC]',
    'date range':
        '[date-range from=2026-09-30T09:00:00 to=2026-09-30T10:00:00 timezone=Etc/UTC]',
    'link': '[Discourse](https://discourse.org)',
  }.entries) {
    testWidgets(
      '${entry.key} mobile backspace removes the whole component',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final source = 'Before\n\n${entry.value}\n\nAfter';
        final composer = await _pump(tester, source);
        final caret = 8 + entry.value.length;
        composer.text.selection = TextSelection.collapsed(offset: caret);
        await tester.pump();

        // Software keyboards send editing values, not hardware key events.
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: source.replaceRange(caret - 1, caret, ''),
            selection: TextSelection.collapsed(offset: caret - 1),
          ),
        );
        await tester.pump();

        expect(composer.raw, matches(RegExp(r'^Before\n+After$')));
        expect(composer.text.keyboardSelectedProjection, isNull);
        composer.history.undo();
        await tester.pump();
        expect(composer.raw, source);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }

  for (final entry in _blocks.entries) {
    for (final gap in ['\n', '\r\n', '\n\n']) {
      testWidgets(
        '${entry.key} mobile backspace across ${gap.length} gap characters '
        'selects before deleting',
        (tester) async {
          final source = 'Before\n\n${entry.value}${gap}After';
          final composer = await _pump(tester, source);
          final caret = source.indexOf('After');
          composer.text.selection = TextSelection.collapsed(offset: caret);
          await tester.pump();
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: source.replaceRange(caret - 1, caret, ''),
              selection: TextSelection.collapsed(offset: caret - 1),
            ),
          );
          await tester.pump();
          expect(composer.raw, source);
          expect(composer.text.keyboardSelectedProjection, isNotNull);

          final selection = composer.text.selection;
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: source.replaceRange(selection.start, selection.end, ''),
              selection: TextSelection.collapsed(offset: selection.start),
            ),
          );
          await tester.pump();
          expect(
            composer.raw,
            source.replaceRange(selection.start, selection.end, '').trim(),
          );
          expect(composer.text.keyboardSelectedProjection, isNull);
          expect(tester.takeException(), isNull);
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.android,
          TargetPlatform.iOS,
        }),
      );
    }
  }

  testWidgets(
    'mobile backspace removes adjacent dates without source fragments',
    (tester) async {
      const date = '[date=2026-09-30 timezone=Etc/UTC]';
      const prefix = 'Before 👩‍💻 ';
      final composer = await _pump(tester, '$prefix$date$date ');
      for (final expected in ['$prefix$date$date', '$prefix$date', prefix]) {
        final value = composer.text.value;
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: value.text.substring(0, value.text.length - 1),
            selection: TextSelection.collapsed(offset: value.text.length - 1),
          ),
        );
        await tester.pump();
        expect(composer.text.text, expected);
        expect(composer.text.selection.extentOffset, expected.length);
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.mobile(),
  );

  testWidgets('mobile forward delete removes an inline date', (tester) async {
    const date = '[date=2026-09-30 timezone=Etc/UTC]';
    const source = 'Before $date after';
    final composer = await _pump(tester, source);
    composer.text.selection = const TextSelection.collapsed(offset: 7);
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Before date=2026-09-30 timezone=Etc/UTC] after',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    await tester.pump();
    expect(composer.text.text, 'Before  after');
    expect(composer.text.selection, const TextSelection.collapsed(offset: 7));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.mobile());

  testWidgets('mobile backspace removes a date inside a list body', (
    tester,
  ) async {
    const date = '[date=2026-09-30 timezone=Etc/UTC]';
    final composer = await _pump(tester, '- Before $date');
    final body = tester
        .widgetList<ComposerRichBodyEditor>(find.byType(ComposerRichBodyEditor))
        .map((widget) => widget.composer)
        .whereType<ComposerListBodyController>()
        .single;
    body.text.selection = TextSelection.collapsed(
      offset: body.text.text.length,
    );
    body.requestFocus();
    await tester.pump();
    final value = body.text.value;
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: value.text.substring(0, value.text.length - 1),
        selection: TextSelection.collapsed(offset: value.text.length - 1),
      ),
    );
    await tester.pump();
    expect(body.text.text, 'Before ');
    expect(composer.raw, '- Before');
    composer.history.undo();
    await tester.pump();
    expect(composer.raw, '- Before $date');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.mobile());

  for (final shift in [false, true]) {
    for (final selection in [
      const TextSelection.collapsed(offset: 5),
      const TextSelection.collapsed(offset: 10),
      const TextSelection(baseOffset: 3, extentOffset: 7),
    ]) {
      testWidgets('paragraph Enter shift=$shift selection=$selection', (
        tester,
      ) async {
        final composer = await _pump(tester, 'First last');
        composer.text.selection = selection;
        await tester.pump();
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();

        final insertion = shift ? '\n' : '\n\n';
        expect(
          composer.text.text,
          'First last'.replaceRange(selection.start, selection.end, insertion),
        );
        expect(
          composer.text.selection,
          TextSelection.collapsed(offset: selection.start + insertion.length),
        );
        if (selection.end < 10) {
          expect(composer.blocks.index.blocks, hasLength(shift ? 1 : 2));
        }
        composer.history.undo();
        await tester.pump();
        expect(composer.text.text, 'First last');
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      'block outline replaces the text fill in ${theme.brightness.name}',
      (tester) async {
        final composer = await _pump(
          tester,
          'Before\n\n$_table\n\nAfter',
          theme: theme,
        );
        final mainField = _field(composer);
        final mainEditable = tester.state<EditableTextState>(mainField);
        final normalSelectionColor = mainEditable.renderEditable.selectionColor;
        expect(normalSelectionColor?.a, greaterThan(0));

        composer.text.selection = const TextSelection.collapsed(offset: 8);
        await tester.pump();
        expect(mainEditable.renderEditable.selectionColor?.a, 0);
        expect(
          tester
              .widgetList<DItem>(find.byType(DItem))
              .where(
                (item) =>
                    item.selected &&
                    item.selectionStyle == DItemSelectionStyle.outline,
              ),
          hasLength(1),
        );

        final outline = find.byWidgetPredicate(
          (widget) =>
              widget is DItem &&
              widget.selected &&
              widget.selectionStyle == DItemSelectionStyle.outline,
        );
        final table = find.byType(DDataTable<int>);
        expect(tester.getRect(outline), tester.getRect(table));
        for (final label in ['Add row', 'Add column']) {
          expect(
            tester.getRect(outline).overlaps(tester.getRect(find.text(label))),
            isFalse,
          );
        }

        // Keyboard focus can move into a cell without a pointer clearing the
        // component selection. The cell must keep its normal text highlight.
        final cell = find.descendant(
          of: find.byKey(const ValueKey('table-cell-1-0')),
          matching: find.byType(EditableText),
        );
        await tester.showKeyboard(cell);
        final cellEditable = tester.state<EditableTextState>(cell);
        cellEditable.widget.controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 3,
        );
        await tester.pump();
        expect(cellEditable.renderEditable.selectionColor?.a, greaterThan(0));

        composer.text.clearKeyboardPillSelection();
        composer.text.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 6,
        );
        composer.requestFocus();
        await tester.pump();
        expect(
          mainEditable.renderEditable.selectionColor,
          normalSelectionColor,
        );
        expect(outline, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final first in _blocks.entries) {
    for (final second in _blocks.entries) {
      testWidgets(
        '${first.key} followed by ${second.key} has structural spacing',
        (tester) async {
          final composer = await _pump(
            tester,
            '${first.value}\n${second.value}',
          );
          expect(composer.blocks.index.blocks, hasLength(2));
          final rendered = tester
              .state<EditableTextState>(_field(composer))
              .renderEditable;
          final painted = rendered.text!.toPlainText(
            includeSemanticsLabels: false,
          );
          expect(painted[0], '\uFFFC');
          expect(painted[first.value.length + 1], '\uFFFC');
          expect(composer.blocks.index.blocks.map((block) => block.source), [
            first.value,
            second.value,
          ]);
          final surface = tester.widget<ComposerBlockSurface>(
            find.byType(ComposerBlockSurface),
          );
          final before = surface.blockRect(composer.blocks.index.blocks.first)!;
          final after = surface.blockRect(composer.blocks.index.blocks.last)!;
          // Adjacent components keep at least the half-line paragraph gap.
          expect(
            after.top - before.bottom,
            greaterThanOrEqualTo(rendered.preferredLineHeight * .5),
          );
          expect(painted.length, composer.text.text.length);
          expect(composer.text.text, '${first.value}\n${second.value}');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('lists stay on their own side of a poll boundary', (
    tester,
  ) async {
    final poll = _blocks['poll']!;
    final source = '* Before\n$poll\n$_table';
    final composer = await _pump(tester, source);
    expect(
      [
        for (final block in composer.text.syntaxBlocks)
          (block.kind.name, block.source),
      ],
      [
        ('list-item', '* Before'),
        ('poll', poll),
        ('list-item', '* Tea'),
        ('list-item', '* Coffee'),
        ('table', _table),
      ],
    );
    final rendered = tester
        .state<EditableTextState>(_field(composer))
        .renderEditable;
    final painted = rendered.text!.toPlainText(includeSemanticsLabels: false);
    expect(painted[source.indexOf(poll)], '￼');
    expect(painted[source.indexOf(_table)], '￼');

    // The caret inside the poll shows its source. Each option keeps its list
    // editor, which holds neither the closing tag nor the following table.
    composer.text.selection = TextSelection.collapsed(
      offset: source.indexOf('[poll]') + 3,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<ComposerRichBodyEditor>(
            find.byType(ComposerRichBodyEditor),
          )
          .map((editor) => editor.composer.text.text),
      ['Before', 'Tea', 'Coffee'],
    );
    expect(composer.text.text, source);
    expect(tester.takeException(), isNull);
  });

  for (final entry in _blocks.entries) {
    testWidgets(
      '${entry.key} boundary carets can reselect a component at the start of the document',
      (tester) async {
        final composer = await _pump(tester, entry.value);
        composer.text.selection = const TextSelection.collapsed(offset: 0);
        await tester.pump();
        for (final direction in [
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
        ]) {
          await tester.sendKeyEvent(direction);
          await tester.pump();
          expect(composer.text.keyboardSelectedProjection, isNull);
          expect(composer.text.selection.isCollapsed, isTrue);
          await tester.sendKeyEvent(
            direction == LogicalKeyboardKey.arrowLeft
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowLeft,
          );
          await tester.pump();
          expect(composer.text.keyboardSelectedProjection, isNotNull);
          expect(composer.text.text, entry.value);
        }
      },
    );
    for (final suffix in ['', '\n\nAfter']) {
      for (final before in [true, false]) {
        testWidgets(
          '${entry.key} arrow ${before ? 'left' : 'right'} places a same-line caret and Enter inserts beside it ($suffix)',
          (tester) async {
            final source = 'Before\n\n${entry.value}$suffix';
            final composer = await _pump(tester, source);
            composer.text.selection = const TextSelection.collapsed(offset: 8);
            await tester.pump();
            final selected = composer.text.selection;
            final offset = before
                ? selected.start
                : selected.start +
                      selected.textInside(source).trimRight().length;
            await tester.sendKeyEvent(
              before
                  ? LogicalKeyboardKey.arrowLeft
                  : LogicalKeyboardKey.arrowRight,
            );
            await tester.pump();
            expect(composer.text.text, source);
            expect(composer.text.keyboardSelectedProjection, isNull);
            expect(
              composer.text.selection,
              TextSelection.collapsed(offset: offset),
            );
            expect(
              tester.widget<EditableText>(_field(composer)).showCursor,
              isTrue,
            );
            final render = tester
                .state<EditableTextState>(_field(composer))
                .renderEditable;
            // The hidden blank line before the component shares its line.
            expect(
              render.getLineAtOffset(TextPosition(offset: offset)).start,
              7,
            );
            expect(
              render.getLocalRectForCaret(TextPosition(offset: offset)).height,
              greaterThan(0),
            );
            if (suffix.isNotEmpty) {
              expect(
                render
                    .getLineAtOffset(TextPosition(offset: source.length - 1))
                    .start,
                greaterThan(offset),
              );
            }
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pump();
            expect(
              composer.text.text,
              source.replaceRange(offset, offset, '\n\n'),
            );
            expect(composer.text.keyboardSelectedProjection, isNull);
            expect(
              composer.text.selection,
              TextSelection.collapsed(offset: before ? offset : offset + 2),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
      testWidgets(
        '${entry.key} Backspace immediately deletes from its trailing caret ($suffix)',
        (tester) async {
          final source = 'Before\n\n${entry.value}$suffix';
          final composer = await _pump(tester, source);
          composer.text.selection = const TextSelection.collapsed(offset: 8);
          await tester.pump();
          final selected = composer.text.selection;
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
          await tester.pump();
          expect(
            composer.raw,
            source.replaceRange(selected.start, selected.end, '').trim(),
          );
          expect(composer.text.keyboardSelectedProjection, isNull);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '${entry.key} Backspace at the source boundary removes the whole component',
      (tester) async {
        final composer = await _pump(
          tester,
          'Before\n\n${entry.value}\n\nAfter',
        );
        composer.text.selection = TextSelection.collapsed(
          offset: 8 + entry.value.length,
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(
          composer.raw,
          entry.key == 'quote' ? 'Before\n\nAfter' : 'Before\n\n\n\nAfter',
        );
        expect(composer.text.keyboardSelectedProjection, isNull);
      },
    );
    for (final newline in ['\n', '\r\n']) {
      testWidgets(
        '${entry.key} gap before another component cannot hold a caret (${newline.length})',
        (tester) async {
          const second = '![Second|100x100](upload://second)';
          final composer = await _pump(
            tester,
            '${entry.value}$newline$newline$second',
          );
          final rendered = tester
              .state<EditableTextState>(_field(composer))
              .renderEditable;
          double secondTop() => rendered
              .getBoxesForSelection(
                TextSelection(
                  baseOffset: composer.text.text.indexOf(second),
                  extentOffset: composer.text.text.indexOf(second) + 1,
                ),
              )
              .last
              .top;
          final before = secondTop();
          composer.text.selection = TextSelection.collapsed(
            offset: entry.value.length + newline.length,
          );
          await tester.pump();
          expect(
            composer.text.selection.isCollapsed &&
                composer.text.selection.extentOffset > entry.value.length &&
                composer.text.selection.extentOffset <
                    entry.value.length + newline.length * 2,
            isFalse,
          );
          expect(composer.text.text, '${entry.value}$newline$newline$second');
          expect(secondTop(), closeTo(before, .01));
          composer.text.clearKeyboardPillSelection();
          composer.text.selection = TextSelection.collapsed(
            offset: composer.text.text.length,
          );
          await tester.pump();
          final painted = rendered.text!.toPlainText(
            includeSemanticsLabels: false,
          );
          // One line break remains; the required blank line is hidden.
          expect(
            '\n'.allMatches(
              painted.substring(0, composer.text.text.indexOf(second)),
            ),
            hasLength(1),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
    for (final suffix in ['\n', '\r\n']) {
      testWidgets(
        '${entry.key} Backspace selects before deleting after ${suffix.length} line-ending characters',
        (tester) async {
          final source = 'Before\n\n${entry.value}$suffix';
          final composer = await _pump(tester, source);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
          await tester.pump();
          expect(composer.raw, 'Before\n\n${entry.value}');
          expect(composer.text.keyboardSelectedProjection, isNotNull);
          final rendered = tester
              .state<EditableTextState>(_field(composer))
              .renderEditable;
          expect(
            rendered.text!
                .toPlainText(includeSemanticsLabels: false)
                .substring(8),
            isNot(contains('\n')),
            reason:
                'The selected component must not retain a synthetic caret line',
          );
          expect(
            rendered
                .getLineAtOffset(
                  TextPosition(offset: composer.text.text.length),
                )
                .start,
            7,
            reason: 'The end of the component must share its rendered line',
          );
          expect(
            composer.text.selection.textInside(composer.text.text).trimRight(),
            entry.value,
          );
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.backspace);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
          await tester.pump();
          expect(composer.raw, 'Before\n\n${entry.value}');
          await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
          await tester.pump();
          expect(composer.raw.trim(), 'Before');
          expect(tester.takeException(), isNull);
        },
      );
    }
    for (final gap in ['\n', '\n\n']) {
      testWidgets(
        '${entry.key} Backspace preserves following text with ${gap.length} newlines',
        (tester) async {
          final source = 'Before\n\n${entry.value}${gap}After';
          final composer = await _pump(tester, source);
          composer.text.selection = TextSelection.collapsed(
            offset: source.indexOf('After'),
          );
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
          await tester.pump();
          expect(composer.raw, source);
          expect(composer.text.keyboardSelectedProjection, isNotNull);
          final painted = tester
              .state<EditableTextState>(_field(composer))
              .renderEditable
              .text!
              .toPlainText(includeSemanticsLabels: false);
          expect(painted.length, source.length);
          expect(tester.takeException(), isNull);
        },
      );
    }
    for (final prefix in ['', 'Before\n\n']) {
      testWidgets(
        '${entry.key} leading boundary selects and deletes the whole block '
        'with ${prefix.isEmpty ? 'no' : 'preceding'} text',
        (tester) async {
          final source = '$prefix${entry.value}\n\nAfter';
          final composer = await _pump(tester, source);
          tester.testTextInput.updateEditingValue(
            composer.text.value.copyWith(
              selection: TextSelection.collapsed(offset: prefix.length),
            ),
          );
          await tester.pump();

          final selected = composer.text.selection;
          expect(selected.isCollapsed, isFalse);
          expect(selected.start, prefix.length);
          expect(selected.textInside(source).trimRight(), entry.value);
          expect(composer.text.keyboardSelectedProjection, isNotNull);
          expect(
            tester.widget<EditableText>(_field(composer)).showCursor,
            false,
          );
          expect(
            find.byKey(const ValueKey('composer-selection-toolbar')),
            findsNothing,
          );
          expect(composer.raw, source);

          await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
          await tester.pump();
          expect(
            composer.raw,
            source.replaceRange(selected.start, selected.end, '').trim(),
          );
          expect(composer.text.keyboardSelectedProjection, isNull);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets('${entry.key} supports native keyboard deletion', (
      tester,
    ) async {
      final source = 'Before\n\n${entry.value}\n\nAfter';
      final composer = await _pump(tester, source);
      composer.text.selection = const TextSelection.collapsed(offset: 8);
      await tester.pump();
      final selected = composer.text.selection;
      final remaining = source.replaceRange(selected.start, selected.end, '');
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: remaining,
          selection: TextSelection.collapsed(offset: selected.start),
        ),
      );
      await tester.pump();
      expect(composer.raw, remaining.trim());
      expect(composer.text.keyboardSelectedProjection, isNull);
    });
  }

  testWidgets('images keep their structural gap with one or two newlines', (
    tester,
  ) async {
    const first = '![First|100x100](upload://first)';
    const second = '![Second|100x100](upload://second)';
    final composer = await _pump(tester, '$first\n\n$second');
    final rendered = tester
        .state<EditableTextState>(_field(composer))
        .renderEditable;
    double secondTop() => rendered
        .getBoxesForSelection(
          TextSelection(
            baseOffset: composer.text.imageBlocks.last.start,
            extentOffset: composer.text.imageBlocks.last.start + 1,
          ),
        )
        .last
        .top;
    final before = secondTop();
    composer.text.value = const TextEditingValue(
      text: '$first\n$second',
      selection: TextSelection.collapsed(
        offset: first.length + 1 + second.length,
      ),
    );
    await tester.pump();
    expect(composer.text.text, '$first\n$second');
    expect(secondTop(), closeTo(before, 2));
    composer.text.clearKeyboardPillSelection();
    composer.text.selection = TextSelection.collapsed(
      offset: composer.text.text.length,
    );
    await tester.pump();
    final painted = rendered.text!.toPlainText(includeSemanticsLabels: false);
    expect(
      '\n'.allMatches(
        painted.substring(0, composer.text.imageBlocks.last.start),
      ),
      hasLength(1),
      reason:
          'The gap has geometry without inserting a newline into the source',
    );
  });

  testWidgets('undo restores the line removed after a component', (
    tester,
  ) async {
    const source = 'Before\n\n$_table\n';
    final composer = await _pump(tester, source);
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump(const Duration(seconds: 1));
    expect(composer.text.text, source.substring(0, source.length - 1));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(composer.text.text, source);
    expect(composer.text.keyboardSelectedProjection, isNull);
    expect(
      composer.text.selection,
      const TextSelection.collapsed(offset: source.length),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'Delete removes a selected block and undo restores exact source',
    (tester) async {
      const source = 'Before\n\n$_table\n\nAfter';
      final composer = await _pump(tester, source);
      composer.text.selection = const TextSelection.collapsed(offset: 8);
      await tester.pump(const Duration(seconds: 1));
      final selectedItem = tester
          .widgetList<DItem>(find.byType(DItem))
          .where((item) => item.selected);
      expect(selectedItem, hasLength(1));
      expect(selectedItem.single.selectionStyle, DItemSelectionStyle.outline);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump(const Duration(seconds: 1));
      expect(composer.raw, 'Before\n\n\n\nAfter');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(composer.raw, source);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('arrows traverse a block through its boundary carets', (
    tester,
  ) async {
    const prefix = 'Before\n\n';
    final composer = await _pump(tester, '$prefix$_table\n\nAfter');
    composer.text.selection = const TextSelection.collapsed(
      offset: prefix.length - 1,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      composer.text.keyboardSelectedProjection,
      isA<ComposerSyntaxOccurrence>(),
    );
    expect(composer.text.selection.start, prefix.length);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(composer.text.keyboardSelectedProjection, isNull);
    expect(
      composer.text.selection,
      const TextSelection.collapsed(offset: prefix.length),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(composer.text.keyboardSelectedProjection, isNull);
    expect(
      composer.text.selection,
      const TextSelection.collapsed(offset: prefix.length + _table.length),
    );
  });

  testWidgets('clicking the leading table caret selects it', (tester) async {
    final composer = await _pump(tester, '$_table\n\nAfter');
    final render = tester
        .state<EditableTextState>(_field(composer))
        .renderEditable;
    final caret = render.getLocalRectForCaret(const TextPosition(offset: 0));
    await tester.tapAt(
      render.localToGlobal(caret.topLeft + const Offset(1, 1)),
    );
    await tester.pump();
    expect(composer.text.keyboardSelectedSyntax, isNotNull);
    expect(
      composer.text.selection,
      const TextSelection(baseOffset: 0, extentOffset: _table.length),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(composer.raw, 'After');
  });

  testWidgets('leaving an image preserves the preceding grapheme', (
    tester,
  ) async {
    const prefix = '👩‍💻';
    final composer = await _pump(tester, '$prefix${_blocks['image']}\nAfter');
    final image = composer.text.imageBlocks.single;
    composer.text.selection = TextSelection.collapsed(offset: image.start);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(
      composer.text.selection,
      const TextSelection.collapsed(offset: prefix.length),
    );
  });

  testWidgets('inline links retain an editable leading caret', (tester) async {
    final composer = await _pump(
      tester,
      'Before [link](https://example.test) after',
    );
    composer.text.selection = const TextSelection.collapsed(offset: 7);
    await tester.pump();
    expect(composer.text.selection.isCollapsed, isTrue);
    expect(composer.text.keyboardSelectedProjection, isNull);
    expect(tester.widget<EditableText>(_field(composer)).showCursor, isTrue);
  });
}
