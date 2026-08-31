import 'dart:async';

import 'package:flutter/material.dart';

import '../models/discourse_user.dart';
import '../models/do_not_disturb.dart';
import '../models/notification_totals.dart';
import '../models/user_status.dart';
import '../plugin_api/plugin_scope.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'bookmark_list.dart';
import 'do_not_disturb_dialog.dart';
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

@immutable
class UserMenuSection {
  const UserMenuSection({
    required this.id,
    required this.icon,
    required this.label,
    this.rows = const [],
    this.badge = 0,
    this.plugin,
  });

  static const String notificationsId = 'all';

  static const String repliesId = 'replies';

  static const String bookmarksId = 'bookmarks';

  static const String messagesId = 'messages';

  static const String profileId = 'profile';

  final String id;
  final DIconData icon;
  final String label;

  final List<UserMenuRow> rows;

  final int badge;
  final PluginUserMenuSection? plugin;

  bool get isNotifications => id == notificationsId;
  bool get isReplies => id == repliesId;
  bool get isBookmarks => id == bookmarksId;
  bool get isMessages => id == messagesId;
  bool get isProfile => id == profileId;

  bool get isPlaceholder =>
      !isNotifications &&
      !isReplies &&
      !isBookmarks &&
      plugin == null &&
      !isMessages &&
      !isProfile;
}

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

  final String? detail;
  final UserStatus? status;
  final int? userId;

  bool get isDrafts => id == 'drafts';
  bool get isSummary => id == 'summary';
  bool get isActivity => id == 'activity';
  bool get isUserStatus => id == 'user-status';
  bool get isPreferences => id == 'preferences';
  bool get isDoNotDisturb => id == 'do-not-disturb';
  bool get isHidePresence => id == 'hide-presence';
}

enum UserMenuAction { disconnect, pauseNotifications, dismiss }

List<UserMenuSection> userMenuSections(
  NotificationTotals? totals, {
  DiscourseUser? user,
  bool userStatusEnabled = false,
  List<PluginUserMenuSection> pluginSections = const [],
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
    for (final contribution in pluginSections)
      UserMenuSection(
        id: contribution.id.id,
        icon: contribution.icon,
        label: contribution.label,
        badge: contribution.badge,
        plugin: contribution,
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
        const UserMenuRow(DIcons.toggleOn, 'Online', id: 'hide-presence'),
        const UserMenuRow(
          DIcons.toggleOff,
          'Pause notifications',
          id: 'do-not-disturb',
        ),
        const UserMenuRow(DIcons.user, 'Summary', id: 'summary'),
        const UserMenuRow(DIcons.list, 'Activity', id: 'activity'),
        const UserMenuRow(DIcons.pencil, 'Drafts', id: 'drafts'),
        const UserMenuRow(DIcons.gear, 'Preferences', id: 'preferences'),
      ],
    ),
  ];
}

