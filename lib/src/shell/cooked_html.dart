import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import 'code_block.dart';
import 'inline_code.dart';
import 'onebox.dart';
import 'open_link.dart';
import 'quote.dart';

/// Draws Discourse's `cooked` HTML.
///
/// Discourse already resolved the markdown, oneboxes, mentions and emoji, so
/// [HtmlWidget] does most of the work. The exceptions are the pieces Discourse
/// styles from its stylesheet rather than inline — [HtmlWidget] has no
/// stylesheet engine, so those arrive unstyled and are drawn natively instead.
///
/// Onebox bodies come back through here, which is why an onebox containing a
/// code block gets the same code block a post does.
class CookedHtml extends StatelessWidget {
  const CookedHtml({super.key, required this.html, this.textStyle});

  final String html;
  final TextStyle? textStyle;

  /// Inline code sizes itself against the prose around it, so unlike the other
  /// builders this one needs the style the widget was given.
  static Widget? Function(dom.Element) _customWidget(TextStyle? textStyle) =>
      (element) =>
          oneboxWidgetBuilder(element) ??
          quoteWidgetBuilder(element) ??
          codeBlockWidgetBuilder(element) ??
          inlineCodeWidgetBuilder(element, textStyle);

  /// Discourse leaves links undecorated and lets colour carry them, but
  /// [HtmlWidget] underlines every `a[href]` by default. Inline styles are the
  /// only styling it reads, so the override has to arrive as one.
  static Map<String, String>? _customStyles(dom.Element element) =>
      element.localName == 'a' ? const {'text-decoration': 'none'} : null;

  @override
  Widget build(BuildContext context) {
    final style = textStyle ?? Theme.of(context).textTheme.bodyMedium;

    return HtmlWidget(
      html,
      textStyle: style,
      renderMode: RenderMode.column,
      customWidgetBuilder: _customWidget(style),
      customStylesBuilder: _customStyles,
      // The builders close over [style], and [HtmlWidget] caches what they
      // built — so a change of style has to say so to reach the inline code.
      rebuildTriggers: [style],
      onTapUrl: (url) => openLink(context, url),
    );
  }
}
