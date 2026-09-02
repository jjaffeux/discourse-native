import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../models/user_status.dart';
import 'open_link.dart';
import 'pill.dart';
import 'user_status.dart';

class MentionPill extends StatelessWidget {
  const MentionPill({
    super.key,
    required this.label,
    required this.baseStyle,
    this.href,
    this.siteUrl,
    this.status,
  });

  final String label;

  final TextStyle? baseStyle;
  final String? href;
  final String? siteUrl;
  final UserStatusReference? status;

  @override
  Widget build(BuildContext context) {
    final target = href;
    final pill = LinkTarget(
      url: target,
      siteUrl: siteUrl,
      child: Pill(
        label: label,
        baseStyle: baseStyle,
        onTap: target == null
            ? null
            : () => openLink(context, target, siteUrl: siteUrl),
      ),
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
  final isGroupMention = element.classes.contains('mention-group');

  return InlineCustomWidget(
    // Baseline rather than middle: the pill has a real `Text` inside it, so it
    // reports a baseline and sits on the line like the word it stands for.
    child: MentionPill(
      label: label,
      baseStyle: baseStyle,
      href: _mentionTarget(
        element.attributes['href'],
        isGroupMention: isGroupMention,
      ),
      siteUrl: siteUrl,
      status: userStatuses[username],
    ),
  );
}

String? _mentionTarget(String? href, {required bool isGroupMention}) {
  if (!isGroupMention || href == null) return href;
  final uri = Uri.tryParse(href);
  if (uri == null) return href;
  final segments = uri.pathSegments;
  if (segments.length != 2 ||
      segments.first != 'groups' ||
      segments.last.isEmpty) {
    return href;
  }
  return uri.replace(pathSegments: ['', 'g', segments.last]).toString();
}
