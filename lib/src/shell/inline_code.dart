import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../theme/app_theme.dart';
import 'code_block.dart';

/// Renders inline `<code>` as the chip Discourse's stylesheet draws.
///
/// `code_highlighting.scss` gives inline code a background, a little padding,
/// rounded corners and a smaller monospace face — everything except the font
/// comes from CSS, so [HtmlWidget] drops it and the code arrives as bare
/// monospace text that barely reads as code at all.
///
/// [HtmlWidget] only understands inline styling it can put on a [TextStyle],
/// and a `TextStyle.background` paints a tight rectangle with no padding and
/// square corners. The chip therefore has to be a widget.
///
/// `<code>` inside a `<pre>` never reaches here: [codeBlockWidgetBuilder]
/// claims the whole `<pre>` subtree first.
class InlineCode extends StatelessWidget {
  const InlineCode({
    super.key,
    required this.text,
    required this.baseStyle,
    this.isLink = false,
  });

  final String text;

  /// The style of the surrounding prose, which the chip sizes itself against
  /// the way `font-size: 0.875rem` sizes against the body.
  final TextStyle? baseStyle;

  /// Whether the code is the text of a link, which Discourse colors as one
  /// (`a > code`). The tap itself is [HtmlWidget]'s: it wraps inline custom
  /// widgets in the enclosing anchor's gesture detector.
  final bool isLink;

  /// Discourse's `p > code` sits at 0.875rem against a 1rem body.
  static const double _scale = 0.875;

  /// `padding: 2px 4px`, minus a little vertically: CSS padding on an inline
  /// box overflows the line rather than growing it, which Flutter cannot do, so
  /// keeping it tight stops a paragraph from opening up wherever code appears.
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

/// Hands inline `<code>` to [InlineCode], for [HtmlWidget.customWidgetBuilder].
///
/// [baseStyle] is the prose the code is sitting in, which the builder has to be
/// told because [HtmlWidget] does not pass its resolved style to custom
/// builders.
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
