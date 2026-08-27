import 'dart:async';

import 'package:flutter/material.dart';

import '../models/discourse_user.dart';
import '../models/notification_totals.dart';
import '../models/user_status.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'bookmark_list.dart';
import 'notification_list.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';
import 'user_menu_message.dart';
import 'user_status.dart';
import 'user_status_editor.dart';

typedef _UserMenuPanelSnapshot = ({
  String? siteUrl,
  String? host,
  DiscourseUser? user,
  int draftCount,
  bool userStatusEnabled,
});
typedef _SectionListSnapshot = ({
  ShellController controller,
  String? siteUrl,
  String? host,
  DiscourseUser? user,
  bool userStatusEnabled,
});

/// Everything the avatar in the top right leads to.
///
/// The sections are Discourse's own user menu tabs. Notifications, Replies,
/// Bookmarks and Chat are backed by the site, Messages leaves the menu for the
/// full inbox, and the account has its own actions. Rows without a native
/// action remain stand-ins and use [ShellColors.placeholder], so what is
/// orange is what is still to do.
@immutable
class UserMenuSection {
  const UserMenuSection({
    required this.id,
    required this.icon,
    required this.label,
    this.rows = const [],
    this.badge = 0,
  });

  /// The notifications section. First, and where the menu opens.
  static const String notificationsId = 'all';

  /// The server-filtered reply notifications section.
  static const String repliesId = 'replies';

  /// The bookmarks section.
  static const String bookmarksId = 'bookmarks';

  /// The server-filtered chat notification section.
  static const String chatId = 'chat';

  /// The messages section, which opens the full private-message topic list.
  static const String messagesId = 'messages';

  /// The account section. Always last, and separated from the rest.
  static const String profileId = 'profile';

  final String id;
  final DIconData icon;
  final String label;

  /// Static rows. A row stays in the placeholder color until its native action
  /// is supplied by [_SectionBody].
  final List<UserMenuRow> rows;

  /// Real count from `/notifications/totals.json` where we have one, so the
  /// tabs are not lying about how much is waiting even while their lists are.
  final int badge;

  bool get isNotifications => id == notificationsId;
  bool get isReplies => id == repliesId;
  bool get isBookmarks => id == bookmarksId;
  bool get isChat => id == chatId;
  bool get isMessages => id == messagesId;
  bool get isProfile => id == profileId;

  /// True for the tabs that lead nowhere yet, which is what the placeholder
  /// color marks.
  bool get isPlaceholder =>
      !isNotifications &&
      !isReplies &&
      !isBookmarks &&
      !isChat &&
      !isMessages &&
      !isProfile;
}

/// One line inside a section. Wiring stays in [_SectionBody] so this remains a
/// small description of the server-independent menu shape.
@immutable
class UserMenuRow {
  const UserMenuRow(
    this.icon,
    this.title, {
    this.id,
    this.detail,
    this.status,
    this.userId,
  });

  final DIconData icon;
  final String title;
  final String? id;

  /// Trailing text, such as a count.
  final String? detail;
  final UserStatus? status;
  final int? userId;

  bool get isDrafts => id == 'drafts';
  bool get isSummary => id == 'summary';
  bool get isUserStatus => id == 'user-status';
}

/// Results a section can hand back to whatever opened it.
enum UserMenuAction {
  disconnect,

  /// The section did something that leaves nothing to come back to — opening
  /// a notification, say — so the menu should get out of the way.
  dismiss,
}

