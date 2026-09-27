import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../plugin_api/composer_syntax.dart';
import 'composer_block_selection.dart';
import 'composer_controller.dart';
import 'composer_upload_attachment.dart';

/// Where one registered upload token occurs in a document.
typedef ComposerUploadSlot = ({int id, int start, String token});

/// The draft-local tokens one composer holds its upload slots with: U+FFFC,
/// `upload-<composer>-<id>`, U+FFFC.
///
/// A settled slot stays registered: an undo can restore it after its request
/// has finished, and it must still be recognised to be stripped. The scans run
/// on every keystroke, so they cannot afford a search per slot ever minted.
/// Every token shares its composer's prefix instead, and a scan walks that
/// prefix's occurrences — one pass over the document, however many uploads
/// the composer has started.
final class ComposerUploadPlaceholders {
  ComposerUploadPlaceholders(Object composer)
    : _prefix = '${_delimiter}upload-${identityHashCode(composer)}-';

  static const _delimiter = '\uFFFC';
  final String _prefix;
  final Map<int, String> _tokens = {};

  /// Registers the token for upload [id] and returns it.
  String add(int id) => _tokens[id] = '$_prefix$id$_delimiter';

  String? operator [](int id) => _tokens[id];

  Iterable<String> get values => _tokens.values;

  /// The first occurrence of each registered token in [source], in document
  /// order.
  List<ComposerUploadSlot> find(String source) {
    final found = <int>{};
    return [
      for (final slot in _occurrences(source))
        if (found.add(slot.id)) slot,
    ];
  }

  /// [source] without any registered token, each taking the line break that
  /// follows it.
  String strip(String source) {
    StringBuffer? kept;
    var copied = 0;
    for (final slot in _occurrences(source)) {
      if (slot.start < copied) continue;
      (kept ??= StringBuffer()).write(source.substring(copied, slot.start));
      copied = slot.start + slot.token.length;
      if (source.startsWith('\n', copied)) copied++;
    }
    if (kept == null) return source;
    return (kept..write(source.substring(copied))).toString();
  }

  Iterable<ComposerUploadSlot> _occurrences(String source) sync* {
    if (_tokens.isEmpty) return;
    for (
      var start = source.indexOf(_prefix);
      start >= 0;
      start = source.indexOf(_prefix, start + 1)
    ) {
      var id = 0;
      for (var at = start + _prefix.length; at < source.length; at++) {
        final digit = source.codeUnitAt(at) - 0x30;
        if (digit < 0 || digit > 9) break;
        id = id * 10 + digit;
      }
      final token = _tokens[id];
      if (token != null && source.startsWith(token, start)) {
        yield (id: id, start: start, token: token);
      }
    }
  }
}

/// Projects draft-local upload slots through the editor's existing block API.
/// Tokens are removed from saved/submitted Markdown by the composer owner.
final class ComposerUploadPlaceholderPolicy implements ComposerSyntaxPolicy {
  ComposerUploadPlaceholderPolicy(this.composer);

  final ComposerController composer;

  @override
  ComposerSyntaxKind get kind => const ComposerSyntaxKind(
    owner: PluginId('core'),
    name: 'upload',
    label: 'Upload',
  );

  @override
  Object? get projectionState => null;

  @override
  TextInputFormatter get inputFormatter => _UploadInputFormatter(this);

  @override
  List<ComposerSyntaxProjection> parse(String source) => [
    for (final slot in composer.uploadPlaceholders.find(source))
      _UploadProjection(composer, slot.id, slot.start, slot.token),
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
