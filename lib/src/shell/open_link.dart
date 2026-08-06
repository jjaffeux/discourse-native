import 'package:flutter/widgets.dart';

import 'external_link.dart';
import 'shell_scope.dart';
import 'user_card.dart';

/// Opens [url] wherever it belongs.
///
/// Anything the shell has a view for, it shows: a mention opens a card, and a
/// topic on a site in the rail opens here — switching to that site first when
/// the topic lives on another one. Everything else is someone else's page and
/// goes to the browser.
///
/// Returns false only when nothing at all could handle the link, which is the
/// shape [HtmlWidget.onTapUrl] wants.
Future<bool> openLink(BuildContext context, String url) async {
  final controller = ShellScope.maybeOf(context);

  // Everything downstream compares hosts, so resolve the site-relative hrefs
  // Discourse writes before handing the link on.
  final target = controller?.absoluteUrl(url) ?? url;

  if (showUserCardForUrl(context, target)) return true;
  if (controller?.openTopicUrl(target) ?? false) return true;
  return openExternalLink(target);
}
