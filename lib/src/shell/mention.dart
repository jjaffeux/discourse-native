import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../models/user_status.dart';
import 'open_link.dart';
import 'pill.dart';
import 'user_status.dart';

/// One `@someone`, drawn as a pill.
///
/// [href] is null in the composer, where the pill stands over text being
/// edited. When it is set the pill carries its own tap: claiming an element in
/// [HtmlWidget.customWidgetBuilder] means the anchor's own handling — including
/// `onTapUrl` — never runs for it.
class MentionPill extends StatelessWidget {
  const MentionPill({
    super.key,
    required this.label,
    required this.baseStyle,
    this.href,
    this.siteUrl,
    this.status,
  });

  /// `@sam`, sigil and all, exactly as the post has it. Discourse lowercases
  /// the href but leaves the text as it was typed, and the text is what a
  /// reader recognises.
  final String label;

  final TextStyle? baseStyle;
  final String? href;
  final String? siteUrl;
  final UserStatusReference? status;

  @override
  Widget build(BuildContext context) {
    final target = href;
    final pill = Pill(
      label: label,
      baseStyle: baseStyle,
      onTap: target == null
          ? null
          : () => openLink(context, target, siteUrl: siteUrl),
    );
    final reference = status;
    if (reference == null || siteUrl == null) return pill;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        pill,
        UserStatusMessage(
          siteUrl: siteUrl!,
          userId: reference.userId,
          status: reference.status,
          size: (baseStyle?.fontSize ?? 14) * .95,
          style: baseStyle,
          leadingGap: 4,
        ),
      ],
    );
  }
}

/// Hands `<a class="mention">` and `<a class="mention-group">` to [MentionPill],
/// for [HtmlWidget.customWidgetBuilder].
///
/// An unresolved mention arrives as `<span class="mention">` — somebody who is
/// not a user, or one the reader may not see — and is deliberately not claimed.
/// Discourse does not pill it either; it is prose that looks like a mention,
/// and drawing it as one would promise a person who is not there.
Widget? mentionWidgetBuilder(
  dom.Element element,
  TextStyle? baseStyle, {
  String? siteUrl,
  Map<String, UserStatusReference> userStatuses = const {},
}) {
  if (element.localName != 'a') return null;
  if (!element.classes.contains('mention') &&
      !element.classes.contains('mention-group')) {
    return null;
  }

  final label = element.text.trim();
  if (label.isEmpty) return null;

  final username = label.startsWith('@')
      ? label.substring(1).toLowerCase()
      : label.toLowerCase();

  return InlineCustomWidget(
    // Baseline rather than middle: the pill has a real `Text` inside it, so it
    // reports a baseline and sits on the line like the word it stands for.
    child: MentionPill(
      label: label,
      baseStyle: baseStyle,
      href: element.attributes['href'],
      siteUrl: siteUrl,
      status: userStatuses[username],
    ),
  );
}
