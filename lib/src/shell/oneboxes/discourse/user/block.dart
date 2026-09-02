import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../../../theme/app_theme.dart';
import '../../../avatar_image.dart';
import '../../../cooked_dom.dart';
import '../../../inline_action.dart';
import '../../../open_link.dart';
import '../../../site_url.dart';
import '../../markup.dart';
import '../../onebox.dart';

class DiscourseUserOnebox extends StatelessWidget {
  const DiscourseUserOnebox({super.key, required this.data, this.siteUrl});

  final DiscourseUserData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipOval(
          child: SizedBox.square(
            dimension: 56,
            child: AvatarImage(
              url: _absoluteAvatar(data.avatarUrl),
              size: 56,
              fallback: ColoredBox(color: theme.shell.floating),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.username,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              if (data.name != null ||
                  data.location != null ||
                  data.websiteName != null) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  children: [
                    if (data.name != null)
                      Text(data.name!, style: _mutedStyle(theme)),
                    if (data.location != null)
                      Text(data.location!, style: _mutedStyle(theme)),
                    if (data.websiteName != null && data.websiteUrl != null)
                      LinkTarget(
                        url: data.websiteUrl,
                        siteUrl: siteUrl,
                        child: InlineAction.link(
                          onTap: () => openLink(
                            context,
                            data.websiteUrl!,
                            siteUrl: siteUrl,
                          ),
                          semanticLabel: data.websiteName!,
                          excludeChildSemantics: true,
                          child: Text(
                            data.websiteName!,
                            style: _mutedStyle(
                              theme,
                            )?.copyWith(color: theme.colorScheme.primary),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (data.bio != null) ...[
                const SizedBox(height: 6),
                Text(
                  data.bio!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ],
              if (data.joined != null) ...[
                const SizedBox(height: 6),
                Text(data.joined!, style: _mutedStyle(theme)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  TextStyle? _mutedStyle(ThemeData theme) => theme.textTheme.labelMedium
      ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

  String? _absoluteAvatar(String? src) {
    if (src == null) return null;
    final url = resolveSiteUrl(src, siteUrl);
    return url.startsWith('http') ? url : null;
  }
}

class DiscourseUserData {
  const DiscourseUserData({
    required this.username,
    required this.avatarUrl,
    required this.name,
    required this.location,
    required this.websiteName,
    required this.websiteUrl,
    required this.bio,
    required this.joined,
  });

  final String username;
  final String? avatarUrl;
  final String? name;
  final String? location;
  final String? websiteName;
  final String? websiteUrl;
  final String? bio;
  final String? joined;

  static DiscourseUserData from(dom.Element aside) {
    final article =
        descendantWhere(aside, (e) => e.classes.contains('user-onebox')) ??
        aside;

    final avatar = descendantWhere(article, (e) => e.localName == 'img');
    final profileHeading = descendantWhere(article, (e) => e.localName == 'h3');
    final profileLink = profileHeading == null
        ? null
        : childWhere(profileHeading, (e) => e.localName == 'a');

    // The template marks the website link with a globe icon; the location
    // cell has no anchor of its own, so its svg is the way in.
    final websiteIcon = descendantWhere(
      article,
      (e) => e.classes.contains('d-icon-earth-americas'),
    );
    final websiteRow = websiteIcon?.parent;
    final websiteLink = websiteRow == null
        ? null
        : childWhere(websiteRow, (e) => e.localName == 'a');

    final locationEl = descendantWhere(
      article,
      (e) => e.classes.contains('location'),
    );

    final bioElement = childWhere(
      article,
      (e) => e.localName == 'p' && oneLineText(e) != null,
    );

    return DiscourseUserData(
      username: (profileLink?.text ?? '').trim().replaceFirst('@', ''),
      avatarUrl: avatar?.attributes['src'],
      name: descendantWhere(
        article,
        (e) => e.classes.contains('full-name'),
      )?.text.trim().nullIfEmpty,
      location: locationEl?.text.trim().nullIfEmpty,
      websiteName: websiteLink?.text.trim().nullIfEmpty,
      websiteUrl: websiteLink?.attributes['href'],
      bio: bioElement == null ? null : oneLineText(bioElement),
      joined: descendantWhere(
        article,
        (e) => e.classes.contains('user-onebox--joined'),
      )?.text.trim().nullIfEmpty,
    );
  }
}

final OneboxEngine discourseUserBlock = OneboxEngine(
  matches: _hasUserBody,
  build: (aside, envelope, siteUrl) => OneboxCard(
    data: envelope,
    siteUrl: siteUrl,
    child: DiscourseUserOnebox(
      data: DiscourseUserData.from(aside),
      siteUrl: siteUrl,
    ),
  ),
);

bool _hasUserBody(dom.Element aside) =>
    descendantWhere(aside, (e) => e.classes.contains('user-onebox')) != null;
