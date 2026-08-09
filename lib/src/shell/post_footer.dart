import 'package:flutter/widgets.dart';

import '../models/post.dart';
import '../plugins/site_plugin.dart';
import 'post_likes.dart';

/// What sits under a post: the record of what people did with it.
///
/// On plain core that is the likes, and on a site with an optional feature that
/// claims this spot it is whatever that feature draws instead. The choice is
/// made per post rather than per site, from the payload the post arrived in —
/// see [SitePlugin] for why that is the gate rather than a setting.
///
/// An ordered fallthrough with the core answer at the end, the same shape as
/// `cooked_html.dart`'s builder chain and `open_link.dart`'s dispatch.
class PostFooter extends StatelessWidget {
  const PostFooter({super.key, required this.siteUrl, required this.post});

  final String siteUrl;
  final Post post;

  @override
  Widget build(BuildContext context) {
    return pluginRegistry.postFooter(siteUrl, post) ??
        PostLikes(siteUrl: siteUrl, post: post);
  }
}
