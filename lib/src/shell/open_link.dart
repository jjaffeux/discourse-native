import 'package:flutter/widgets.dart';

import 'external_link.dart';
import 'shell_scope.dart';
import 'site_url.dart';
import 'user_card.dart';

/// Opens [url] wherever it belongs.
///
/// Anything the shell has a view for, it shows: a mention opens a card, a
/// hashtag opens the list it names, and a topic on a site in the rail opens
/// here — switching to that site first when it lives on another one.
/// Everything else is someone else's page and goes to the browser.
///
/// [title] is what the link's own markup called its destination, where the
/// caller knows — a cooked hashtag carries the category's real name, which
/// beats reading it back out of the slug.
///
/// Returns false only when nothing at all could handle the link, which is the
/// shape [HtmlWidget.onTapUrl] wants.
Future<bool> openLink(
  BuildContext context,
  String url, {
  String? title,
  String? siteUrl,
}) async {
  final controller = ShellScope.maybeRead(context);

  // Everything downstream compares hosts, so resolve the site-relative hrefs
  // Discourse writes before handing the link on.
  final target =
      controller?.absoluteUrl(url, siteUrl: siteUrl) ??
      resolveSiteUrl(url, siteUrl);

  if (showUserCardForUrl(context, target, siteUrl: siteUrl)) return true;
  if (controller?.openTopicUrl(target) ?? false) return true;
  if (controller?.openListUrl(target, title: title) ?? false) return true;
  return openExternalLink(target);
}
