import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import '../models/post_checklist.dart';

/// Conceals both block and inline spoilers before their descendants are built.
/// The host supplies nested rendering so revealed content retains its context.
Widget? cookedSpoilerWidgetBuilder(
  dom.Element element, {
  required Widget Function(BuildContext, String) contentBuilder,
}) {
  if (!const {'div', 'span'}.contains(element.localName) ||
      !element.classes.contains('spoiler')) {
    return null;
  }
  return DAccordion<int>(
    // A replacement body must never inherit another spoiler's revealed state.
    key: ValueKey((
      'spoiler',
      PostChecklistDocument.contentKey(element.outerHtml),
    )),
    children: [
      DAccordionItem<int>(
        value: 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DAccordionHeader(
              child: DAccordionTrigger(
                child: Text(appL10n.spoilerCookedspoiler),
              ),
            ),
            DAccordionContent(
              // Closing immediately removes selectable content as well as its
              // media and focus nodes. The Native component owns disclosure.
              duration: Duration.zero,
              child: Builder(
                builder: (context) =>
                    contentBuilder(context, element.innerHtml),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
