import 'package:discourse_native/discourse_plugin_composer.dart';
import 'package:discourse_native/discourse_plugin_contracts.dart';

import 'local_date_composer_parser.dart';

const localDateComposerSyntaxId = 'discourse-local-dates/local-date';

abstract interface class LocalDateComposerProjectionData {
  LocalDateComposerBlock get localDateBlock;
}

extension LocalDateComposerEditing on MarkdownEditingController {
  List<LocalDateComposerBlock> get localDateBlocks => [
    for (final occurrence in syntaxBlocks) ?_localDateBlock(occurrence),
  ];

  LocalDateComposerBlock? collapsedLocalDateAtOffset(int offset) {
    final occurrence = collapsedSyntaxAtOffset(offset);
    return occurrence == null ? null : _localDateBlock(occurrence);
  }

  LocalDateComposerBlock? get keyboardSelectedLocalDate {
    final occurrence = keyboardSelectedSyntax;
    return occurrence == null ? null : _localDateBlock(occurrence);
  }
}

LocalDateComposerBlock? _localDateBlock(ComposerSyntaxOccurrence occurrence) {
  if (occurrence.kind.id != localDateComposerSyntaxId) return null;
  return switch (occurrence.projection) {
    final LocalDateComposerProjectionData projection =>
      projection.localDateBlock,
    _ => null,
  };
}
