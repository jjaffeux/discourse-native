import 'package:flutter/material.dart';

import '../../plugin_api/composer_component.dart';
import '../../plugin_api/composer_syntax.dart';
import 'local_date.dart';
import 'local_date_composer_pill.dart';
import 'local_date_environment.dart';

/// The Local Dates plugin's atomic inline composer declaration.
///
/// Parsing remains lossless: the finder proposes typed blocks and ranges, then
/// the composer captures the exact source before this declaration can render
/// or invoke an action.
ComposerComponent<LocalDateComposerBlock> buildLocalDateComposerComponent({
  required ComposerSyntaxKind kind,
  required LocalDateEnvironment environment,
  required LocalDateFormatter formatter,
  required String? Function() accountTimezone,
  required ComposerComponentAction<LocalDateComposerBlock> onEdit,
  required ComposerComponentAction<LocalDateComposerBlock> onRemove,
}) => ComposerComponent<LocalDateComposerBlock>.inline(
  kind: kind,
  find: (markdown) =>
      parseLocalDateComposerBlocks(markdown, environment: environment).map(
        (block) => ComposerComponentCandidate(
          range: TextRange(start: block.start, end: block.end),
          value: block,
        ),
      ),
  builder: (context, component) {
    final label = _summary(
      context,
      component.value,
      formatter: formatter,
      accountTimezone: accountTimezone(),
    );
    return LocalDateComposerPill(
      label: label,
      baseStyle: component.baseStyle,
      highlighted: component.selected,
    );
  },
  semanticLabel: (context, component) =>
      '${_summary(context, component.value, formatter: formatter, accountTimezone: accountTimezone())}. Activate to edit.',
  onEdit: onEdit,
  onRemove: onRemove,
);

String _summary(
  BuildContext context,
  LocalDateComposerBlock block, {
  required LocalDateFormatter formatter,
  required String? accountTimezone,
}) {
  final summary = localDateComposerSummary(
    block,
    locale: Localizations.maybeLocaleOf(context) ?? const Locale('en'),
    accountTimezone: accountTimezone,
    formatter: formatter,
  );
  return summary == block.source ? 'Local date' : summary;
}
