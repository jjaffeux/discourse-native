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
  final visibleSummary = _visibleSummary(summary);
  final title = _summaryLabel(visibleSummary);
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
                child: visibleSummary?.querySelector('img.emoji') == null
                    ? Text(title.isEmpty ? appL10n.details : title)
                    : IgnorePointer(
                        child: Builder(
                          builder: (context) =>
                              content(context, _summaryHtml(visibleSummary!)),
                        ),
                      ),
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

// Only visible text and server-cooked emoji belong in the trigger. Concealed
// descendants must not leak through its appearance or accessibility label.
dom.Element? _visibleSummary(dom.Element? summary) {
  if (summary == null) return null;
  final visible = summary.clone(true);
  for (final hidden in visible.querySelectorAll('div.hidden, span.hidden')) {
    hidden.remove();
  }
  for (final spoiler
      in visible.querySelectorAll('div.spoiler, span.spoiler').reversed) {
    spoiler.replaceWith(dom.Text(appL10n.spoiler));
  }
  return visible;
}

String _summaryLabel(dom.Element? summary) =>
    summary?.text.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';

String _summaryHtml(dom.Element summary) {
  final inline = dom.Element.tag('span');
  void append(dom.Node node) {
    if (node is dom.Text) {
      inline.append(node.clone(true));
    } else if (node is dom.Element) {
      if (node.localName == 'img' && node.classes.contains('emoji')) {
        inline.append(node.clone(true)..attributes['class'] = 'emoji');
      } else {
        for (final child in node.nodes) {
          append(child);
        }
      }
    }
  }

  append(summary);
  return inline.outerHtml;
}
