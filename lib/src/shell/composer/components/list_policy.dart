import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../plugin_api/composer_syntax.dart';
import '../component_editing_host.dart';
import '../component_editor.dart';
import 'list_source.dart';

ComposerSyntaxKind get composerListSyntaxKind => ComposerSyntaxKind(
  owner: const PluginId('core'),
  name: 'list-item',
  label: appL10n.list,
);

final class ComposerListPolicy implements ComposerSyntaxPolicy {
  const ComposerListPolicy(
    this.composer, {
    required this.embeddedInList,
    required this.render,
  });
  final bool embeddedInList;
  final Widget Function(ComposerSyntaxRenderContext, ComposerListItem) render;
  final ComposerComponentEditingHost composer;
  @override
  ComposerSyntaxKind get kind => composerListSyntaxKind;
  @override
  Object get projectionState =>
      (composer.isEditing, composer.text.todoReferenceMarkers);
  @override
  TextInputFormatter? get inputFormatter => null;
  @override
  List<ComposerSyntaxProjection> parse(String source) => [
    for (final item
        in composer.text
            .sourceAnalysisFor(source)
            .listItems(referenceMarkers: composer.text.todoReferenceMarkers))
      // Wait for the separating space while a marker is being typed.
      if (item.source.length >= 2 &&
          item.contentStart > item.start + item.indent + item.marker.length)
        _ListProjection(item, embeddedInList, render),
  ];
}

final class _ListProjection
    implements
        ComposerInteractiveSyntaxProjection,
        ComposerParagraphSpacingProjection {
  _ListProjection(this.item, this.embeddedInList, this.render);
  final bool embeddedInList;
  final Widget Function(ComposerSyntaxRenderContext, ComposerListItem) render;
  final ComposerListItem item;
  GlobalKey? _key;
  @override
  int get start => item.start;
  @override
  int get end => item.end;
  @override
  String get source => item.source;
  @override
  bool get supportsHover => false;
  @override
  bool get protectsAdjacentDelete => true;
  @override
  bool needsRawSource(
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) =>
      !document.composing.isCollapsed &&
      document.composing.start < item.contentStart &&
      document.composing.end > item.start;
  @override
  int caretAfter(String document) =>
      end +
      (document.startsWith('\r\n', end)
          ? 2
          : document.startsWith('\n', end)
          ? 1
          : 0);
  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) =>
      document.copyWith(
        selection: TextSelection.collapsed(offset: caretAfter(document.text)),
        composing: TextRange.empty,
      );
  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) {
    _key = context.pillKey;
    return [
      WidgetSpan(
        // The embedded editor owns its line spacing. Top alignment would add
        // the outer paragraph's ascent leading before the first line again.
        alignment: PlaceholderAlignment.middle,
        style: context.baseStyle,
        child: render(context, item),
      ),
      TextSpan(
        text: embeddedInList && end == item.document.length ? '\u200b' : '\n',
        style: context.baseStyle.copyWith(color: Colors.transparent),
      ),
      TextSpan(
        text: source.substring(2),
        semanticsLabel: '',
        style: const TextStyle(
          fontSize: 0,
          height: 0,
          letterSpacing: 0,
          color: Colors.transparent,
        ),
      ),
    ];
  }

  @override
  void edit(BuildContext context, ComposerEditorHost editor) {
    if (_key?.currentState case final ComposerComponentEditor editor) {
      editor.edit();
    }
  }

  @override
  void remove(BuildContext context, ComposerEditorHost editor) {
    if (!editor.isEditing) return;
    final value = editor.value;
    if (end > value.text.length || value.text.substring(start, end) != source) {
      return;
    }
    editor.commitText(
      expectedText: value.text,
      value: TextEditingValue(
        text: value.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      ),
    );
  }
}
