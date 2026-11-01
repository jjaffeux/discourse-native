import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'math_settings.dart';
import 'math_source.dart';

const mathSyntaxKind = ComposerSyntaxKind(
  owner: PluginId('discourse-math'),
  name: 'expression',
);
bool _editable(ComposerEditorHost editor) =>
    editor.isCurrent &&
    editor.isEditing &&
    !editor.loadingBody &&
    editor.siteSettings.get(mathSettingsKey)?.configuration != null;

Future<void> insertMath(BuildContext context, ComposerEditorHost editor) async {
  if (!_editable(editor)) return;
  final before = editor.value;
  final selection = before.selection;
  if (!selection.isValid) return;
  final lineStart = selection.start == 0
      ? 0
      : before.text.lastIndexOf('\n', selection.start - 1) + 1;
  final block = before.text
      .substring(lineStart, selection.start)
      .trim()
      .isEmpty;
  final result = await _mathDialog(
    context,
    source: before.text.substring(selection.start, selection.end),
    display: block,
  );
  if (result == null || !_editable(editor)) return;
  final source = result.display
      ? '\$\$\n${result.source}\n\$\$'
      : '\$${escapeMathDelimiter(result.source, r'$')}\$';
  if (editor.value.text != before.text) return;
  if (result.display) {
    editor.commitText(expectedText: before.text, value: before);
    editor.insertBlock(expectedValue: editor.value, markdown: source);
  } else {
    final left =
        selection.start > 0 &&
            !RegExp(
              r'[\s\p{P}]',
              unicode: true,
            ).hasMatch(before.text[selection.start - 1])
        ? ' '
        : '';
    final right =
        selection.end < before.text.length &&
            !RegExp(
              r'[\s\p{P}]',
              unicode: true,
            ).hasMatch(before.text[selection.end])
        ? ' '
        : '';
    final inserted = '$left$source$right';
    editor.commitText(
      expectedText: before.text,
      value: TextEditingValue(
        text: before.text.replaceRange(
          selection.start,
          selection.end,
          inserted,
        ),
        selection: TextSelection.collapsed(
          offset: selection.start + inserted.length,
        ),
      ),
    );
  }
  editor.requestFocus();
}

Future<DMathExpression?> _mathDialog(
  BuildContext context, {
  required String source,
  required bool display,
  bool editing = false,
}) => showDDialog<DMathExpression>(
  context: context,
  builder: (context, dialog) => _MathSourceDialog(
    source: source,
    display: display,
    editing: editing,
    dialog: dialog,
  ),
);

class _MathSourceDialog extends StatefulWidget {
  const _MathSourceDialog({
    required this.source,
    required this.display,
    required this.editing,
    required this.dialog,
  });
  final String source;
  final bool display, editing;
  final DDialogController<DMathExpression> dialog;
  @override
  State<_MathSourceDialog> createState() => _MathSourceDialogState();
}

class _MathSourceDialogState extends State<_MathSourceDialog> {
  late final controller = TextEditingController(text: widget.source);
  late bool display = widget.display;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DDialogContent(
    maxWidth: 560,
    children: [
      DDialogTitle(
        child: Text(
          widget.editing ? context.l10n.editMath : context.l10n.insertMath,
        ),
      ),
      DTextarea(
        controller: controller,
        labelText: context.l10n.mathSource,
        hintText: r'E=mc^2',
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        minLines: 3,
        maxLines: 10,
        maxLength: 16384,
        onChanged: (_) => setState(() {}),
      ),
      if (!widget.editing)
        DToggle(
          pressed: display,
          onPressedChanged: (value) => setState(() => display = value),
          child: Text(context.l10n.mathDisplay),
        ),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          DButton(
            label: Text(context.l10n.cancel),
            variant: DButtonVariant.outline,
            onPressed: () => widget.dialog.close(),
          ),
          const SizedBox(width: DSpacing.sm),
          DButton(
            label: Text(
              widget.editing ? context.l10n.mathApply : context.l10n.insert,
            ),
            onPressed:
                controller.text.trim().isEmpty ||
                    (!display && controller.text.contains('\n'))
                ? null
                : () => widget.dialog.close(
                    DMathExpression(controller.text, display: display),
                  ),
          ),
        ],
      ),
    ],
  );
}

