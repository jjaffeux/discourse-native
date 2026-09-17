import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../plugin_api/composer_syntax.dart';
import 'composer_block_selection.dart';
import 'composer_controller.dart';
import 'composer_upload_attachment.dart';

/// Projects draft-local upload slots through the editor's existing block API.
/// Tokens are removed from saved/submitted Markdown by the composer owner.
final class ComposerUploadPlaceholderPolicy implements ComposerSyntaxPolicy {
  ComposerUploadPlaceholderPolicy(this.composer);

  final ComposerController composer;

  @override
  ComposerSyntaxKind get kind =>
      const ComposerSyntaxKind(owner: PluginId('core'), name: 'upload');

  @override
  Object? get projectionState => null;

  @override
  TextInputFormatter get inputFormatter => _UploadInputFormatter(this);

  @override
  List<ComposerSyntaxProjection> parse(String source) => [
    for (final entry in composer.uploadPlaceholders.entries)
      if (source.indexOf(entry.value) case final start when start >= 0)
        _UploadProjection(composer, entry.key, start, entry.value),
  ];
}

final class _UploadProjection implements ComposerBlockSyntaxProjection {
  const _UploadProjection(this.composer, this.id, this.start, this.source);

  final ComposerController composer;
  final int id;
  @override
  final int start;
  @override
  final String source;
  @override
  int get end => start + source.length;

  @override
  bool needsRawSource(
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) => false;

  @override
  int caretAfter(String document) =>
      end < document.length && document[end] == '\n' ? end + 1 : end;

  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) =>
      document.copyWith(
        selection: TextSelection.collapsed(offset: caretAfter(document.text)),
        composing: TextRange.empty,
      );

  @override
  bool get supportsHover => false;
  @override
  bool get protectsAdjacentDelete => true;

  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) => [
    WidgetSpan(
      alignment: PlaceholderAlignment.top,
      style: context.baseStyle,
      child: ComposerBlockSelection(
        selected: context.highlighted,
        child: ListenableBuilder(
          key: context.pillKey,
          listenable: composer,
          builder: (context, _) {
            final upload = composer.uploads
                .where((upload) => upload.id == id)
                .firstOrNull;
            if (upload == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ComposerUploadAttachment(
                key: ValueKey('composer-inline-upload-$id'),
                composer: composer,
                upload: upload,
              ),
            );
          },
        ),
      ),
    ),
    // Match the editor's image/quote block accounting: end the widget's
    // intrinsic-height line before the hidden source tail. Otherwise adjacent
    // upload rows can overlap each other's hit-test regions.
    TextSpan(
      text: '\n',
      style: context.baseStyle.copyWith(color: Colors.transparent),
    ),
    TextSpan(
      text: source.substring(2),
      style: const TextStyle(
        fontSize: 0,
        height: 0,
        letterSpacing: 0,
        color: Colors.transparent,
      ),
    ),
  ];

  @override
  void edit(BuildContext context, ComposerEditorHost editor) {}

  @override
  void remove(BuildContext context, ComposerEditorHost editor) {
    if (editor.isEditing) composer.cancelUpload(id);
  }
}

/// An upload slot can be removed as a whole, never edited into a broken token.
final class _UploadInputFormatter extends TextInputFormatter {
  const _UploadInputFormatter(this.policy);

  final ComposerUploadPlaceholderPolicy policy;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text == newValue.text) return newValue;
    final blocks = policy.parse(oldValue.text);
    if (blocks.isEmpty) return newValue;
    var start = 0;
    while (start < oldValue.text.length &&
        start < newValue.text.length &&
        oldValue.text[start] == newValue.text[start]) {
      start++;
    }
    var end = oldValue.text.length;
    var newEnd = newValue.text.length;
    while (end > start &&
        newEnd > start &&
        oldValue.text[end - 1] == newValue.text[newEnd - 1]) {
      end--;
      newEnd--;
    }
    for (final block in blocks) {
      if (start == end) {
        if (start > block.start && start < block.end) return oldValue;
      } else if (start < block.end &&
          end > block.start &&
          (start > block.start || end < block.end)) {
        return oldValue;
      }
    }
    return newValue;
  }
}
