import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// Server checklist targets count owned checkboxes, including permanent ones.
class PostChecklistTarget {
  const PostChecklistTarget({
    required this.index,
    required this.count,
    required this.checked,
    required this.permanent,
    this.source,
  });

  final int index;
  final int count;
  final bool checked;
  final bool permanent;
  final String? source;

  Map<String, Object?> toggle(bool checked) => {
    'checkbox_index': index,
    if (source != null) 'checkbox_source': source else 'checkbox_count': count,
    'checked': checked,
  };
}

class PostChecklistUpdate {
  const PostChecklistUpdate({
    required this.raw,
    required this.cooked,
    required this.updatedAt,
    required this.version,
  });

  final String raw;
  final String cooked;
  final DateTime updatedAt;
  final int version;
}

/// Shared target mapping for rendering, optimistic state and backend requests.
class PostChecklistDocument {
  PostChecklistDocument(String source) : this._(html.parseFragment(source));

  PostChecklistDocument._(this._document);

  static const indexAttribute = 'data-native-checklist-index';
  final dom.DocumentFragment _document;
  late final List<dom.Element> _boxes = _ownedBoxes(_document);

  static List<dom.Element> _ownedBoxes(
    dom.DocumentFragment document, {
    bool clearIndexes = false,
  }) {
    final boxes = <dom.Element>[];
    void visit(dom.Node parent, {bool quoted = false}) {
      for (final node in parent.nodes) {
        if (node is! dom.Element) continue;
        if (clearIndexes) node.attributes.remove(indexAttribute);
        final excluded =
            quoted ||
            (node.localName == 'aside' &&
                node.classes.contains('quote') &&
                (node.attributes.containsKey('data-username') ||
                    node.attributes.containsKey('data-post') ||
                    node.attributes.containsKey('data-topic')));
        if (!excluded &&
            node.localName == 'span' &&
            node.classes.contains('chcklst-box')) {
          boxes.add(node);
        }
        if (!excluded || clearIndexes) visit(node, quoted: excluded);
      }
    }

    visit(document);
    return boxes;
  }

  static final _sourcePattern = RegExp(r'^\d+:\d+$');

  late final List<PostChecklistTarget> targets = List.unmodifiable([
    for (var i = 0; i < _boxes.length; i++)
      PostChecklistTarget(
        index: i,
        count: _boxes.length,
        checked: _boxes[i].classes.contains('checked'),
        permanent: _boxes[i].classes.contains('permanent'),
        source:
            _sourcePattern.hasMatch(_boxes[i].attributes['data-chk-src'] ?? '')
            ? _boxes[i].attributes['data-chk-src']
            : null,
      ),
  ]);

  static String contentKey(String source) => source.contains('chcklst-box')
      ? PostChecklistDocument(source).fingerprint
      : source;

  /// Every build of a checklist post renders this, so it is kept rather than
  /// derived again: nothing modifies the parsed tree it is derived from.
  late final String annotatedHtml = _annotate();

  String _annotate() {
    final copy = _document.clone(true);
    // Untrusted markup cannot supply an index for an excluded quote.
    final boxes = _ownedBoxes(copy, clearIndexes: true);
    for (var i = 0; i < boxes.length; i++) {
      boxes[i].attributes[indexAttribute] = '$i';
    }
    return copy.outerHtml;
  }

  String withStates(Map<int, bool> states) {
    final copy = PostChecklistDocument._(_document.clone(true));
    for (final entry in states.entries) {
      if (entry.key < 0 || entry.key >= copy._boxes.length) continue;
      final box = copy._boxes[entry.key];
      if (box.classes.contains('permanent')) continue;
      box.classes.removeAll(['checked', 'fa-square-o', 'fa-square-check-o']);
      box.classes.add(entry.value ? 'fa-square-check-o' : 'fa-square-o');
      if (entry.value) box.classes.add('checked');
      if (box.attributes.containsKey('aria-checked')) {
        box.attributes['aria-checked'] = '${entry.value}';
      }
    }
    return copy._document.outerHtml;
  }

  /// Core guards edits with Markdown, since saving recooks the entire post.
  /// Ignore only mutable checkbox markers at their physical source locations.
  String? rawFingerprint(String raw) {
    final mutable = targets.where((target) => !target.permanent);
    if (mutable.any((target) => target.source == null)) {
      // Match core's fallback for posts cooked before source hints existed.
      return raw.replaceAll(RegExp(r'\[(?: |x)?\]'), '[ ]');
    }
    final sources = <int, Set<int>>{};
    for (final target in mutable) {
      final parts = target.source!.split(':');
      final line = int.tryParse(parts[0]);
      final ordinal = int.tryParse(parts[1]);
      if (line == null || ordinal == null) return null;
      if (!(sources[line] ??= <int>{}).add(ordinal)) return null;
    }
    final lines = raw.split(RegExp(r'\r\n?|\n'));
    for (final entry in sources.entries) {
      if (entry.key >= lines.length) return null;
      final markers = RegExp(
        r'\[[ xX]?\]',
      ).allMatches(lines[entry.key]).toList();
      for (final ordinal in entry.value) {
        if (ordinal >= markers.length || markers[ordinal][0] == '[X]') {
          return null;
        }
      }
      var ordinal = 0;
      lines[entry.key] = lines[entry.key].replaceAllMapped(
        RegExp(r'\[[ xX]?\]'),
        (match) => entry.value.contains(ordinal++) ? '[ ]' : match[0]!,
      );
    }
    return lines.join('\n');
  }

  /// Pending clicks use rendered indexes. A recook may add source hints to
  /// legacy boxes, but must not move existing sources or change the controls.
  bool hasSameTargets(PostChecklistDocument other) {
    if (targets.length != other.targets.length) return false;
    for (var i = 0; i < targets.length; i++) {
      final before = targets[i];
      final after = other.targets[i];
      if (before.permanent != after.permanent ||
          (before.source != null && before.source != after.source)) {
        return false;
      }
    }
    return true;
  }

  String get fingerprint {
    final copy = PostChecklistDocument._(_document.clone(true));
    for (final box in copy._boxes) {
      box.attributes.remove(indexAttribute);
      box.attributes.remove('data-chk-src');
      box.attributes.remove('aria-checked');
      if (!box.classes.contains('permanent')) {
        box.classes.removeAll(['checked', 'fa-square-o', 'fa-square-check-o']);
      }
    }
    return copy._document.outerHtml;
  }
}
