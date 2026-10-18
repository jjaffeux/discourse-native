import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import 'cooked_document.dart';
import 'cooked_dom.dart';

/// Keeps the post's rendering context inside each disclosure, including nested
/// details, plugin content, relative links and authenticated images.
Widget? cookedDetailsWidgetBuilder(
  dom.Element element, {
  required CookedContent content,
}) {
  if (element.localName != 'details') return null;
  final summary = childWhere(element, (child) => child.localName == 'summary');
  final title = _summaryLabel(summary);
  final body = dom.Element.tag('div');
  for (final node in element.nodes) {
    if (!identical(node, summary)) body.append(node.clone(true));
  }
  return DAccordion<int>(
    key: ValueKey(content.stateKey(element)),
    defaultValues: element.attributes.containsKey('open')
        ? const [0]
        : const [],
    children: [
      DAccordionItem<int>(
        value: 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DAccordionHeader(
              child: DAccordionTrigger(
                child: Text(title.isEmpty ? appL10n.details : title),
              ),
            ),
            DAccordionContent(
              child: Builder(
                builder: (context) => content(context, body.innerHtml),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

// The trigger uses plain text. Flattening concealed descendants would expose
// content before its disclosure, including through the accessibility label.
String _summaryLabel(dom.Element? summary) {
  if (summary == null) return '';
  final visible = summary.clone(true);
  for (final hidden in visible.querySelectorAll('div.hidden, span.hidden')) {
    hidden.remove();
  }
  for (final spoiler
      in visible.querySelectorAll('div.spoiler, span.spoiler').reversed) {
    spoiler.replaceWith(dom.Text(appL10n.spoiler));
  }
  return visible.text.trim().replaceAll(RegExp(r'\s+'), ' ');
}
