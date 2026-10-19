import 'package:flutter/widgets.dart';

import '../../plugin_api/composer_syntax.dart';
import 'components/gallery_source.dart';
import 'components/image_source.dart';
import 'components/quote.dart';

/// Input behavior for collapsed source. Artwork and actions stay with features.
sealed class ComposerComponentInput {
  const ComposerComponentInput();

  int get start;
  int get end;
  String get source;

  bool sameAs(ComposerComponentInput? other) =>
      other != null &&
      runtimeType == other.runtimeType &&
      start == other.start &&
      end == other.end &&
      source == other.source;

  bool sameTargetAs(ComposerComponentInput? other);

  int contentEnd(String document) =>
      start + document.substring(start, end).trimRight().length;

  bool containsCaret(int caret, String document) =>
      caret > start && caret < end;

  bool endsAt(int caret, String document) => end == caret;

  int caretBefore(String document) => start == 0
      ? 0
      : start - document.substring(0, start).characters.last.length;

  TextEditingValue moveCaretAfter(TextEditingValue document) =>
      document.copyWith(selection: TextSelection.collapsed(offset: end));
}

final class ComposerImageInput extends ComposerComponentInput {
  const ComposerImageInput(this.image);
  final ComposerImageBlock image;

  @override
  int get start => image.start;
  @override
  int get end => image.end;
  @override
  String get source => image.source;

  @override
  bool sameTargetAs(ComposerComponentInput? other) =>
      other is ComposerImageInput && identical(image, other.image);
}

final class ComposerGalleryInput extends ComposerComponentInput {
  const ComposerGalleryInput(this.gallery);
  final ComposerImageGalleryBlock gallery;

  @override
  int get start => gallery.start;
  @override
  int get end => gallery.end;
  @override
  String get source => gallery.source;

  @override
  bool sameTargetAs(ComposerComponentInput? other) =>
      other is ComposerGalleryInput && identical(gallery, other.gallery);
}

final class ComposerQuoteInput extends ComposerComponentInput {
  const ComposerQuoteInput(this.quote);
  final ComposerQuoteBlock quote;

  @override
  int get start => quote.start;
  @override
  int get end => quote.end;
  @override
  String get source => quote.source;

  @override
  bool sameTargetAs(ComposerComponentInput? other) =>
      other is ComposerQuoteInput && identical(quote, other.quote);

  @override
  bool containsCaret(int caret, String document) =>
      caret > start && caret < quote.contentEnd;

  @override
  bool endsAt(int caret, String document) =>
      end == caret || contentEnd(document) == caret;
}

final class ComposerSyntaxInput extends ComposerComponentInput {
  const ComposerSyntaxInput(this.occurrence);
  final ComposerSyntaxOccurrence occurrence;

  @override
  int get start => occurrence.start;
  @override
  int get end => occurrence.end;
  @override
  String get source => occurrence.source;

  @override
  bool sameTargetAs(ComposerComponentInput? other) =>
      other is ComposerSyntaxInput && identical(occurrence, other.occurrence);

  @override
  bool sameAs(ComposerComponentInput? other) =>
      other is ComposerSyntaxInput && occurrence.sameAs(other.occurrence);

  @override
  bool containsCaret(int caret, String document) =>
      caret > start && caret < contentEnd(document);

  @override
  bool endsAt(int caret, String document) =>
      end == caret ||
      contentEnd(document) == caret ||
      occurrence.projection.caretAfter(document) == caret;

  @override
  int caretBefore(String document) =>
      occurrence.projection is ComposerBlockSyntaxProjection
      ? super.caretBefore(document)
      : start;

  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) =>
      occurrence.projection.moveCaretAfter(document);
}

sealed class ComposerComponentCommand {
  const ComposerComponentCommand();
}

final class ComposerRemoveComponent extends ComposerComponentCommand {
  const ComposerRemoveComponent(this.component);
  final ComposerComponentInput component;
}

final class ComposerSelectComponent extends ComposerComponentCommand {
  const ComposerSelectComponent(this.component);
  final ComposerComponentInput component;
}

final class ComposerSelectPreviousComponent extends ComposerComponentCommand {
  const ComposerSelectPreviousComponent();
}

final class ComposerComponentEdit {
  const ComposerComponentEdit(this.value, [this.command]);
  final TextEditingValue value;
  final ComposerComponentCommand? command;
}

/// A native delete can also begin composing the remaining word in its proposal.
TextRange? composerComponentDeletionRange(
  TextEditingValue oldValue,
  TextEditingValue newValue,
) {
  final removedLength = oldValue.text.length - newValue.text.length;
  if (removedLength <= 0 ||
      !newValue.selection.isValid ||
      !newValue.selection.isCollapsed) {
    return null;
  }
  final start = newValue.selection.extentOffset;
  final end = start + removedLength;
  if (end > oldValue.text.length ||
      newValue.text != oldValue.text.replaceRange(start, end, '')) {
    return null;
  }
  return TextRange(start: start, end: end);
}
