import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import 'code_block.dart';
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

  static Widget? _customWidget(dom.Element element) =>
      oneboxWidgetBuilder(element) ??
      quoteWidgetBuilder(element) ??
      codeBlockWidgetBuilder(element);

  @override
  Widget build(BuildContext context) {
    return HtmlWidget(
      html,
      textStyle: textStyle ?? Theme.of(context).textTheme.bodyMedium,
      renderMode: RenderMode.column,
      customWidgetBuilder: _customWidget,
      onTapUrl: (url) => openLink(context, url),
    );
  }
}
