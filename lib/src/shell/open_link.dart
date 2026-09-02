import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../plugin_api/shell_extensions.dart';
import 'external_link.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'site_url.dart';
import 'user_card.dart';

Future<bool> openLink(
  BuildContext context,
  String url, {
  String? title,
  String? siteUrl,
  bool newTab = false,
}) async {
  final controller = ShellScope.maybeRead(context);

  final target =
      controller?.absoluteUrl(url, siteUrl: siteUrl) ??
      resolveSiteUrl(url, siteUrl);

  if (newTab && controller != null) {
    final result = controller.openLinkInNewTab(target, title: title);
    if (result != TabOpenResult.unsupported) {
      return _handleTabResult(context, result);
    }
  }

  if (showUserCardForUrl(context, target, siteUrl: siteUrl)) return true;
  if (await controller?.openPluginUrl(target, origin: PluginLinkOrigin.inApp) ??
      false) {
    return true;
  }
  if (controller?.openGroupUrl(target) ?? false) return true;
  if (controller?.openTopicUrl(target) ?? false) return true;
  if (controller?.openListUrl(target, title: title) ?? false) return true;
  return openExternalLink(target);
}

bool _handleTabResult(BuildContext context, TabOpenResult result) {
  if (result == TabOpenResult.limitReached) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Close a tab before opening another.')),
    );
  }
  return result == TabOpenResult.opened;
}

class LinkTarget extends StatelessWidget {
  const LinkTarget({
    super.key,
    required this.url,
    required this.child,
    this.title,
    this.siteUrl,
  }) : content = null;

  const LinkTarget.content({
    super.key,
    required ContentRoute this.content,
    required this.child,
    this.siteUrl,
  }) : url = null,
       title = null;

  final String? url;
  final String? title;
  final String? siteUrl;
  final ContentRoute? content;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    onTertiaryTapUp: content != null
        ? (_) => _handleTabResult(
            context,
            ShellScope.read(
              context,
            ).openContentInNewTab(content!, siteUrl: siteUrl),
          )
        : url != null
        ? (_) => openLink(
            context,
            url!,
            title: title,
            siteUrl: siteUrl,
            newTab: true,
          )
        : null,
    child: child,
  );
}
