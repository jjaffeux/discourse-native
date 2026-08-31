import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../theme/app_theme.dart';
import 'code_block.dart';

class InlineCode extends StatelessWidget {
  const InlineCode({
    super.key,
    required this.text,
    required this.baseStyle,
    this.isLink = false,
  });

  final String text;

  final TextStyle? baseStyle;

  final bool isLink;

  static const double _scale = 0.875;

  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: 4,
    vertical: 1,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surrounding =
        baseStyle ??
        theme.textTheme.bodyMedium ??
        const TextStyle(fontSize: DiscourseTypography.base);

    return Container(
      padding: _padding,
      decoration: BoxDecoration(
        color: theme.code.inlineBackground,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: surrounding
            .merge(monospaceTextStyle)
            .copyWith(
              fontSize:
                  (surrounding.fontSize ?? DiscourseTypography.base) * _scale,
              color: isLink
                  ? theme.colorScheme.primary
                  : surrounding.color ?? theme.colorScheme.onSurface,
              height: 1.2,
            ),
      ),
    );
  }
}

Widget? inlineCodeWidgetBuilder(dom.Element element, TextStyle? baseStyle) {
  if (element.localName != 'code') return null;

  // Whitespace is content in code — `white-space: pre-wrap` in the stylesheet —
  // so it is taken from the element rather than left to the HTML whitespace
  // collapsing, but an element holding only whitespace is not worth a chip.
  final text = element.text;
  if (text.trim().isEmpty) return null;

  return InlineCustomWidget(
    child: InlineCode(
      text: text,
      baseStyle: baseStyle,
      isLink: _hasLinkAncestor(element),
    ),
  );
}

bool _hasLinkAncestor(dom.Element element) {
  for (var node = element.parent; node != null; node = node.parent) {
    if (node.localName == 'a' && node.attributes.containsKey('href')) {
      return true;
    }
  }
  return false;
}