/// The tabs, in the order Discourse shows them, with the account last.
List<UserMenuSection> userMenuSections(
  NotificationTotals? totals, {
  DiscourseUser? user,
  bool userStatusEnabled = false,
}) {
  return [
    UserMenuSection(
      id: UserMenuSection.notificationsId,
      icon: DIcons.bell,
      label: 'Notifications',
      badge: totals?.unreadNotifications ?? 0,
    ),
    const UserMenuSection(
      id: UserMenuSection.repliesId,
      icon: DIcons.reply,
      label: 'Replies',
    ),
    const UserMenuSection(
      id: 'likes',
      icon: DIcons.heart,
      label: 'Likes',
      rows: [
        UserMenuRow(
          DIcons.heart,
          'markdoerr liked your post in Outreach chat 2026',
        ),
        UserMenuRow(DIcons.heart, 'flavia liked your post in Daily Log'),
      ],
    ),
    UserMenuSection(
      id: UserMenuSection.messagesId,
      icon: DIcons.envelope,
      label: 'Messages',
      badge: totals?.unreadPersonalMessages ?? 0,
    ),
    const UserMenuSection(
      id: UserMenuSection.bookmarksId,
      icon: DIcons.bookmark,
      label: 'Bookmarks',
    ),
    const UserMenuSection(
      id: 'invites',
      icon: DIcons.paperPlane,
      label: 'Invites',
      rows: [UserMenuRow(DIcons.paperPlane, 'No pending invites')],
    ),
    if (totals?.hasChatEnabled == true && user?.hasChatEnabled != false)
      UserMenuSection(
        id: UserMenuSection.chatId,
        icon: DIcons.comment,
        label: 'Chat',
        badge: totals?.chatNotifications ?? 0,
      ),
    UserMenuSection(
      id: 'other',
      icon: DIcons.ellipsis,
      label: 'Other',
      badge: totals?.unseenReviewables ?? 0,
      rows: const [
        UserMenuRow(DIcons.flag, '2 posts waiting in the review queue'),
        UserMenuRow(DIcons.certificate, 'You earned the Nice Reply badge'),
      ],
    ),
    UserMenuSection(
      id: UserMenuSection.profileId,
      icon: DIcons.user,
      label: 'Profile',
      rows: [
        if (userStatusEnabled)
          UserMenuRow(
            DIcons.farFaceSmile,
            user?.status?.description ?? 'Set a custom status',
            id: 'user-status',
            status: user?.status,
            userId: user?.id,
          ),
        const UserMenuRow(DIcons.toggleOn, 'Online'),
        const UserMenuRow(DIcons.toggleOff, 'Pause notifications'),
        const UserMenuRow(DIcons.user, 'Summary', id: 'summary'),
        const UserMenuRow(DIcons.list, 'Activity'),
        const UserMenuRow(DIcons.pencil, 'Drafts', id: 'drafts'),
        const UserMenuRow(DIcons.gear, 'Preferences'),
      ],
    ),
  ];
}

/// The pointer form of the menu: the sections side by side with the tab rail
/// that switches between them, floating under the avatar.
class UserMenuPanel extends StatefulWidget {
  const UserMenuPanel({super.key, required this.onDismiss});

  /// Closes whatever is showing this, so an action can be taken without the
  /// menu still hanging over the result.
  final VoidCallback onDismiss;

  static const double width = 380;
  static const double height = 460;
  static const double railWidth = 52;

  /// Gap kept between the panel and the window edges.
  ///
  /// The menu overlay pins itself flush to whichever edge it would otherwise
  /// overflow, and the avatar it hangs from is in the very corner, so the
  /// margin has to come from inside the panel: it draws its own surface within
  /// a layout box this much larger.
  static const double margin = 8;

  @override
  State<UserMenuPanel> createState() => _UserMenuPanelState();
}

class _UserMenuPanelState extends State<UserMenuPanel> {
  String _sectionId = 'all';