final class MathComposerPolicy implements ComposerSyntaxPolicy {
  const MathComposerPolicy(this.context);
  final ComposerSyntaxPolicyContext context;
  MathSettings get settings =>
      context.readState().siteSettings.get(mathSettingsKey) ??
      const MathSettings();
  @override
  ComposerSyntaxKind get kind => mathSyntaxKind;
  @override
  Object? get projectionState => settings;
  @override
  TextInputFormatter? get inputFormatter => null;
  @override
  List<ComposerSyntaxProjection> parse(String source) {
    final config = settings.configuration;
    final reader = context.readEditor;
    if (config == null || reader == null) return const [];
    final occurrences = scanMath(source, settings);
    return [
      for (final occurrence in occurrences)
        if (occurrence.expression.display)
          _MathBlockProjection(occurrence, reader, config, occurrences)
        else
          _MathProjection(occurrence, reader, config, occurrences),
    ];
  }
}

class _MathProjection implements ComposerInteractiveSyntaxProjection {
  const _MathProjection(
    this.occurrence,
    this.readEditor,
    this.config,
    this.occurrences,
  );
  final MathOccurrence occurrence;
  final ComposerEditorHost Function() readEditor;
  final DMathConfiguration config;
  final List<MathOccurrence> occurrences;
  @override
  int get start => occurrence.start;
  @override
  int get end => occurrence.end;
  @override
  String get source => occurrence.original;
  @override
  bool get supportsHover => false;
  @override
  bool get protectsAdjacentDelete => true;
  @override
  bool needsRawSource(
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) =>
      document.isComposingRangeValid &&
      !document.composing.isCollapsed &&
      document.composing.start < end &&
      document.composing.end > start;
  @override
  int caretAfter(String document) => end;
  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) =>
      document.copyWith(
        selection: TextSelection.collapsed(offset: end),
        composing: TextRange.empty,
      );
  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) {
    Widget child = DMath(
      key: context.pillKey,
      expression: occurrence.expression,
      configuration: config,
      context: [for (final item in occurrences) item.expression],
      contextIndex: occurrences.indexOf(occurrence),
      onEdit: () => edit(context.pillKey.currentContext!, readEditor()),
    );
    if (occurrence.expression.display) {
      final blockChild = child;
      child = LayoutBuilder(
        builder: (_, constraints) => SizedBox(
          width: (constraints.maxWidth - 3).clamp(0, double.infinity),
          child: ComposerBlockSelection(
            selected: context.highlighted,
            child: blockChild,
          ),
        ),
      );
    } else {
      child = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: child,
      );
    }
    final hiddenEnd =
        source.length -
        (occurrence.expression.display && !context.followedByLineBreak ? 1 : 0);
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: child,
      ),
      if (hiddenEnd > 1)
        TextSpan(
          text: source.substring(1, hiddenEnd),
          semanticsLabel: '\u200B' * (hiddenEnd - 1),
          style: const TextStyle(
            fontSize: 0,
            height: 0,
            letterSpacing: 0,
            color: Colors.transparent,
          ),
        ),
      if (occurrence.expression.display && !context.followedByLineBreak)
        TextSpan(
          text: '\n',
          style: context.baseStyle.copyWith(color: Colors.transparent),
        ),
    ];
  }

  @override
  Future<void> edit(BuildContext context, ComposerEditorHost editor) async {
    if (!_editable(editor)) return;
    final before = editor.value.text;
    if (end > before.length || before.substring(start, end) != source) return;
    final result = await _mathDialog(
      context,
      source: occurrence.expression.source,
      display: occurrence.expression.display,
      editing: true,
    );
    if (result == null || !_editable(editor)) return;
    final replacement = occurrence.replace(result.source);
    if (editor.commitText(
      expectedText: before,
      value: TextEditingValue(
        text: before.replaceRange(start, end, replacement),
        selection: TextSelection.collapsed(offset: start + replacement.length),
      ),
    )) {
      editor.requestFocus();
    }
  }

  @override
  void remove(BuildContext context, ComposerEditorHost editor) {
    final text = editor.value.text;
    if (!_editable(editor) ||
        end > text.length ||
        text.substring(start, end) != source) {
      return;
    }
    editor.commitText(
      expectedText: text,
      value: TextEditingValue(
        text: text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      ),
    );
  }
}

final class _MathBlockProjection extends _MathProjection
    implements ComposerBlockSyntaxProjection {
  const _MathBlockProjection(
    super.occurrence,
    super.readEditor,
    super.config,
    super.occurrences,
  );
}
