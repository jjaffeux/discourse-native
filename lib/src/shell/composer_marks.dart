import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:super_editor/super_editor.dart';

/// The inline HTML tags Discourse keeps when it cooks a post.
///
/// Taken from the rich editor's own `ALLOWED_INLINE`
/// (`static/prosemirror/extensions/html-inline.js`). Core models all of them as
/// one node with a `tag` attribute rather than one type each, and this follows
/// that: one attribution, parameterised by tag.
const Set<String> allowedInlineTags = {
  'kbd',
  'sup',
  'sub',
  'mark',
  'small',
  'big',
  'ins',
  'del',
};

/// A mark the toolbar can turn on and off.
///
/// Carries both halves because the two surfaces mean different things by it:
/// in the plain field it is a pair of characters in the text, in the rich one
/// it is an attribution over a range. The button is the same either way.
enum ComposerMark {
  bold('**', boldAttribution),
  italic('*', italicsAttribution);

  const ComposerMark(this.marker, this.attribution);

  /// What wraps the text in markdown.
  final String marker;

  /// What carries it in a document.
  final Attribution attribution;
}

/// Wraps the selection in [marker], or unwraps it if it is already wrapped.
///
/// Pure, so the fiddly part — what counts as already wrapped — is testable
/// without a widget. A collapsed selection inserts the pair and puts the caret
/// between them, which is what someone pressing bold before typing expects.
TextEditingValue toggleMarkdownMark(TextEditingValue value, String marker) {
  final text = value.text;
  final selection = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: text.length);

  final start = selection.start;
  final end = selection.end;
  final selected = text.substring(start, end);
  final before = text.substring(0, start);
  final after = text.substring(end);

  // Already wrapped, with the markers inside the selection.
  if (_isWrapped(selected, marker)) {
    final inner = selected.substring(
      marker.length,
      selected.length - marker.length,
    );
    return TextEditingValue(
      text: '$before$inner$after',
      selection: TextSelection(
        baseOffset: start,
        extentOffset: start + inner.length,
      ),
    );
  }

  // Already wrapped, with the markers just outside it — which is what you get
  // by double-clicking a bold word.
  if (_endsWithMark(before, marker) && _startsWithMark(after, marker)) {
    final trimmedBefore = before.substring(0, before.length - marker.length);
    return TextEditingValue(
      text: '$trimmedBefore$selected${after.substring(marker.length)}',
      selection: TextSelection(
        baseOffset: trimmedBefore.length,
        extentOffset: trimmedBefore.length + selected.length,
      ),
    );
  }

  final caret = start + marker.length;
  return TextEditingValue(
    text: '$before$marker$selected$marker$after',
    selection: selection.isCollapsed
        ? TextSelection.collapsed(offset: caret)
        : TextSelection(
            baseOffset: caret,
            extentOffset: caret + selected.length,
          ),
  );
}

bool _isWrapped(String text, String marker) {
  if (text.length < marker.length * 2) return false;
  if (!text.startsWith(marker) || !text.endsWith(marker)) return false;
  // `**bold**` is not italic text, so pressing italic on it must add a mark
  // rather than peel one off a longer run.
  return !_continuesRun(text.substring(marker.length), marker);
}

bool _endsWithMark(String before, String marker) =>
    before.endsWith(marker) &&
    !_continuesRun(
      before
          .substring(0, before.length - marker.length)
          .split('')
          .reversed
          .join(),
      marker,
    );

bool _startsWithMark(String after, String marker) =>
    after.startsWith(marker) &&
    !_continuesRun(after.substring(marker.length), marker);

/// Whether [rest] carries on a run of the marker's character, which would mean
/// the marker found is part of a longer one.
bool _continuesRun(String rest, String marker) =>
    marker.length == 1 && rest.startsWith(marker);

/// One of [allowedInlineTags] wrapped around a span of text.
///
/// The tag is part of the id, so `<sup>` inside `<mark>` are two attributions
/// that may overlap — attributions sharing an id cannot.
@immutable
class HtmlInlineAttribution implements Attribution {
  const HtmlInlineAttribution(this.tag);

  final String tag;

  @override
  String get id => 'discourse-html-$tag';

  @override
  bool canMergeWith(Attribution other) => other == this;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HtmlInlineAttribution && other.tag == tag);

  @override
  int get hashCode => tag.hashCode;

  @override
  String toString() => '<$tag>';
}

