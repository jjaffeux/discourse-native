import 'dart:async';

import 'package:flutter/widgets.dart';

import 'shell_controller.dart';
import 'shell_scope.dart';

typedef AccountActivityBuilder =
    Widget Function(BuildContext context, ShellController controller);

enum _AccountActivityRequest {
  notifications,
  replyNotifications,
  bookmarks,
  userActivity;

  Future<void> load(ShellController controller, String siteUrl) =>
      switch (this) {
        notifications => controller.loadNotifications(siteUrl),
        replyNotifications => controller.loadReplyNotifications(siteUrl),
        bookmarks => controller.loadBookmarks(siteUrl),
        userActivity => controller.loadUserActivity(siteUrl),
      };
}

class AccountActivityLoader extends StatelessWidget {
  const AccountActivityLoader.notifications({
    super.key,
    required this.siteUrl,
    required this.builder,
  }) : _request = _AccountActivityRequest.notifications;

  const AccountActivityLoader.bookmarks({
    super.key,
    required this.siteUrl,
    required this.builder,
  }) : _request = _AccountActivityRequest.bookmarks;

  const AccountActivityLoader.replyNotifications({
    super.key,
    required this.siteUrl,
    required this.builder,
  }) : _request = _AccountActivityRequest.replyNotifications;

  const AccountActivityLoader.userActivity({
    super.key,
    required this.siteUrl,
    required this.builder,
  }) : _request = _AccountActivityRequest.userActivity;

  final String siteUrl;
  final AccountActivityBuilder builder;
  final _AccountActivityRequest _request;

  @override
  Widget build(BuildContext context) =>
      ShellSelector<({ShellController controller, bool loaded})>(
        select: (controller) =>
            (controller: controller, loaded: controller.loaded),
        builder: (context, shell, _) => _AccountActivityRequestView(
          controller: shell.controller,
          controllerLoaded: shell.loaded,
          siteUrl: siteUrl,
          request: _request,
          child: builder(context, shell.controller),
        ),
      );
}

typedef _RequestIdentity = ({
  ShellController controller,
  String siteUrl,
  _AccountActivityRequest request,
});

class _AccountActivityRequestView extends StatefulWidget {
  const _AccountActivityRequestView({
    required this.controller,
    required this.controllerLoaded,
    required this.siteUrl,
    required this.request,
    required this.child,
  });

  final ShellController controller;
  final bool controllerLoaded;
  final String siteUrl;
  final _AccountActivityRequest request;
  final Widget child;

  @override
  State<_AccountActivityRequestView> createState() =>
      _AccountActivityRequestViewState();
}

class _AccountActivityRequestViewState
    extends State<_AccountActivityRequestView> {
  _RequestIdentity? _requestIdentity;
  _RequestIdentity? _loadedRequestIdentity;
  bool _requestInFlight = false;

  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(_AccountActivityRequestView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.request != widget.request ||
        (!oldWidget.controllerLoaded && widget.controllerLoaded)) {
      _request();
    }
  }

  void _request() {
    final identity = (
      controller: widget.controller,
      siteUrl: widget.siteUrl,
      request: widget.request,
    );
    if (_loadedRequestIdentity == identity && widget.controller.loaded) return;
    if (_requestIdentity == identity && _requestInFlight) return;
    _requestIdentity = identity;
    _requestInFlight = true;
    unawaited(_load(identity));
  }

  Future<void> _load(_RequestIdentity identity) async {
    try {
      await identity.controller.load();
      if (!mounted ||
          _requestIdentity != identity ||
          !identity.controller.loaded) {
        return;
      }
      _loadedRequestIdentity = identity;
      await identity.request.load(identity.controller, identity.siteUrl);
    } catch (_) {
      return;
    } finally {
      if (_requestIdentity == identity) _requestInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
