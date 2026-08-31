import 'package:flutter/widgets.dart';

import 'external_link.dart';
import 'shell_scope.dart';
import 'site_url.dart';
import 'user_card.dart';

Future<bool> openLink(
  BuildContext context,
  String url, {
  String? title,
  String? siteUrl,
}) async {
  final controller = ShellScope.maybeRead(context);

  final target =
      controller?.absoluteUrl(url, siteUrl: siteUrl) ??
      resolveSiteUrl(url, siteUrl);

  if (showUserCardForUrl(context, target, siteUrl: siteUrl)) return true;
  if (await controller?.openPluginUrl(target) ?? false) return true;
  if (controller?.openGroupUrl(target) ?? false) return true;
  if (controller?.openTopicUrl(target) ?? false) return true;
  if (controller?.openListUrl(target, title: title) ?? false) return true;
  return openExternalLink(target);
}
