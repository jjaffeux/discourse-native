import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// The annotation exists only in the native presentation, never in a Post.
const placeholderFieldAttribute = 'data-native-placeholder-field';

final class PlaceholderDefinition {
  const PlaceholderDefinition({
    required this.key,
    required this.delimiter,
    required this.defaults,
    this.defaultValue,
  });

  final String key;
  final String delimiter;
  final String? defaultValue;
  final List<String> defaults;
  String get token => '$delimiter$key$delimiter';
}

/// A parsed source template. Each projection starts from its untouched DOM.
final class PlaceholderDocument {
  PlaceholderDocument._(
    this.source,
    this._template,
    this.definitions,
    this.fields,
  );

  factory PlaceholderDocument.parse(String source) {
    final fragment = html.parseFragment(source);
    final definitions = <String, PlaceholderDefinition>{};
    final fields = <String>[];
    for (final element in fragment.querySelectorAll(
      '.d-wrap[data-wrap="placeholder"]',
    )) {
      if (element.localName != 'div' && element.localName != 'span') continue;
      final key = element.attributes['data-key'];
      if (key == null || key.isEmpty) continue;
      final delimiter = element.attributes['data-delimiter'];
      definitions[key] = PlaceholderDefinition(
        key: key,
        delimiter: delimiter == null || delimiter.isEmpty ? '=' : delimiter,
        defaultValue: element.attributes['data-default'],
        defaults: List.unmodifiable(
          (element.attributes['data-defaults'] ?? '')
              .split(',')
              .where((v) => v.isNotEmpty),
        ),
      );
      element.attributes[placeholderFieldAttribute] = '${fields.length}';
      fields.add(key);
    }
    return PlaceholderDocument._(
      source,
      fragment,
      Map.unmodifiable(definitions),
      List.unmodifiable(fields),
    );
  }

  final String source;
  final dom.DocumentFragment _template;
  final Map<String, PlaceholderDefinition> definitions;
  final List<String> fields;

  String render(Map<String, String> overrides) {
    if (definitions.isEmpty) return source;
    final fragment = _template.clone(true);
    String replace(String source) {
      var result = source;
      for (final definition in definitions.values) {
        final value = overrides[definition.key] ?? definition.defaultValue;
        if (value != null && value.isNotEmpty && value != 'none') {
          result = result.replaceAll(definition.token, value);
        }
      }
      return result;
    }

    // Visit each text node once even when eligible ancestors overlap. Replacing
    // DOM text/attributes escapes values on serialization, preserving markup.
    final pending = <({dom.Node node, bool eligible})>[
      for (final node in fragment.nodes.reversed) (node: node, eligible: false),
    ];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      final node = current.node;
      if (node is dom.Text) {
        if (current.eligible) node.data = replace(node.data);
      } else if (node is dom.Element) {
        final eligible =
            current.eligible ||
            _textTags.contains(node.localName) ||
            node.classes.contains('md-table');
        if (node.attributes['href'] case final href?
            when node.localName == 'a') {
          node.attributes['href'] = replace(href);
        }
        for (final child in node.nodes.reversed) {
          pending.add((node: child, eligible: eligible));
        }
      }
    }
    return fragment.outerHtml;
  }

  static const _textTags = {
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'p',
    'code',
    'blockquote',
    'li',
  };
}
