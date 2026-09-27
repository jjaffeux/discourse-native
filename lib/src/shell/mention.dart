import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../models/user_status.dart';
import '../theme/app_theme.dart';
import 'open_link.dart';
import 'pill.dart';
import 'shell_scope.dart';
import 'site_url.dart';
import 'user_card.dart';
import 'user_status.dart';

class MentionPill extends StatelessWidget {
  const MentionPill({
    super.key,
    required this.label,
    required this.baseStyle,
    this.name,
    this.href,
    this.siteUrl,
    this.status,
    this.isGroupMention = false,
  });

  final String label;

  final TextStyle? baseStyle;

  /// The user or group [label] names, lowercased as Discourse links it. It is
  /// what a tap opens, as on the web, where a mention shows the card for its
  /// text; null leaves the pill inert.
  final String? name;

  /// The link the cooked mention carries. An author can give a mention any
  /// link, so it never decides where the pill goes; it only tells whether this
  /// is the mention Discourse wrote for [name].
  final String? href;
  final String? siteUrl;
  final UserStatusReference? status;
  final bool isGroupMention;

  @override
  Widget build(BuildContext context) {
    final link = href;
    if (link == null ||
        isGroupMention ||
        ShellScope.maybeIdentityOf(context) == null) {
      return _buildPill(context, false);
    }

    return ShellSelector<bool>(
      select: (controller) {
        final sourceSite = siteUrl ?? controller.currentInstance?.url;
        if (sourceSite == null) return false;
        final username = controller.currentUserFor(sourceSite)?.username;
        // As core does, the cooked profile href alone decides, including a
        // site's subfolder, case-insensitively, whatever the label says.
        return username != null &&
            _linksProfileOf(link, username.toLowerCase(), sourceSite);
      },
      builder: (context, isCurrentUser, child) =>
          _buildPill(context, isCurrentUser),
    );
  }

  Widget _buildPill(BuildContext context, bool isCurrentUser) {
    final mentioned = name;
    final target = mentioned == null
        ? null
        : _siteLink(
            context,
            '/${isGroupMention ? 'g' : 'u'}/${Uri.encodeComponent(mentioned)}',
          );
    final pill = LinkTarget(
      url: target,
      siteUrl: siteUrl,
      child: Pill(
        label: label,
        baseStyle: baseStyle,
        backgroundColor: isCurrentUser
            ? Theme.of(context).shell.currentUserMention
            : null,
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
        Flexible(child: pill),
        UserStatusMessage(
          siteUrl: siteUrl!,
          userId: reference.userId,
          status: reference.status,
          size: (baseStyle?.fontSize ?? DiscourseTypography.sm) * .95,
          style: baseStyle,
          leadingGap: 4,
        ),
      ],
    );
  }

  String _siteLink(BuildContext context, String path) {
    final site = siteUrl ?? ShellScope.maybeRead(context)?.currentInstance?.url;
    return site == null ? path : resolveSiteRootPath(site, path);
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

  final name = _mentionedName(label);
  final href = element.attributes['href'];
  final isGroupMention = element.classes.contains('mention-group');

  return InlineCustomWidget(
    // Baseline rather than middle: the pill has a real `Text` inside it, so it
    // reports a baseline and sits on the line like the word it stands for.
    child: MentionPill(
      label: label,
      baseStyle: baseStyle,
      name: name,
      href: href,
      siteUrl: siteUrl,
      isGroupMention: isGroupMention,
      status: name == null || isGroupMention
          ? null
          : _statusFor(name, href, siteUrl, userStatuses),
    ),
  );
}

// Core's mention pattern with unicode usernames allowed: the names a site can
// cook into a mention, of a user or of a group.
const _nameCharacter = r'\p{Alphabetic}\p{Mark}\p{Decimal_Number}';
final RegExp _mentionName = RegExp(
  '^(?:[${_nameCharacter}_][$_nameCharacter._-]{0,58}[$_nameCharacter]'
  '|[${_nameCharacter}_])\$',
  unicode: true,
);

String? _mentionedName(String label) {
  final name = label.startsWith('@') ? label.substring(1) : label;
  return _mentionName.hasMatch(name) ? name.toLowerCase() : null;
}

/// Statuses arrive keyed by username, so one belongs only beside the mention
/// Discourse wrote for that user, as on the web, and not beside a pill an
/// author gave the same text and another link.
UserStatusReference? _statusFor(
  String name,
  String? href,
  String? siteUrl,
  Map<String, UserStatusReference> statuses,
) {
  final status = statuses[name];
  if (status == null || siteUrl == null) return null;
  return _linksProfileOf(href, name, siteUrl) ? status : null;
}

/// Whether [href] is the link Discourse writes into a mention of [username]:
/// the root-relative profile path on [siteUrl], subfolder included.
bool _linksProfileOf(String? href, String username, String siteUrl) {
  final link = href == null ? null : Uri.tryParse(href);
  if (link == null ||
      link.hasScheme ||
      link.hasAuthority ||
      !link.path.startsWith('/')) {
    return false;
  }
  return usernameFromProfileUrl(link, siteUrl: siteUrl)?.toLowerCase() ==
      username;
}
