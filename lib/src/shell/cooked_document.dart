import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import '../foundation/bounded_lru_cache.dart';
import '../models/post_checklist.dart';

/// The displayed document owns checkbox authority and all nested fragments.
@immutable
final class CookedDocument {
  CookedDocument(
    String html, {
    String? savedHtml,
    bool revisionDiff = false,
    PostChecklistDocument? checklist,
  }) : checklist = revisionDiff
           ? null
           : checklist ?? _displayedChecklist(html, savedHtml),
       source = html,
       _inheritsChecklist = checklist != null;

  final String source;
  final bool _inheritsChecklist;
  final PostChecklistDocument? checklist;

  CookedFragment get root => fragment(
    _inheritsChecklist ? source : checklist?.annotatedHtml ?? source,
  );

  CookedFragment fragment(String html) => CookedFragment._(this, html);

  CookedContent bind(
    Widget Function(BuildContext, CookedFragment, TextStyle?) builder, {
    void Function(PostChecklistTarget, bool)? onToggle,
  }) => CookedContent._(this, builder, onToggle);
}

@immutable
final class CookedFragment {
  const CookedFragment._(this.document, this.html);

  final CookedDocument document;
  final String html;

  @override
  bool operator ==(Object other) =>
      other is CookedFragment &&
      identical(document, other.document) &&
      html == other.html;

  @override
  int get hashCode => Object.hash(document, html);
}

/// A bound fragment builder keeps adapters inside their owning document.
@immutable
final class CookedContent {
  const CookedContent._(this._document, this._builder, this.onToggle);

  final CookedDocument _document;
  final Widget Function(BuildContext, CookedFragment, TextStyle?) _builder;
  final void Function(PostChecklistTarget, bool)? onToggle;

  Widget call(BuildContext context, String html, {TextStyle? style}) =>
      _builder(context, _document.fragment(html), style);

  String stateKey(dom.Element element) =>
      PostChecklistDocument.contentKey(element.outerHtml);

  PostChecklistTarget? targetFor(dom.Element checkbox) {
    final index = int.tryParse(
      checkbox.attributes[PostChecklistDocument.indexAttribute] ?? '',
    );
    final targets = _document.checklist?.targets;
    return index != null &&
            targets != null &&
            index >= 0 &&
            index < targets.length
        ? targets[index]
        : null;
  }
}

final _displayedChecklists =
    BoundedLruCache<(String, String), ({PostChecklistDocument? checklist})>(32);

PostChecklistDocument? _displayedChecklist(String html, String? savedHtml) {
  if (savedHtml == null || !html.contains('chcklst-box')) return null;
  final key = (html, savedHtml);
  if (_displayedChecklists.read(key) case (:final checklist)) return checklist;
  final checklist = _checklistFor(html, savedHtml);
  _displayedChecklists.put(key, (checklist: checklist));
  return checklist;
}

PostChecklistDocument? _checklistFor(String html, String savedHtml) {
  if (!savedHtml.contains('chcklst-box')) return null;
  final document = PostChecklistDocument(html);
  if (html == savedHtml) return document;
  final displayedTargets = document.targets;
  final savedTargets = PostChecklistDocument(savedHtml).targets;
  final sameTargets =
      displayedTargets.length == savedTargets.length &&
      displayedTargets.indexed.every((entry) {
        final (index, displayed) = entry;
        final saved = savedTargets[index];
        return displayed.checked == saved.checked &&
            displayed.permanent == saved.permanent &&
            displayed.source == saved.source;
      });
  return sameTargets ? document : null;
}
