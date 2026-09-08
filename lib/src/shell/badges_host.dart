import 'dart:async';

import 'package:flutter/material.dart';

import '../models/badge_route.dart';
import '../models/discourse_instance.dart';
import 'badges_page.dart';
import 'open_link.dart';
import 'shell_scope.dart';

class BadgesHost extends StatefulWidget {
  const BadgesHost({super.key, required this.siteUrl, required this.route});
  final String siteUrl;
  final BadgeRoute route;

  @override
  State<BadgesHost> createState() => _BadgesHostState();
}

typedef _BadgesOwner = ({
  DiscourseInstance? instance,
  Object? session,
  String? username,
  bool enabled,
});

class _BadgesHostState extends State<BadgesHost> {
  bool _loadScheduled = false;

  void _scheduleLoad() {
    if (_loadScheduled) return;
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScheduled = false;
      if (!mounted) return;
      final shell = ShellScope.read(context);
      final instance = shell.instanceFor(widget.siteUrl);
      if (instance != null) {
        unawaited(shell.badges.load(instance, widget.route));
      }
    });
  }

  @override
  Widget build(BuildContext context) => ShellSelector<_BadgesOwner>(
    select: (shell) {
      final instance = shell.instanceFor(widget.siteUrl);
      return (
        instance: instance,
        session: instance == null
            ? null
            : shell.lifecycle.capture(widget.siteUrl).session,
        username: instance?.user?.username,
        enabled: instance?.config.badgesEnabled ?? false,
      );
    },
    builder: (context, owner, _) {
      final instance = owner.instance;
      if (instance == null) return const SizedBox.shrink();
      if (!instance.config.badgesEnabled) {
        return const Center(child: Text('Badges are disabled on this forum.'));
      }
      final shell = ShellScope.read(context);
      _scheduleLoad();
      return ListenableBuilder(
        listenable: shell.badges,
        builder: (context, _) => BadgesPage(
          siteUrl: widget.siteUrl,
          route: widget.route,
          state: shell.badges.stateFor(widget.siteUrl, widget.route),
          currentUsername: instance.user?.username,
          onRefresh: () =>
              shell.badges.load(instance, widget.route, refresh: true),
          onLoadMore: () =>
              unawaited(shell.badges.load(instance, widget.route, more: true)),
          onOpenBadge: (badge) => shell.openBadgeUrl(
            '${widget.siteUrl}${badge.route.path}',
            title: badge.name,
          ),
          onOpenUrl: (url) =>
              unawaited(openLink(context, url, siteUrl: widget.siteUrl)),
        ),
      );
    },
  );
}
