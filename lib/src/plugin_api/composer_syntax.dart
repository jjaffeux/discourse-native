import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shell/composer_controller.dart';

/// One plugin-owned, losslessly recognised source range in a composer.
final class ComposerSyntaxOccurrence {
  const ComposerSyntaxOccurrence(this.plugin, this.value);

  final ComposerSyntaxPlugin plugin;
  final Object value;

  int get start => plugin.startOf(value);
  int get end => plugin.endOf(value);
  String get source => plugin.sourceOf(value);

  bool sameAs(ComposerSyntaxOccurrence? other) =>
      other != null &&
      identical(plugin, other.plugin) &&
      start == other.start &&
      end == other.end &&
      source == other.source;
}

/// Extends the markdown composer with a lossless plugin-owned projection.
///
/// Core retains the raw document and owns range ordering. The plugin owns all
/// syntax vocabulary, validation, artwork, editing, removal, and any special
/// caret behavior. Returning no occurrences leaves source completely literal.
abstract interface class ComposerSyntaxPlugin {
  String get syntaxId;

  List<Object> parseComposerSyntax(String source);

  int startOf(Object value);

  int endOf(Object value);

  String sourceOf(Object value);

  bool needsRawSource(
    Object value,
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  });

  int caretAfter(Object value, String document) => endOf(value);

  /// Applies any source normalization needed before placing the caret after
  /// this occurrence.
  TextEditingValue moveCaretAfter(Object value, TextEditingValue document);

  bool get supportsHover => false;

  bool get protectsAdjacentDelete => false;

  bool get hidesCursorWhenSelected => false;

  List<InlineSpan> buildCollapsedSpans({
    required Object value,
    required TextStyle baseStyle,
    required Locale locale,
    required String? accountTimezone,
    required int maximumOptions,
    required GlobalKey pillKey,
    required bool highlighted,
    required bool hovered,
    required bool followedByLineBreak,
  });

  FutureOr<void> editComposerSyntax(
    BuildContext context,
    ComposerController composer,
    Object value,
  );

  FutureOr<void> removeComposerSyntax(
    BuildContext context,
    ComposerController composer,
    Object value,
  );

  TextInputFormatter? get inputFormatter => null;
}

/// Adds keyboard commands whose availability is owned by a plugin.
abstract interface class ComposerShortcutPlugin {
  Map<ShortcutActivator, VoidCallback> composerShortcuts(
    BuildContext context,
    ComposerController composer,
  );
}
