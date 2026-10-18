import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import 'cooked_document.dart';

/// Conceals both block and inline spoilers before their descendants are built.
/// The host supplies nested rendering so revealed content retains its context.
Widget? cookedSpoilerWidgetBuilder(
  dom.Element element, {
  TextStyle? textStyle,
  required CookedContent content,
}) {
  if (!const {'div', 'span'}.contains(element.localName) ||
      !element.classes.contains('spoiler')) {
    return null;
  }
  Widget spoiler = DSpoiler(
    key: ValueKey(('spoiler', content.stateKey(element))),
    text: element.text,
    hasMedia: element.querySelector('img, video, iframe') != null,
    showLabel: appL10n.spoilerCookedspoiler,
    hideLabel: appL10n.hideSpoiler,
    builder: (context) => content(context, element.innerHtml),
  );
  if (textStyle != null) {
    spoiler = DefaultTextStyle.merge(style: textStyle, child: spoiler);
  }
  return element.localName == 'span'
      ? InlineCustomWidget(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: spoiler,
        )
      : spoiler;
}
