import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _kind = ComposerSyntaxKind(owner: PluginId('example'), name: 'mention');

void main() {
  test('typed finder proposes ranges without copying source', () {
    const component = ComposerComponent<String>.inline(
      kind: _kind,
      find: _findMentions,
      builder: _buildMention,
      semanticLabel: _mentionLabel,
    );

    final candidate = component.find('Hello @sam').single;

    expect(component.layout, ComposerComponentLayout.inline);
    expect(component.precedence, 0);
    expect(candidate.range, const TextRange(start: 6, end: 10));
    expect(candidate.value, 'sam');
  });

  testWidgets('rendering and semantics use a raw-free presentation', (
    tester,
  ) async {
    const renderContext = ComposerComponentRenderContext<String>(
      range: TextRange(start: 6, end: 10),
      value: 'sam',
      baseStyle: TextStyle(fontSize: 18),
      selected: true,
      hovered: false,
    );
    const component = ComposerComponent<String>.block(
      kind: _kind,
      precedence: 7,
      find: _findMentions,
      builder: _buildMention,
      semanticLabel: _mentionLabel,
    );

    late BuildContext buildContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            buildContext = context;
            return component.builder(context, renderContext);
          },
        ),
      ),
    );

    expect(component.layout, ComposerComponentLayout.block);
    expect(component.precedence, 7);
    const presentation = ComposerComponentPresentation<String>(
      range: TextRange(start: 6, end: 10),
      value: 'sam',
    );
    expect(component.semanticLabel(buildContext, presentation), 'Mention sam');
    expect(renderContext.value, 'sam');
    expect(renderContext.start, 6);
    expect(renderContext.end, 10);
    expect(find.text('sam (selected)'), findsOneWidget);
    expect(find.textContaining('@sam'), findsNothing);
  });
}

Iterable<ComposerComponentCandidate<String>> _findMentions(String markdown) {
  return RegExp(r'@(\w+)').allMatches(markdown).map((match) {
    return ComposerComponentCandidate(
      range: TextRange(start: match.start, end: match.end),
      value: match.group(1)!,
    );
  });
}

Widget _buildMention(
  BuildContext context,
  ComposerComponentRenderContext<String> component,
) {
  final selection = component.selected ? ' (selected)' : '';
  return Text('${component.value}$selection', style: component.baseStyle);
}

String _mentionLabel(
  BuildContext context,
  ComposerComponentPresentation<String> component,
) {
  return 'Mention ${component.value}';
}
