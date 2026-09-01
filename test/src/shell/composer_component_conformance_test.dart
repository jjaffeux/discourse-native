import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/material.dart';

import '../../support/composer_component_conformance.dart';

const _owner = PluginId('composer-conformance-fixtures');
const _dateKind = ComposerSyntaxKind(owner: _owner, name: 'date');
const _gridKind = ComposerSyntaxKind(owner: _owner, name: 'grid');
const _dateSource = '[date:2026-09-01]';
const _dateMarkdown = 'Before $_dateSource after';
const _gridSource = '''[grid]
- Tea
- Coffee
[/grid]''';
const _gridMarkdown =
    '''Before
$_gridSource
after''';

void main() {
  runComposerComponentConformance<String>(
    name: 'inline date fixture',
    component: const ComposerComponent<String>.inline(
      kind: _dateKind,
      find: _findDates,
      builder: _buildDate,
      semanticLabel: _dateLabel,
    ),
    markdown: _dateMarkdown,
    expectedRange: _rangeOf(_dateMarkdown, _dateSource),
    expectedLayout: ComposerComponentLayout.inline,
  );

  runComposerComponentConformance<List<String>>(
    name: 'block grid fixture',
    component: const ComposerComponent<List<String>>.block(
      kind: _gridKind,
      find: _findGrids,
      builder: _buildGrid,
      semanticLabel: _gridLabel,
    ),
    markdown: _gridMarkdown,
    expectedRange: _rangeOf(_gridMarkdown, _gridSource),
    expectedLayout: ComposerComponentLayout.block,
  );
}

TextRange _rangeOf(String markdown, String source) {
  final start = markdown.indexOf(source);
  return TextRange(start: start, end: start + source.length);
}

Iterable<ComposerComponentCandidate<String>> _findDates(String markdown) {
  return RegExp(r'\[date:([^\]]+)\]').allMatches(markdown).map((match) {
    return ComposerComponentCandidate<String>(
      range: TextRange(start: match.start, end: match.end),
      value: match.group(1)!,
    );
  });
}

Iterable<ComposerComponentCandidate<List<String>>> _findGrids(String markdown) {
  return RegExp(r'\[grid\]\n([\s\S]*?)\n\[/grid\]').allMatches(markdown).map((
    match,
  ) {
    final options = match
        .group(1)!
        .split('\n')
        .map((line) => line.substring(2))
        .toList(growable: false);
    return ComposerComponentCandidate<List<String>>(
      range: TextRange(start: match.start, end: match.end),
      value: options,
    );
  });
}

Widget _buildDate(
  BuildContext context,
  ComposerComponentRenderContext<String> component,
) {
  return Text(component.value);
}

String _dateLabel(
  BuildContext context,
  ComposerComponentPresentation<String> component,
) {
  return 'Date ${component.value}';
}

Widget _buildGrid(
  BuildContext context,
  ComposerComponentRenderContext<List<String>> component,
) {
  return Column(
    children: component.value.map(Text.new).toList(growable: false),
  );
}

String _gridLabel(
  BuildContext context,
  ComposerComponentPresentation<List<String>> component,
) {
  return 'Grid with ${component.value.length} rows';
}
