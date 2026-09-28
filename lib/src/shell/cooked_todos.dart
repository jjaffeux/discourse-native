import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../models/post_checklist.dart';

bool _isCheckbox(dom.Node node) =>
    node is dom.Element &&
    node.localName == 'span' &&
    node.classes.contains('chcklst-box');

dom.Node? _firstContent(Iterable<dom.Node> nodes) => nodes
    .where((node) => node is! dom.Text || node.text.trim().isNotEmpty)
    .firstOrNull;

/// Only the item's own leading marker makes it a task. A nested task must not
/// remove the bullet from an ordinary parent item.
dom.Element? cookedTodoListMarker(dom.Element element) {
  if (element.localName != 'li') return null;
  var first = _firstContent(element.nodes);
  if (first is dom.Element && first.localName == 'p') {
    first = _firstContent(first.nodes);
  }
  return first != null && _isCheckbox(first) ? first as dom.Element : null;
}

Map<String, String>? cookedTodoStyles(dom.Element element) {
  if (cookedTodoListMarker(element) != null) {
    return const {'list-style-type': 'none'};
  }
  if (element.localName == 'ul') {
    final items = element.children.where((child) => child.localName == 'li');
    if (items.isNotEmpty &&
        items.every((item) => cookedTodoListMarker(item) != null)) {
      // The Native checkbox supplies the marker gutter for a task list.
      return const {'padding-inline-start': '0'};
    }
  }
  return null;
}

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
    return Builder(
      builder: (context) => DCheckbox(
        inline: true,
        size: DControlStyle.isTouch(context)
            ? DCheckboxSize.large
            : DCheckboxSize.standard,
        value: box.classes.contains('checked'),
        readOnly: !interactive,
        semanticLabel: label.isEmpty ? 'To-do' : label,
        onChanged: (checked) {
          if (interactive) onToggle(target, checked == true);
        },
      ),
    );
  }

  if (_isCheckbox(element)) {
    return InlineCustomWidget(child: checkbox(element, 'To-do'));
  }
  if (cookedTodoListMarker(element) case final marker?) {
    final copy = element.clone(true);
    final copiedMarker = cookedTodoListMarker(copy)!;
    final first = _firstContent(copy.nodes);
    final label = first is dom.Element && first.localName == 'p'
        ? first.text.trim()
        : copy.nodes
              .takeWhile(
                (node) =>
                    node is! dom.Element ||
                    !const {
                      'ul',
                      'ol',
                      'pre',
                      'blockquote',
                      'p',
                      'details',
                      'table',
                    }.contains(node.localName),
              )
              .map((node) => node.text ?? '')
              .join()
              .trim();
    copiedMarker.remove();
    final fragment = dom.DocumentFragment();
    for (final node in copy.nodes.toList()) {
      fragment.append(node);
    }
    return Builder(
      builder: (context) {
        if (marker.classes.contains('checked')) {
          _markCompletedText(fragment, DTokens.of(context).mutedForeground);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            checkbox(marker, label),
            Expanded(child: contentBuilder(fragment.outerHtml.trim(), style)),
          ],
        );
      },
    );
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
              crossAxisAlignment: CrossAxisAlignment.start,
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

/// Completion belongs to this task's prose, not to code blocks or child tasks.
void _markCompletedText(dom.DocumentFragment fragment, Color color) {
  final cssColor = '#${color.toARGB32().toRadixString(16).substring(2)}';
  final decoration = 'color:$cssColor;text-decoration:line-through';
  dom.Element? run;
  var firstLine = true;
  for (final node in fragment.nodes.toList()) {
    if (node is dom.Element && node.localName == 'br') {
      firstLine = false;
      run = null;
      continue;
    }
    if (node is dom.Element &&
        const {
          'p',
          'ul',
          'ol',
          'pre',
          'blockquote',
          'details',
          'table',
          'div',
        }.contains(node.localName)) {
      run = null;
      if (firstLine && node.localName == 'p') {
        final leading = node.nodes
            .takeWhile(
              (child) => child is! dom.Element || child.localName != 'br',
            )
            .toList();
        if (leading.isNotEmpty) {
          final span = dom.Element.tag('span')
            ..attributes['style'] = decoration;
          leading.first.replaceWith(span);
          for (final child in leading) {
            span.append(child);
          }
        }
      }
      firstLine = false;
    } else if (firstLine) {
      if (run == null) {
        run = dom.Element.tag('span')..attributes['style'] = decoration;
        node.replaceWith(run);
      }
      run.append(node);
    }
  }
}
