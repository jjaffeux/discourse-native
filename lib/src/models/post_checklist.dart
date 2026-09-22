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
  PostChecklistDocument(String source)
    : _document = html.parseFragment(source) {
    _boxes = _document.querySelectorAll('span.chcklst-box').where((box) {
      for (var parent = box.parent; parent != null; parent = parent.parent) {
        if (parent.localName == 'aside' &&
            parent.classes.contains('quote') &&
            [
              'data-username',
              'data-post',
              'data-topic',
            ].any(parent.attributes.containsKey)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  static const indexAttribute = 'data-native-checklist-index';
  final dom.DocumentFragment _document;
  late final List<dom.Element> _boxes;

  late final List<PostChecklistTarget> targets = List.unmodifiable([
    for (var i = 0; i < _boxes.length; i++)
      PostChecklistTarget(
        index: i,
        count: _boxes.length,
        checked: _boxes[i].classes.contains('checked'),
        permanent: _boxes[i].classes.contains('permanent'),
        source:
            RegExp(
              r'^\d+:\d+$',
            ).hasMatch(_boxes[i].attributes['data-chk-src'] ?? '')
            ? _boxes[i].attributes['data-chk-src']
            : null,
      ),
  ]);

  static String contentKey(String source) => source.contains('chcklst-box')
      ? PostChecklistDocument(source).fingerprint
      : source;

  String get annotatedHtml {
    final copy = PostChecklistDocument(_document.outerHtml);
    // Untrusted markup cannot supply an index for an excluded quote.
    for (final node in copy._document.querySelectorAll('[$indexAttribute]')) {
      node.attributes.remove(indexAttribute);
    }
    for (var i = 0; i < copy._boxes.length; i++) {
      copy._boxes[i].attributes[indexAttribute] = '$i';
    }
    return copy._document.outerHtml;
  }

  String withStates(Map<int, bool> states) {
    final copy = PostChecklistDocument(_document.outerHtml);
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

  String get fingerprint {
    final copy = PostChecklistDocument(_document.outerHtml);
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
