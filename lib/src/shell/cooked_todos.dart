import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../models/post_checklist.dart';

bool _isCheckbox(dom.Node node) =>
    node is dom.Element &&
    node.localName == 'span' &&
    node.classes.contains('chcklst-box');

/// Renders the Checklist plugin's cooked HTML through the Native UI kit.
Widget? cookedTodoWidgetBuilder(
  dom.Element element, {
  required Widget Function(String html, TextStyle? style) contentBuilder,
  required TextStyle? style,
  PostChecklistDocument? checklist,
  void Function(PostChecklistTarget, bool)? onToggle,
}) {
  Widget checkbox(dom.Element box, String label) {
    final index = int.tryParse(
      box.attributes[PostChecklistDocument.indexAttribute] ?? '',
    );
    final targets = checklist?.targets;
    final target =
        index != null && targets != null && index >= 0 && index < targets.length
        ? targets[index]
        : null;
    final interactive = target != null && !target.permanent && onToggle != null;
    return DCheckbox(
      value: box.classes.contains('checked'),
      readOnly: !interactive,
      semanticLabel: label.isEmpty ? 'To-do' : label,
      onChanged: (checked) {
        if (interactive) onToggle(target, checked == true);
      },
    );
  }

  if (_isCheckbox(element)) {
    return InlineCustomWidget(child: checkbox(element, 'To-do'));
  }
  if (element.localName != 'p' && element.localName != 'li') return null;
  final lines = <List<dom.Node>>[[]];
  for (final node in element.nodes) {
    if (node is dom.Element && node.localName == 'br') {
      lines.add([]);
    } else {
      lines.last.add(node);
    }
  }
  for (final line in lines) {
    while (line.isNotEmpty &&
        line.first is dom.Text &&
        line.first.text!.trim().isEmpty) {
      line.removeAt(0);
    }
  }
  if (!lines.any((line) => line.isNotEmpty && _isCheckbox(line.first))) {
    return null;
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final line in lines)
        Builder(
          builder: (context) {
            final isTodo = line.isNotEmpty && _isCheckbox(line.first);
            final checked =
                isTodo &&
                (line.first as dom.Element).classes.contains('checked');
            final fragment = dom.DocumentFragment();
            for (final node in line.skip(isTodo ? 1 : 0)) {
              fragment.append(node.clone(true));
            }
            if (!isTodo) {
              return contentBuilder(
                fragment.outerHtml.isEmpty ? '<br>' : fragment.outerHtml,
                style,
              );
            }
            final label = fragment.text?.trim() ?? '';
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                checkbox(line.first as dom.Element, label),
                Expanded(
                  child: contentBuilder(
                    fragment.outerHtml.trim(),
                    checked
                        ? (style ?? DefaultTextStyle.of(context).style)
                              .copyWith(
                                color: DTokens.of(context).mutedForeground,
                                decoration: TextDecoration.lineThrough,
                              )
                        : style,
                  ),
                ),
              ],
            );
          },
        ),
    ],
  );
}
