import 'package:flutter/widgets.dart';

import '../data/site_lifecycle.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

/// The reader and account session that made a rendered post action available.
final class PostActionOwner {
  PostActionOwner._(
    this._tab,
    this._siteUrl,
    this._lease,
    this._routeId,
    this._postId,
  );

  factory PostActionOwner.capture(
    BuildContext context, {
    required String siteUrl,
    required int postId,
  }) {
    final tab = ForumTabScope.tabOf(context);
    return PostActionOwner._(
      tab,
      siteUrl,
      tab.shell.lifecycle.capture(siteUrl),
      tab.currentContent?.id,
      postId,
    );
  }

  final ShellTabContext _tab;
  final String _siteUrl;
  final SiteLease _lease;
  final String? _routeId;
  final int _postId;

  bool isCurrent(
    BuildContext context, {
    required String siteUrl,
    required int postId,
  }) =>
      context.mounted &&
      identical(ShellScope.maybeRead(context), _tab.shell) &&
      _lease.isCurrent &&
      siteUrl == _siteUrl &&
      postId == _postId &&
      _tab.isCurrent &&
      _tab.siteUrl == _siteUrl &&
      ForumTabScope.tabOf(context).tabId == _tab.tabId &&
      _tab.currentContent?.id == _routeId;
}
