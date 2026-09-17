import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

/// Keeps the post's rendering context inside each disclosure, including nested
/// details, plugin content, relative links and authenticated images.
Widget? cookedDetailsWidgetBuilder(
  dom.Element element, {
  required Widget Function(BuildContext, String) contentBuilder,
}) {
  if (element.localName != 'details') return null;
  final summary = element.children
      .where((child) => child.localName == 'summary')
      .firstOrNull;
  final title = summary?.text.trim() ?? '';
  final body = dom.Element.tag('div');
  for (final node in element.nodes) {
    if (!identical(node, summary)) body.append(node.clone(true));
  }
  return DAccordion<int>(
    key: ValueKey(element.outerHtml),
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
                child: Text(title.isEmpty ? 'Details' : title),
              ),
            ),
            DAccordionContent(
              child: Builder(
                builder: (context) => contentBuilder(context, body.innerHtml),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
