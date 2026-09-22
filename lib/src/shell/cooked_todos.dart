import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

bool _isCheckbox(dom.Node node) =>
    node is dom.Element &&
    node.localName == 'span' &&
    node.classes.contains('chcklst-box');

/// Renders the Checklist plugin's cooked HTML through the Native UI kit.
Widget? cookedTodoWidgetBuilder(
  dom.Element element, {
  required Widget Function(String html, TextStyle? style) contentBuilder,
  required TextStyle? style,
}) {
  if (_isCheckbox(element)) {
    return InlineCustomWidget(
      child: DCheckbox(
        value: element.classes.contains('checked'),
        readOnly: true,
        onChanged: (_) {},
        semanticLabel: 'To-do',
      ),
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DCheckbox(
                  value: checked,
                  readOnly: true,
                  onChanged: (_) {},
                  semanticLabel: label.isEmpty ? 'To-do' : label,
                ),
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
