import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user_status.dart';
import 'shell_scope.dart';
import 'site_emoji_image.dart';

/// Renders one user's live custom status and removes it when it expires.
///
/// Emoji-only placements match core's compact post/chat treatment; richer
/// identity surfaces opt into [showDescription]. The description is always
/// available through the tooltip and accessibility label.
class UserStatusMessage extends StatelessWidget {
  const UserStatusMessage({
    super.key,
    required this.siteUrl,
    required this.status,
    this.userId,
    this.showDescription = false,
    this.size = 16,
    this.style,
    this.descriptionMaxWidth = 180,
    this.leadingGap = 0,
    this.badgeBackgroundColor,
    this.badgePadding = 0,
  });

  final String siteUrl;
  final int? userId;
  final UserStatus? status;
  final bool showDescription;
  final double size;
  final TextStyle? style;
  final double descriptionMaxWidth;
  final double leadingGap;
  final Color? badgeBackgroundColor;
  final double badgePadding;

  @override
  Widget build(BuildContext context) {
    if (ShellScope.maybeIdentityOf(context) == null) {
      return _ExpiringUserStatus(
        siteUrl: siteUrl,
        status: status,
        showDescription: showDescription,
        size: size,
        style: style,
        descriptionMaxWidth: descriptionMaxWidth,
        leadingGap: leadingGap,
        badgeBackgroundColor: badgeBackgroundColor,
        badgePadding: badgePadding,
      );
    }
    return ShellSelector<UserStatus?>(
      select: (controller) => controller.userStatusFor(siteUrl, userId, status),
      builder: (context, liveStatus, child) => _ExpiringUserStatus(
        siteUrl: siteUrl,
        status: liveStatus,
        showDescription: showDescription,
        size: size,
        style: style,
        descriptionMaxWidth: descriptionMaxWidth,
        leadingGap: leadingGap,
        badgeBackgroundColor: badgeBackgroundColor,
        badgePadding: badgePadding,
      ),
    );
  }
}

class _ExpiringUserStatus extends StatefulWidget {
  const _ExpiringUserStatus({
    required this.siteUrl,
    required this.status,
    required this.showDescription,
    required this.size,
    required this.style,
    required this.descriptionMaxWidth,
    required this.leadingGap,
    required this.badgeBackgroundColor,
    required this.badgePadding,
  });

  final String siteUrl;
  final UserStatus? status;
  final bool showDescription;
  final double size;
  final TextStyle? style;
  final double descriptionMaxWidth;
  final double leadingGap;
  final Color? badgeBackgroundColor;
  final double badgePadding;

  @override
  State<_ExpiringUserStatus> createState() => _ExpiringUserStatusState();
}

class _ExpiringUserStatusState extends State<_ExpiringUserStatus> {
  Timer? _expiryTimer;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _scheduleExpiry();
  }

  @override
  void didUpdateWidget(_ExpiringUserStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) _scheduleExpiry();
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final status = widget.status;
    final remaining = status?.endsAt?.difference(DateTime.now());
    _expired = status == null || status.isActiveAt(DateTime.now()) == false;
    if (!_expired && remaining != null) {
      _expiryTimer = Timer(remaining, () {
        if (mounted) setState(() => _expired = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    if (_expired || status == null) return const SizedBox.shrink();

    final tooltip = _tooltip(context, status);
    final emoji = SiteEmojiImage(
      siteUrl: widget.siteUrl,
      name: status.emoji,
      size: widget.size,
      alt: status.description,
      style: widget.style,
    );
    Widget content = Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        container: true,
        child: ExcludeSemantics(
          child: widget.showDescription
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    emoji,
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: widget.descriptionMaxWidth,
                      ),
                      child: Text(
                        status.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: widget.style,
                      ),
                    ),
                  ],
                )
              : emoji,
        ),
      ),
    );
    if (widget.badgeBackgroundColor case final background?) {
      content = DecoratedBox(
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Padding(
          padding: EdgeInsets.all(widget.badgePadding),
          child: content,
        ),
      );
    }
    return widget.leadingGap == 0
        ? content
        : Padding(
            padding: EdgeInsetsDirectional.only(start: widget.leadingGap),
            child: content,
          );
  }

  String _tooltip(BuildContext context, UserStatus status) {
    final endsAt = status.endsAt?.toLocal();
    if (endsAt == null) return status.description;
    final localizations = MaterialLocalizations.of(context);
    return '${status.description} — until '
        '${localizations.formatMediumDate(endsAt)} '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(endsAt))}';
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }
}