class UserMenuPanel extends StatefulWidget {
  const UserMenuPanel({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  static const double width = 380;
  static const double height = 460;
  static const double railWidth = 52;

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
            pluginSections: siteUrl == null || menu.user == null
                ? const []
                : PluginScope.of(context).registry.userMenuSections(
                    PluginUserMenuContext(
                      siteUrl: siteUrl,
                      user: menu.user!,
                      totals: controller.accountActivity.totalsFor(siteUrl),
                    ),
                  ),
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
                        onPauseNotifications: () {
                          final siteUrl = menu.siteUrl;
                          if (siteUrl == null) return;
                          final dialog = showDoNotDisturbDialog(
                            context,
                            siteUrl: siteUrl,
                            controller: controller,
                          );
                          widget.onDismiss();
                          unawaited(dialog);
                        },
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

class _SectionBody extends StatelessWidget {
  const _SectionBody({
    required this.section,
    required this.siteUrl,
    required this.host,
    required this.onDisconnect,
    required this.onDismiss,
    required this.onPauseNotifications,
    this.showHeader = true,
  });

  final UserMenuSection section;
  final String? siteUrl;
  final String? host;
  final VoidCallback onDisconnect;
  final VoidCallback onPauseNotifications;

  final VoidCallback onDismiss;

  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final siteUrl = this.siteUrl;
    final controller = ShellScope.read(context);

    List<Widget> rows() => [
      if (section.plugin case final contribution?)
        contribution.builder(
          context,
          PluginUserMenuRenderContext(onDismiss: onDismiss),
        )
      else if (section.isNotifications && siteUrl != null)
        NotificationSection(siteUrl: siteUrl, onOpened: onDismiss)
      else if (section.isReplies && siteUrl != null)
        RepliesSection(siteUrl: siteUrl, onOpened: onDismiss)
      else if (section.isBookmarks && siteUrl != null)
        BookmarkSection(siteUrl: siteUrl, onOpened: onDismiss)
      else
        for (final row in section.rows)
          if (row.isHidePresence && siteUrl != null)
            _HidePresenceTile(siteUrl: siteUrl)
          else if (row.isDoNotDisturb && siteUrl != null)
            _DoNotDisturbTile(siteUrl: siteUrl, onPause: onPauseNotifications)
          else
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
                  ? () => unawaited(
                      showUserStatusEditor(context, siteUrl: siteUrl),
                    )
                  : row.isSummary && siteUrl != null
                  ? () {
                      onDismiss();
                      controller.openUserSummary(siteUrl);
                    }
                  : row.isActivity && siteUrl != null
                  ? () {
                      onDismiss();
                      controller.openUserActivity(siteUrl);
                    }
                  : row.isDrafts && siteUrl != null
                  ? () {
                      onDismiss();
                      controller.openDrafts(siteUrl);
                    }
                  : row.isPreferences && siteUrl != null
                  ? () {
                      onDismiss();
                      controller.openPreferences(siteUrl);
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

class _DoNotDisturbTile extends StatelessWidget {
  const _DoNotDisturbTile({required this.siteUrl, required this.onPause});

  final String siteUrl;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    return ListenableBuilder(
      listenable: controller.doNotDisturb,
      builder: (context, _) {
        final theme = Theme.of(context);
        final state = controller.doNotDisturb.stateFor(siteUrl);
        final active = state.isActiveAt(DateTime.now());
        final until = state.until;
        final detail = active && until != null && !state.isEternal
            ? doNotDisturbRemainingLabel(until)
            : null;
        final localizations = MaterialLocalizations.of(context);
        final value = state.saving
            ? 'Saving'
            : active
            ? state.isEternal
                  ? 'On, no expiration'
                  : 'On, until ${localizations.formatMediumDate(until!.toLocal())} '
                        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(until.toLocal()))}'
            : 'Off';
        final messenger = ScaffoldMessenger.maybeOf(context);

        Future<void> resume() async {
          final error = await controller.doNotDisturb.resume(siteUrl);
          if (error != null && messenger?.mounted == true) {
            messenger!.showSnackBar(SnackBar(content: Text(error)));
          }
        }

        final VoidCallback? action = state.saving
            ? null
            : active
            ? () => unawaited(resume())
            : onPause;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Semantics(
            key: const ValueKey('pause-notifications-row'),
            container: true,
            button: true,
            enabled: !state.saving,
            toggled: active,
            label: 'Pause notifications',
            value: value,
            onTap: action,
            child: ExcludeSemantics(
              child: InkWell(
                onTap: action,
                borderRadius: BorderRadius.circular(6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        if (state.saving)
                          const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          )
                        else
                          DIcon(
                            active ? DIcons.toggleOn : DIcons.toggleOff,
                            size: 18,
                            color: active
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Pause notifications',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (detail != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            detail,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
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

typedef _HidePresenceSnapshot = ({bool? hidden, bool saving, String? error});

class _HidePresenceTile extends StatelessWidget {
  const _HidePresenceTile({required this.siteUrl});

  static const semanticsKey = ValueKey('user-menu-hide-presence');

  final String siteUrl;

  @override
  Widget build(BuildContext context) => ShellSelector<_HidePresenceSnapshot>(
    select: (controller) => (
      hidden: controller.hidePresenceFor(siteUrl),
      saving: controller.hidePresenceWriteInFlight(siteUrl),
      error: controller.hidePresenceErrorFor(siteUrl),
    ),
    builder: (context, state, _) {
      final controller = ShellScope.read(context);
      final theme = Theme.of(context);
      final hidden = state.hidden;
      final loading = hidden == null && state.error == null;
      final title = switch ((hidden, state.error)) {
        (true, _) => 'Offline',
        (false, _) => 'Online',
        (null, null) => 'Loading presence…',
        (null, _) => 'Presence unavailable',
      };
      final VoidCallback? onTap = state.saving || loading
          ? null
          : hidden == null
          ? () => unawaited(controller.retryHidePresence(siteUrl))
          : () => unawaited(controller.toggleHidePresence(siteUrl));
      final semanticsLabel = hidden == null ? 'Presence' : title;
      final semanticsValue = state.saving
          ? 'Saving'
          : loading
          ? 'Loading'
          : null;
      final semanticsHint = hidden == null && state.error != null
          ? 'Retry loading the presence setting'
          : 'Toggle presence features';

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              key: semanticsKey,
              container: true,
              button: true,
              enabled: onTap != null,
              toggled: hidden == null ? null : !hidden,
              label: semanticsLabel,
              value: semanticsValue,
              hint: semanticsHint,
              liveRegion: state.saving || loading,
              onTap: onTap,
              child: ExcludeSemantics(
                child: Tooltip(
                  message: 'Toggle presence features',
                  excludeFromSemantics: true,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(6),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            DIcon(
                              hidden == false
                                  ? DIcons.toggleOn
                                  : DIcons.toggleOff,
                              size: 18,
                              color: hidden == false
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            if (state.saving)
                              const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator.adaptive(
                                  strokeWidth: 2,
                                ),
                              )
                            else if (loading)
                              DIcon(
                                DIcons.farClock,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant,
                              )
                            else if (hidden == null)
                              Text(
                                'Retry',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (state.error case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(36, 1, 8, 7),
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  label: error,
                  child: ExcludeSemantics(
                    child: Text(
                      error,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

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
    final rowKey = ValueKey('user-menu-row-${row.id ?? row.title}');
    final tile = InkWell(
      key: rowKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
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
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: onTap == null
          ? tile
          : Semantics(
              button: true,
              label: [row.title, ?detail].join(', '),
              onTap: onTap,
              excludeSemantics: true,
              child: tile,
            ),
    );
  }
}

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
        onPauseNotifications: () =>
            Navigator.of(nestedContext).pop(UserMenuAction.pauseNotifications),
        onDisconnect: () =>
            Navigator.of(nestedContext).pop(UserMenuAction.disconnect),
      ),
    );

    if (action == null || !context.mounted) return;

    final controller = ShellScope.read(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop();

    if (action == UserMenuAction.disconnect) {
      controller.disconnectInstance(siteUrl).ignore();
    } else if (action == UserMenuAction.pauseNotifications) {
      final dialogContext = navigator.context;
      if (!dialogContext.mounted) return;
      unawaited(
        showDoNotDisturbDialog(
          dialogContext,
          siteUrl: siteUrl,
          controller: controller,
        ),
      );
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
            pluginSections: PluginScope.of(context).registry.userMenuSections(
              PluginUserMenuContext(
                siteUrl: currentSiteUrl,
                user: user,
                totals: controller.accountActivity.totalsFor(currentSiteUrl),
              ),
            ),
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

class UserMenuAvatar extends StatelessWidget {
  const UserMenuAvatar({
    super.key,
    required this.avatarUrl,
    required this.initial,
    required this.connecting,
    this.size = 30,
  });

  final String? avatarUrl;

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
