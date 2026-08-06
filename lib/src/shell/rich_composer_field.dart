import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'composer_controller.dart';
import 'composer_marks.dart';

/// The composer's rich editing surface.
///
/// The markdown remains the source of truth: this reads [ComposerController.text]
/// once on open, and writes the serialised document straight back into it on
/// every change. Everything downstream — submitting, drafts, the round-trip
/// guard — keeps working against a plain String and never learns that a
/// document model exists.
class RichComposerField extends StatefulWidget {
  const RichComposerField({super.key, required this.composer});

  final ComposerController composer;

  @override
  State<RichComposerField> createState() => _RichComposerFieldState();
}

class _RichComposerFieldState extends State<RichComposerField> {
  late final MutableDocument _document;
  late final MutableDocumentComposer _documentComposer;
  late final Editor _editor;

  @override
  void initState() {
    super.initState();
    _document = discourseMarkdownToDocument(widget.composer.text.text);
    _documentComposer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(
      document: _document,
      composer: _documentComposer,
      isHistoryEnabled: true,
    );
    _document.addListener(_onDocumentChanged);
    widget.composer.attachRichEditor(_editor, _documentComposer);
  }

  void _onDocumentChanged(DocumentChangeLog changeLog) {
    // Straight back to markdown. Serialising per keystroke is affordable at
    // post length, and it keeps the two representations from ever drifting.
    widget.composer.setRawFromRichEditor(
      discourseDocumentToMarkdown(_document),
    );
  }

  @override
  void dispose() {
    widget.composer.detachRichEditor(_editor);
    _document.removeListener(_onDocumentChanged);
    _editor.dispose();
    _documentComposer.dispose();
    _document.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium ?? const TextStyle();

    return SuperEditor(
      editor: _editor,
      focusNode: widget.composer.focus,
      autofocus: true,
      stylesheet: defaultStylesheet.copyWith(
        documentPadding: EdgeInsets.zero,
        // The hook Parchment has no equivalent of: how a span is drawn is a
        // function of the attributions on it, so marks we invented are styled
        // like any other rather than needing the editor to know them.
        inlineTextStyler: (attributions, existing) =>
            discourseInlineStyle(attributions, existing, theme),
        // super_editor's defaults are a document viewer's: a 640-wide column
        // centred in whatever space it is given. It has to go, or the composer
        // text sits in the middle of the panel while the plain field fills it.
        //
        // Before, not after, because rules only merge text styles and paddings
        // — for anything else the first rule to set a key keeps it, so a later
        // rule cannot take the width back.
        addRulesBefore: [
          StyleRule(
            BlockSelector.all,
            (document, node) => {Styles.maxWidth: double.infinity},
          ),
        ],
        addRulesAfter: [
          StyleRule(
            BlockSelector.all,
            (document, node) => {
              Styles.textStyle: base,
              // Paddings do cascade, so the default 24 horizontal has to be
              // overridden rather than merely left unset.
              Styles.padding: const CascadingPadding.symmetric(
                horizontal: 0,
                vertical: 2,
              ),
            },
          ),
        ],
      ),
    );
  }
}
