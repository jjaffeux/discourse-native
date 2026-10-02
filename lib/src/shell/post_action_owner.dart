import 'package:flutter/widgets.dart';

import '../data/site_lifecycle.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

/// The reader and account session that made a rendered post action available.
final class PostActionOwner {
  PostActionOwner._(
    this._shell,
    this._siteUrl,
    this._lease,
    this._tabId,
    this._routeId,
    this._postId,
  );

  factory PostActionOwner.capture(
    BuildContext context, {
    required String siteUrl,
    required int postId,
  }) => ForumTabScope.read(
    context,
    (shell) => PostActionOwner._(
      shell,
      siteUrl,
      shell.lifecycle.capture(siteUrl),
      shell.activeTabId,
      shell.currentContent?.id,
      postId,
    ),
  );

  final ShellController _shell;
  final String _siteUrl;
  final SiteLease _lease;
  final String? _tabId;
  final String? _routeId;
  final int _postId;

  bool isCurrent(
    BuildContext context, {
    required String siteUrl,
    required int postId,
  }) =>
      context.mounted &&
      identical(ShellScope.maybeRead(context), _shell) &&
      _lease.isCurrent &&
      siteUrl == _siteUrl &&
      postId == _postId &&
      _shell.currentInstance?.url == _siteUrl &&
      _shell.activeTabId == _tabId &&
      _shell.currentContent?.id == _routeId;
}
