import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../../../theme/app_theme.dart';
import '../../../avatar_image.dart';
import '../../../cooked_dom.dart';
import '../../../open_link.dart';
import '../../../site_url.dart';
import '../../onebox.dart';

/// A profile on the site the post was written on: `aside.onebox` holding an
/// `article.user-onebox`. The user card does not claim it — a onebox is a
/// card already, just drawn by the server's stylesheet until now.
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
                      Semantics(
                        container: true,
                        link: true,
                        label: data.websiteName!,
                        child: InkWell(
                          onTap: () => openLink(
                            context,
                            data.websiteUrl!,
                            siteUrl: siteUrl,
                          ),
                          borderRadius: BorderRadius.circular(2),
                          hoverColor: theme.shell.hover,
                          focusColor: theme.shell.hover,
                          child: ExcludeSemantics(
                            child: Text(
                              data.websiteName!,
                              style: _mutedStyle(
                                theme,
                              )?.copyWith(color: theme.colorScheme.primary),
                            ),
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

  /// The avatar is written site-relative, like quote avatars.
  String? _absoluteAvatar(String? src) {
    if (src == null) return null;
    final url = resolveSiteUrl(src, siteUrl);
    return url.startsWith('http') ? url : null;
  }
}

/// Everything the user onebox carries, read out of the aside.
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
    final profileLink = descendantWhere(
      article,
      (e) => e.localName == 'h3',
    )?.children.where((e) => e.localName == 'a').firstOrNull;

    // The template marks the website link with a globe icon; the location
    // cell has no anchor of its own, so its svg is the way in.
    final websiteLink = descendantWhere(
      article,
      (e) => e.classes.contains('d-icon-earth-americas'),
    )?.parent?.children.where((e) => e.localName == 'a').firstOrNull;

    final locationEl = descendantWhere(
      article,
      (e) => e.classes.contains('location'),
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
      bio: article.children
          .where((e) => e.localName == 'p')
          .map((e) => e.text.replaceAll(RegExp(r'\s+'), ' ').trim())
          .where((text) => text.isNotEmpty)
          .firstOrNull,
      joined: descendantWhere(
        article,
        (e) => e.classes.contains('user-onebox--joined'),
      )?.text.trim().nullIfEmpty,
    );
  }
}

/// Claims the user onebox — an `aside.onebox` with no engine class of its
/// own, recognised by its body — for the dispatch in `onebox.dart`.
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

bool _hasUserBody(dom.Element aside) {
  final pending = <dom.Element>[];
  void pushReversed(List<dom.Element> children) {
    for (var index = children.length - 1; index >= 0; index--) {
      pending.add(children[index]);
    }
  }

  pushReversed(aside.children);
  while (pending.isNotEmpty) {
    final child = pending.removeLast();
    if (child.classes.contains('user-onebox')) return true;
    pushReversed(child.children);
  }
  return false;
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