/// A person. The document text stays `@name`, so this carries no content of its
/// own — it exists to be styled, and to be recognised on the way back out.
@immutable
class MentionAttribution implements Attribution {
  const MentionAttribution(this.username);

  final String username;

  @override
  String get id => 'discourse-mention';

  @override
  bool canMergeWith(Attribution other) => other == this;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MentionAttribution && other.username == username);

  @override
  int get hashCode => username.hashCode;

  @override
  String toString() => '@$username';
}

/// Matches `<kbd>…</kbd>` and friends, emitting an element whose tag is the
/// HTML tag so the visitor below can turn it into an attribution.
class _HtmlInlineSyntax extends md.InlineSyntax {
  _HtmlInlineSyntax()
    : super('<(${allowedInlineTags.join('|')})>([\\s\\S]*?)</\\1>');

  /// Namespaced, because `~~x~~` also parses to a `del` element and the two
  /// must serialise back differently.
  static const String prefix = 'discourse-html:';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element('$prefix${match[1]}', [md.Text(match[2]!)]));
    return true;
  }
}

/// Matches `@name`, keeping the literal source text as the element's content —
/// which is what makes serialising it back a no-op.
class _MentionSyntax extends md.InlineSyntax {
  _MentionSyntax() : super(r'@([a-zA-Z0-9_.-]+)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(_mentionTag, match[0]!));
    return true;
  }
}

const String _mentionTag = 'discourse-mention';

AttributedText? _htmlInlineToAttribution(
  md.Element element,
  AttributedText text,
) {
  if (!element.tag.startsWith(_HtmlInlineSyntax.prefix) || text.isEmpty) {
    return null;
  }
  return text..addAttribution(
    HtmlInlineAttribution(
      element.tag.substring(_HtmlInlineSyntax.prefix.length),
    ),
    SpanRange(0, text.length - 1),
  );
}

AttributedText? _mentionToAttribution(md.Element element, AttributedText text) {
  if (element.tag != _mentionTag || text.isEmpty) return null;
  return text..addAttribution(
    MentionAttribution(text.toPlainText().substring(1)),
    SpanRange(0, text.length - 1),
  );
}

/// Reads Discourse-flavoured markdown into an editable document.
MutableDocument discourseMarkdownToDocument(String markdown) {
  return deserializeMarkdownToDocument(
    markdown,
    // Replaces the defaults rather than adding to them, so the ones worth
    // keeping are listed again here.
    inlineMarkdownSyntaxes: [
      _HtmlInlineSyntax(),
      _MentionSyntax(),
      md.StrikethroughSyntax(),
    ],
    inlineHtmlSyntaxes: const [
      _htmlInlineToAttribution,
      _mentionToAttribution,
      boldHtmlSyntax,
      italicHtmlSyntax,
      // `~~x~~` arrives as a `del` element; a literal `<del>` arrived
      // namespaced above, so these no longer collide.
      strikethroughHtmlSyntax,
      codeInlineHtmlSyntax,
      anchorHtmlSyntax,
    ],
    // Discourse allows inline HTML, so escaping `<` here would corrupt every
    // post that contains one.
    encodeHtml: false,
  );
}

/// Writes a document back out as the markdown that will be posted.
String discourseDocumentToMarkdown(Document document) =>
    serializeDocumentToMarkdown(
      document,
      customNodeSerializers: const [_DiscourseParagraphSerializer()],
    ).trimRight();

/// Whether [markdown] can be edited richly without rewriting it.
///
/// The composer posts raw markdown, so a document model is only safe for text
/// it can return unchanged. Anything that does not survive stays in the plain
/// field — the same bargain core makes when it refuses rich mode for a post it
/// cannot represent.
bool richModeAvailable(String markdown) {
  if (markdown.trim().isEmpty) return true;
  try {
    return discourseDocumentToMarkdown(discourseMarkdownToDocument(markdown)) ==
        markdown.trimRight();
  } catch (_) {
    return false;
  }
}

/// Serialises paragraphs ourselves.
///
/// The built-in inline serialiser walks a fixed list of five attributions and
/// never sees any other, so our marks would come back as bare text with their
/// tags dropped. Custom serialisers run first, which is what lets this replace
/// it rather than sit behind it.
class _DiscourseParagraphSerializer
    extends NodeTypedDocumentNodeMarkdownSerializer<ParagraphNode> {
  const _DiscourseParagraphSerializer();

  @override
  String doSerialization(
    Document document,
    ParagraphNode node, {
    NodeSelection? selection,
  }) {
    final buffer = StringBuffer();
    final blockType = node.getMetadataValue('blockType');
    if (blockType is NamedAttribution) {
      buffer.write(switch (blockType.id) {
        'header1' => '# ',
        'header2' => '## ',
        'header3' => '### ',
        'header4' => '#### ',
        'header5' => '##### ',
        'header6' => '###### ',
        'blockquote' => '> ',
        _ => '',
      });
    }
    buffer.write(inlineToMarkdown(node.text));
    return buffer.toString();
  }
}