  @override
  Widget build(BuildContext context) => ShellSelector<_UserMenuPanelSnapshot>(
    select: (controller) {
      final instance = controller.currentInstance;
      return (
        siteUrl: instance?.url,
        host: instance?.host,
        user: instance?.user,
        draftCount: instance?.user?.draftCount ?? 0,
        userStatusEnabled: instance?.config.userStatusEnabled ?? false,
      );
    },
    builder: (context, menu, _) {
      final theme = Theme.of(context);
      final controller = ShellScope.read(context);

      return ListenableBuilder(
        listenable: controller.accountActivity.totalsListenable,
        builder: (context, _) {
          final siteUrl = menu.siteUrl;
          final sections = userMenuSections(
            siteUrl == null
                ? null
                : controller.accountActivity.totalsFor(siteUrl),
            user: menu.user,
            userStatusEnabled: menu.userStatusEnabled,
          );
          final section = sections.firstWhere(
            (candidate) => candidate.id == _sectionId,
            orElse: () => sections.first,
          );

          return Padding(
            padding: const EdgeInsets.only(
              right: UserMenuPanel.margin,
              bottom: UserMenuPanel.margin,
            ),
            child: Material(
              color: theme.shell.floating,
              elevation: 8,
              shadowColor: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: UserMenuPanel.width,
                height: UserMenuPanel.height,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _SectionBody(
                        section: section,
                        siteUrl: menu.siteUrl,
                        host: menu.host,
                        onDismiss: widget.onDismiss,
                        onDisconnect: () {
                          widget.onDismiss();
                          final siteUrl = menu.siteUrl;
                          if (siteUrl != null) {
                            controller.disconnectInstance(siteUrl).ignore();
                          }
                        },
                      ),
                    ),
                    VerticalDivider(width: 1, color: theme.shell.divider),
                    SizedBox(
                      width: UserMenuPanel.railWidth,
                      child: _TabRail(
                        sections: sections,
                        selectedId: section.id,
                        onSelect: (id) {
                          final selected = sections.firstWhere(
                            (candidate) => candidate.id == id,
                          );
                          if (selected.isMessages) {
                            widget.onDismiss();
                            _openMessages(controller);
                            return;
                          }
                          setState(() => _sectionId = id);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

/// The icon column down the right edge, with the account tab set apart at the
/// bottom the way Discourse sets it apart.
class _TabRail extends StatelessWidget {
  const _TabRail({
    required this.sections,
    required this.selectedId,
    required this.onSelect,
  });

  final List<UserMenuSection> sections;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          for (final section in sections) ...[
            if (section.isProfile)
              Divider(
                color: theme.shell.divider,
                indent: 10,
                endIndent: 10,
                height: 17,
              ),
            _TabButton(
              section: section,
              selected: section.id == selectedId,
              onTap: () => onSelect(section.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final UserMenuSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Semantics(
        key: ValueKey('user-menu-tab-${section.id}'),
        button: true,
        selected: selected,
        label: section.label,
        child: Tooltip(
          message: section.label,
          excludeFromSemantics: true,
          waitDuration: const Duration(milliseconds: 400),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? theme.shell.hover : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  DIcon(
                    section.icon,
                    size: 20,
                    color: selected
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  if (section.badge > 0)
                    Positioned(
                      right: -8,
                      top: -6,
                      child: _Badge(count: section.badge),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One section's contents, shared by the panel and the nested sheet.
class _SectionBody extends StatelessWidget {
  const _SectionBody({
    required this.section,
    required this.siteUrl,
    required this.host,
    required this.onDisconnect,
    required this.onDismiss,
    this.showHeader = true,
  });

  final UserMenuSection section;
  final String? siteUrl;
  final String? host;
  final VoidCallback onDisconnect;

  /// Closes the menu, for a row that has taken the user somewhere else.
  final VoidCallback onDismiss;

  /// The sheet already names the section in its own header, so it turns this
  /// off; the panel has nowhere else to say which tab is showing.
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final siteUrl = this.siteUrl;
    final controller = ShellScope.read(context);

    List<Widget> rows() => [
      if (section.isNotifications && siteUrl != null)
        NotificationSection(siteUrl: siteUrl, onOpened: onDismiss)
      else if (section.isReplies && siteUrl != null)
        RepliesSection(siteUrl: siteUrl, onOpened: onDismiss)
      else if (section.isChat && siteUrl != null)
        ChatNotificationsSection(siteUrl: siteUrl, onOpened: onDismiss)
      else if (section.isBookmarks && siteUrl != null)
        BookmarkSection(siteUrl: siteUrl, onOpened: onDismiss)
      else
        for (final row in section.rows)
          _RowTile(
            row: row,
            leading: row.isUserStatus && siteUrl != null && row.status != null
                ? UserStatusMessage(
                    siteUrl: siteUrl,
                    userId: row.userId,
                    status: row.status,
                    size: 18,
                  )
                : null,
            detail: row.isDrafts && siteUrl != null
                ? switch (controller.draftCountFor(siteUrl)) {
                    final count when count > 0 => '$count',
                    _ => null,
                  }
                : row.detail,
            onTap: row.isUserStatus && siteUrl != null
                ? () =>
                      unawaited(showUserStatusEditor(context, siteUrl: siteUrl))
                : row.isSummary && siteUrl != null
                ? () {
                    onDismiss();
                    controller.openUserSummary(siteUrl);
                  }
                : row.isDrafts && siteUrl != null
                ? () {
                    onDismiss();
                    controller.openDrafts(siteUrl);
                  }
                : null,
          ),
      if (section.isProfile) ...[
        Divider(color: theme.shell.divider, height: 17),
        _DisconnectTile(host: host, onTap: onDisconnect),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeader) _SectionHeader(section: section),
        Flexible(
          child: ListenableBuilder(
            listenable: controller.draftList,
            builder: (context, _) => ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: rows(),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section});

  final UserMenuSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.shell.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              section.label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                // Implemented sections and the account use the normal color;
                // stand-ins are the only orange headings.
                color: section.isPlaceholder ? theme.shell.placeholder : null,
              ),
            ),
          ),
          if (section.badge > 0) _Badge(count: section.badge),
        ],
      ),
    );
  }
}

/// A static row. Rows without [onTap] use the shell's placeholder color;
/// actionable rows use the normal foreground and expose button semantics.
class _RowTile extends StatelessWidget {
  const _RowTile({required this.row, this.detail, this.onTap, this.leading});

  final UserMenuRow row;
  final String? detail;
  final VoidCallback? onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = onTap == null ? theme.shell.placeholder : null;
    final tile = InkWell(
      key: ValueKey('user-menu-row-${row.id ?? row.title}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            leading ??
                DIcon(
                  row.icon,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                row.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: color),
              ),
            ),
            if (detail case final detail?)
              Text(
                detail,
                style: theme.textTheme.labelMedium?.copyWith(color: color),
              ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: onTap == null
          ? tile
          : Semantics(
              button: true,
              label: [row.title, ?detail].join(', '),
              child: ExcludeSemantics(child: tile),
            ),
    );
  }
}

/// The one thing in here that is not a placeholder.
class _DisconnectTile extends StatelessWidget {
  const _DisconnectTile({required this.host, required this.onTap});

  final String? host;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              DIcon(
                DIcons.rightFromBracket,
                size: 18,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Disconnect',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.error,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onError,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

/// The touch form of the menu: the sections as a list, each opening a sheet of
/// its own on top of this one rather than swapping the contents underneath.
Future<void> showUserMenuSheet(BuildContext context) {
  final controller = ShellScope.read(context);
  final instance = controller.currentInstance;
  final user = instance?.user;
  if (instance == null || user == null) return Future.value();

  return showShellSheet<void>(
    context: context,
    title: user.displayName,
    padding: const EdgeInsets.symmetric(vertical: 8),
    builder: (sheetContext) => _SectionList(siteUrl: instance.url),
  );
}

class _SectionList extends StatelessWidget {
  const _SectionList({required this.siteUrl});

  final String siteUrl;

  Future<void> _open(
    BuildContext context,
    UserMenuSection section,
    String siteUrl,
    String host,
  ) async {
    if (section.isMessages) {
      final controller = ShellScope.read(context);
      Navigator.of(context).pop();
      _openMessages(controller);
      return;
    }

    final action = await showShellSheet<UserMenuAction>(
      context: context,
      title: section.label,
      nested: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      builder: (nestedContext) => _SectionBody(
        section: section,
        siteUrl: siteUrl,
        host: host,
        showHeader: false,
        onDismiss: () =>
            Navigator.of(nestedContext).pop(UserMenuAction.dismiss),
        onDisconnect: () =>
            Navigator.of(nestedContext).pop(UserMenuAction.disconnect),
      ),
    );

    if (action == null || !context.mounted) return;

    // The sheet the section was opened from is still underneath, and both of
    // them are now in the way: of the topic that was opened, or of the account
    // that is about to stop existing.
    final controller = ShellScope.read(context);
    Navigator.of(context).pop();

    if (action == UserMenuAction.disconnect) {
      controller.disconnectInstance(siteUrl).ignore();
    }
  }

  @override
  Widget build(BuildContext context) => ShellSelector<_SectionListSnapshot>(
    select: (controller) {
      final instance = controller.instances
          .where((instance) => instance.url == siteUrl)
          .firstOrNull;
      return (
        controller: controller,
        siteUrl: instance?.url,
        host: instance?.host,
        user: instance?.user,
        userStatusEnabled: instance?.config.userStatusEnabled ?? false,
      );
    },
    builder: (context, state, _) {
      final controller = state.controller;
      final currentSiteUrl = state.siteUrl;
      final host = state.host;
      if (currentSiteUrl == null || host == null) {
        return UserMenuMessage(
          text: controller.loaded ? 'This site is no longer available.' : null,
        );
      }
      final theme = Theme.of(context);
      final user = state.user;
      if (user == null) {
        return const UserMenuMessage(
          text: 'This account is no longer connected.',
        );
      }

      return ListenableBuilder(
        listenable: controller.accountActivity.totalsListenable,
        builder: (context, _) {
          final sections = userMenuSections(
            controller.accountActivity.totalsFor(currentSiteUrl),
            user: user,
            userStatusEnabled: state.userStatusEnabled,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '@${user.username} · $host',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final section in sections)
                _SectionTile(
                  section: section,
                  onTap: () => _open(context, section, currentSiteUrl, host),
                ),
            ],
          );
        },
      );
    },
  );
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.section, required this.onTap});

  final UserMenuSection section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            DIcon(
              section.icon,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                section.label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: section.isPlaceholder ? theme.shell.placeholder : null,
                ),
              ),
            ),
            if (section.badge > 0) ...[
              _Badge(count: section.badge),
              const SizedBox(width: 8),
            ],
            DIcon(
              DIcons.chevronRight,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the same inbox as the instance sidebar's Messages destination.
///
/// Keeping one destination means both entry points share loading, pagination,
/// scroll restoration, unread state, and the content back stack.
void _openMessages(ShellController controller) {
  final instance = controller.currentInstance;
  if (instance == null) return;

  for (final section in instance.sections) {
    for (final destination in section.destinations) {
      if (destination.id == UserMenuSection.messagesId) {
        controller.selectDestination(destination);
        return;
      }
    }
  }
}

/// The connected user's avatar, a spinner while connecting, or a neutral
/// placeholder when signed out.
class UserMenuAvatar extends StatelessWidget {
  const UserMenuAvatar({
    super.key,
    required this.avatarUrl,
    required this.initial,
    required this.connecting,
    this.size = 30,
  });

  final String? avatarUrl;

  /// First letter of the username, shown until the image arrives.
  final String? initial;

  final bool connecting;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (connecting) {
      return SizedBox(
        width: size,
        height: size,
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      );
    }

    final fallback = ColoredBox(
      color: initial == null
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.primary,
      child: Center(
        child: initial == null
            ? DIcon(
                DIcons.user,
                size: size * 0.6,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : Text(
                initial!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: AvatarImage(url: avatarUrl, size: size, fallback: fallback),
      ),
    );
  }
}
