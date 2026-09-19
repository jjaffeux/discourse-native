import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

/// A group marker has no member list. Cooked markup cannot manufacture the
/// server's account-scoped group timezone snapshot or trigger its acquisition.
Widget? groupTimezonesFallback(dom.Element element) {
  if (element.localName != 'div' ||
      !element.classes.contains('group-timezones')) {
    return null;
  }
  final group = element.attributes['data-group']?.trim();
  return Semantics(
    container: true,
    label: 'Group timezones, read only',
    child: DCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DText(
            group == null || group.isEmpty
                ? 'Group timezones'
                : 'Timezones for $group',
            variant: DTextVariant.large,
          ),
          const Text('Group member timezones are not available here.'),
        ],
      ),
    ),
  );
}