/// Turns attributed text back into markdown.
///
/// Walks the text one character at a time, closing the marks that ended and
/// opening the ones that began. Order matters on the way out: marks close in
/// the reverse of the order they opened, or the tags interleave illegally.
@visibleForTesting
String inlineToMarkdown(AttributedText text) {
  final plain = text.toPlainText();
  if (plain.isEmpty) return '';

  final buffer = StringBuffer();
  final open = <Attribution>[];

  for (var i = 0; i < plain.length; i++) {
    final here = text.getAllAttributionsAt(i);

    // Close, innermost first, anything that does not continue here.
    while (open.isNotEmpty && !here.contains(open.last)) {
      buffer.write(_close(open.removeLast()));
    }
    for (final attribution in here) {
      if (open.contains(attribution)) continue;
      final marker = _open(attribution);
      if (marker == null) continue;
      open.add(attribution);
      buffer.write(marker);
    }
    buffer.write(plain[i]);
  }

  while (open.isNotEmpty) {
    buffer.write(_close(open.removeLast()));
  }
  return buffer.toString();
}

String? _open(Attribution attribution) => switch (attribution) {
  HtmlInlineAttribution(:final tag) => '<$tag>',
  // The text is already `@name`; the attribution is only there to style it.
  MentionAttribution() => null,
  _ when attribution == boldAttribution => '**',
  _ when attribution == italicsAttribution => '*',
  _ when attribution == strikethroughAttribution => '~~',
  _ when attribution == codeAttribution => '`',
  LinkAttribution() => '[',
  _ => null,
};

String _close(Attribution attribution) => switch (attribution) {
  HtmlInlineAttribution(:final tag) => '</$tag>',
  _ when attribution == boldAttribution => '**',
  _ when attribution == italicsAttribution => '*',
  _ when attribution == strikethroughAttribution => '~~',
  _ when attribution == codeAttribution => '`',
  LinkAttribution(:final plainTextUri) => ']($plainTextUri)',
  _ => '',
};

/// How a marked span is drawn.
///
/// This is the hook Parchment has no equivalent of: styling is a function of
/// the attributions on a span, so a mark we invented is drawn like anything
/// else rather than needing the editor to know about it.
TextStyle discourseInlineStyle(
  Set<Attribution> attributions,
  TextStyle base,
  ThemeData theme,
) {
  var style = base;
  for (final attribution in attributions) {
    style = switch (attribution) {
      MentionAttribution() => style.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
      HtmlInlineAttribution(:final tag) => switch (tag) {
        'kbd' => style.copyWith(
          fontFamily: 'monospace',
          fontSize: (style.fontSize ?? 14) * 0.9,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
        'mark' => style.copyWith(
          backgroundColor: theme.colorScheme.tertiaryContainer,
          color: theme.colorScheme.onTertiaryContainer,
        ),
        'sup' => style.copyWith(
          fontFeatures: const [FontFeature.superscripts()],
        ),
        'sub' => style.copyWith(fontFeatures: const [FontFeature.subscripts()]),
        'small' => style.copyWith(fontSize: (style.fontSize ?? 14) * 0.85),
        'big' => style.copyWith(fontSize: (style.fontSize ?? 14) * 1.15),
        'ins' => style.copyWith(decoration: TextDecoration.underline),
        'del' => style.copyWith(decoration: TextDecoration.lineThrough),
        _ => style,
      },
      _ when attribution == boldAttribution => style.copyWith(
        fontWeight: FontWeight.bold,
      ),
      _ when attribution == italicsAttribution => style.copyWith(
        fontStyle: FontStyle.italic,
      ),
      _ when attribution == strikethroughAttribution => style.copyWith(
        decoration: TextDecoration.lineThrough,
      ),
      _ when attribution == codeAttribution => style.copyWith(
        fontFamily: 'monospace',
      ),
      LinkAttribution() => style.copyWith(color: theme.colorScheme.primary),
      _ => style,
    };
  }
  return style;
}
