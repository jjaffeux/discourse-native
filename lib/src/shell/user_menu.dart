import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/clock_time.dart';
import '../models/discourse_user.dart';
import '../models/do_not_disturb.dart';
import '../models/notification_totals.dart';
import '../models/user_status.dart';
import '../plugin_api/plugin_scope.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import 'about_dialog.dart';
import 'avatar_image.dart';
import 'bookmark_list.dart';
import 'desktop_header_menu.dart';
import 'do_not_disturb_dialog.dart';
import 'external_link.dart';
import 'invite_list.dart';
import 'notification_list.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'user_card.dart';
import 'user_status.dart';
import 'user_status_editor.dart';

typedef _UserMenuPanelSnapshot = ({
  String? siteUrl,
  DiscourseUser? user,
  int draftCount,
  bool userStatusEnabled,
});
typedef _SectionListSnapshot = ({
  ShellController controller,
  String? siteUrl,
  DiscourseUser? user,
  bool userStatusEnabled,
});

_SectionListSnapshot _sectionListSnapshot(
  ShellController controller,
  String siteUrl,
) {
  final instance = controller.instances
      .where((instance) => instance.url == siteUrl)
      .firstOrNull;
  return (
    controller: controller,
    siteUrl: instance?.url,
    user: instance?.user,
    userStatusEnabled: instance?.config.userStatusEnabled ?? false,
  );
}

@immutable
class UserMenuSection {
  const UserMenuSection({
    required this.id,
    required this.label,
    this.rows = const [],
    this.badge = 0,
    this.plugin,
  });

  static const String notificationsId = 'all';

  static const String repliesId = 'replies';

  static const String likesId = 'likes';

  static const String bookmarksId = 'bookmarks';

  static const String messagesId = 'messages';

  static const String invitesId = 'invites';

  static const String otherId = 'other';

  static const String profileId = 'profile';

  final String id;
  final String label;

  final List<UserMenuRow> rows;

  final int badge;
  final PluginUserMenuSection? plugin;

  bool get isNotifications => id == notificationsId;
  bool get isReplies => id == repliesId;
  bool get isLikes => id == likesId;
  bool get isBookmarks => id == bookmarksId;
  bool get isMessages => id == messagesId;
  bool get isInvites => id == invitesId;
  bool get isOther => id == otherId;
  bool get isProfile => id == profileId;

  bool get isPlaceholder =>
      !isNotifications &&
      !isReplies &&
      !isLikes &&
      !isBookmarks &&
      !isOther &&
      plugin == null &&
      !isMessages &&
      !isInvites &&
      !isProfile;
}

@immutable
class UserMenuRow {
  const UserMenuRow(
    this.icon,
    this.title, {
    this.id,
    this.status,
    this.userId,
  });

  final DIconData icon;
  final String title;
  final String? id;

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

List<UserMenuSection> userMenuSections(
  NotificationTotals? totals, {
  DiscourseUser? user,
  bool userStatusEnabled = false,
  int? notificationsBadge,
  int repliesBadge = 0,
  int likesBadge = 0,
  int messagesBadge = 0,
  int bookmarksBadge = 0,
  int otherBadge = 0,
  List<PluginUserMenuSection> pluginSections = const [],
}) {
  return [
    UserMenuSection(
      id: UserMenuSection.notificationsId,
      label: appL10n.notifications,
      badge: notificationsBadge ?? totals?.unreadNotifications ?? 0,
    ),
    UserMenuSection(
      id: UserMenuSection.repliesId,
      label: appL10n.replies,
      badge: repliesBadge,
    ),
    if (user?.likesNotificationsDisabled != true)
      UserMenuSection(
        id: UserMenuSection.likesId,
        label: appL10n.likes,
        badge: likesBadge,
      ),
    UserMenuSection(
      id: UserMenuSection.messagesId,
      label: appL10n.messages,
      badge: messagesBadge,
    ),
    UserMenuSection(
      id: UserMenuSection.bookmarksId,
      label: appL10n.bookmarks,
      badge: bookmarksBadge,
    ),
    if (user?.canInviteToForum == true)
      UserMenuSection(
        id: UserMenuSection.invitesId,
        label: appL10n.invites,
      ),
    for (final contribution in pluginSections)
      UserMenuSection(
        id: contribution.id.id,
        label: contribution.label,
        badge: contribution.badge,
        plugin: contribution,
      ),
    UserMenuSection(
      id: UserMenuSection.otherId,
      label: appL10n.other,
      badge: otherBadge,
    ),
    UserMenuSection(
      id: UserMenuSection.profileId,
      label: appL10n.profile,
      rows: [
        if (userStatusEnabled)
          UserMenuRow(
            DIcons.farFaceSmile,
            user?.status?.description ?? appL10n.setACustomStatus,
            id: 'user-status',
            status: user?.status,
            userId: user?.id,
          ),
        UserMenuRow(DIcons.toggleOn, appL10n.online, id: 'hide-presence'),
        UserMenuRow(
          DIcons.toggleOff,
          appL10n.pauseNotifications,
          id: 'do-not-disturb',
        ),
        UserMenuRow(DIcons.user, appL10n.summary, id: 'summary'),
        UserMenuRow(DIcons.barsStaggered, appL10n.activity, id: 'activity'),
        UserMenuRow(DIcons.pencil, appL10n.drafts, id: 'drafts'),
        UserMenuRow(DIcons.gear, appL10n.preferences, id: 'preferences'),
      ],
    ),
  ];
}

Color _userMenuBorderColor(ThemeData theme) => Color.alphaBlend(
  theme.colorScheme.onSurface.withValues(alpha: 0.12),
  theme.shell.floating,
);

enum UserMenuView { notifications, profile }

class UserMenuPanel extends StatefulWidget {
  const UserMenuPanel({
    super.key,
    required this.onDismiss,
    this.view = UserMenuView.notifications,
  });

  final UserMenuView view;

  final VoidCallback onDismiss;

  static const double width = 400;
  static const double mobileWidth = 320;
  static const double profileWidth = 280;
  static const double height = 460;

  static const double margin = 12;

  @override
  State<UserMenuPanel> createState() => _UserMenuPanelState();
}

class _UserMenuPanelState extends State<UserMenuPanel> {
  String _sectionId = 'all';
  bool _markingRead = false;

  @override
  Widget build(BuildContext context) => ShellSelector<_UserMenuPanelSnapshot>(
    select: (controller) {
      final instance = controller.currentInstance;
      return (
        siteUrl: instance?.url,
        user: instance?.user,
        draftCount: instance?.user?.draftCount ?? 0,
        userStatusEnabled: instance?.config.userStatusEnabled ?? false,
      );
    },
    builder: (context, menu, _) {
      final controller = ShellScope.read(context);

      return ListenableBuilder(
        listenable: controller.accountActivity.totalsListenable,
        builder: (context, _) {
          final siteUrl = menu.siteUrl;
          final totals = siteUrl == null
              ? null
              : controller.accountActivity.totalsFor(siteUrl);
          final pluginSections = siteUrl == null || menu.user == null
              ? const <PluginUserMenuSection>[]
              : PluginScope.of(context).registry.userMenuSections(
                  PluginUserMenuContext(
                    siteUrl: siteUrl,
                    user: menu.user!,
                    totals: totals,
                  ),
                );
          final sections = userMenuSections(
            totals,
            user: menu.user,
            userStatusEnabled: menu.userStatusEnabled,
            notificationsBadge: siteUrl == null
                ? 0
                : controller.allNotificationUnreadCount(siteUrl),
            repliesBadge: siteUrl == null
                ? 0
                : controller.replyNotificationUnreadCount(siteUrl),
            likesBadge: siteUrl == null
                ? 0
                : controller.likeNotificationUnreadCount(siteUrl),
            messagesBadge: siteUrl == null
                ? 0
                : controller.messageNotificationUnreadCount(siteUrl),
            bookmarksBadge: siteUrl == null
                ? 0
                : controller.bookmarkReminderUnreadCount(siteUrl),
            otherBadge: siteUrl == null
                ? 0
                : controller.otherNotificationUnreadCount(
                    siteUrl,
                    pluginSections: pluginSections,
                  ),
            pluginSections: pluginSections,
          );
          final section = sections.firstWhere(
            (candidate) => widget.view == UserMenuView.profile
                ? candidate.isProfile
                : candidate.id == _sectionId,
            orElse: () => sections.first,
          );

          final body = _SectionBody(
            section: section,
            siteUrl: menu.siteUrl,
            showHeader: widget.view == UserMenuView.profile,
            onDismiss: widget.onDismiss,
            onAbout: () => _openAboutAfterMenu(context, widget.onDismiss),
            onPauseNotifications: () {
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
              if (siteUrl != null) {
                controller.disconnectInstance(siteUrl).ignore();
              }
            },
          );
          void selectSection(String id) {
            final selected = sections.firstWhere(
              (candidate) => candidate.id == id,
            );
            final activePath = selected.plugin?.linkWhenActive;
            if (id == _sectionId && activePath != null) {
              widget.onDismiss();
              unawaited(
                _openPluginUserMenuLink(controller, siteUrl!, activePath),
              );
              return;
            }
            setState(() => _sectionId = id);
          }

          final notificationSections = sections
              .where((section) => !section.isProfile && !section.isInvites)
              .toList();
          if (widget.view == UserMenuView.notifications) {
            return DesktopHeaderMenu<String>(
              notificationStyle: true,
              filtersKey: const ValueKey('user-menu-mobile-tabs'),
              controlsKey: ValueKey((
                controller,
                siteUrl,
                siteUrl == null
                    ? null
                    : controller.lifecycle.capture(siteUrl).session,
              )),
              title: context.l10n.notifications,
              action: context.l10n.markAllRead,
              busy: _markingRead,
              onAction: _markingRead || siteUrl == null
                  ? null
                  : () async {
                      final lease = controller.lifecycle.capture(siteUrl);
                      setState(() => _markingRead = true);
                      try {
                        await controller.markAllNotificationsRead(siteUrl);
                      } catch (_) {
                        if (context.mounted && lease.isCurrent) {
                          DToast.show(
                            context,
                            appL10n.couldnTMarkNotificationsAsReadTryAgain,
                            type: DToastType.error,
                          );
                        }
                      } finally {
                        if (mounted && lease.isCurrent) {
                          setState(() => _markingRead = false);
                        }
                      }
                    },
              filters: [
                for (final item in notificationSections)
                  DesktopHeaderMenuFilter(
                    item.id,
                    item.isNotifications ? context.l10n.all : item.label,
                    unread: item.badge,
                    key: ValueKey('user-menu-tab-${item.id}'),
                  ),
              ],
              value: section.id,
              onChanged: selectSection,
              child: body,
            );
          }
          return SizedBox(
            width: UserMenuPanel.profileWidth,
            height: UserMenuPanel.height,
            child: body,
          );
        },
      );
    },
  );
}

Future<void> _openPluginUserMenuLink(
  ShellController controller,
  String siteUrl,
  String path,
) async {
  final url = controller.siteLink(path, siteUrl: siteUrl);
  if (await controller.openNotificationUrl(url)) return;
  await openExternalLink(url);
}

class _SectionBody extends StatelessWidget {
  const _SectionBody({
    required this.section,
    required this.siteUrl,
    required this.onDisconnect,
    required this.onDismiss,
    required this.onPauseNotifications,
    required this.onAbout,
    this.showHeader = true,
  });

  final UserMenuSection section;
  final String? siteUrl;
  final VoidCallback onDisconnect;
  final VoidCallback onPauseNotifications;
  final VoidCallback onAbout;

  final VoidCallback onDismiss;

  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final siteUrl = this.siteUrl;
    final controller = ShellScope.read(context);
    final fillSheet =
        DesktopHeaderMenu.isActiveOf(context) &&
        context.findAncestorWidgetOfExactType<DSheetContent>() != null;

    List<Widget> rows() => [
      if (section.isProfile && siteUrl != null)
        _OwnCardMenuEntry(siteUrl: siteUrl, onDismiss: onDismiss),
      if (section.plugin case final contribution?)
        contribution.builder(
          context,
          PluginUserMenuRenderContext(onDismiss: onDismiss),
        )
      else if (section.isNotifications && siteUrl != null)
        NotificationSection(siteUrl: siteUrl, onOpened: onDismiss)
      else if (section.isReplies && siteUrl != null)
        RepliesSection(siteUrl: siteUrl, onOpened: onDismiss)
      else if (section.isMessages && siteUrl != null)
        MessageNotificationsSection(siteUrl: siteUrl, onOpened: onDismiss)
      else if (section.isLikes && siteUrl != null)
        LikesSection(siteUrl: siteUrl, onOpened: onDismiss)
      else if (section.isBookmarks && siteUrl != null)
        BookmarkSection(siteUrl: siteUrl, onOpened: onDismiss)
      else if (section.isInvites && siteUrl != null)
        InviteSection(siteUrl: siteUrl, onOpened: onDismiss)
      else if (section.isOther && siteUrl != null)
        OtherNotificationsSection(siteUrl: siteUrl, onOpened: onDismiss)
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
                      size: DControlStyle.iconDimension(DControlSize.regular),
                    )
                  : null,
              detail: row.isDrafts && siteUrl != null
                  ? switch (controller.draftCountFor(siteUrl)) {
                      final count when count > 0 => '$count',
                      _ => null,
                    }
                  : null,
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
        _RowTile(
          row: UserMenuRow(DIcons.circleInfo, context.l10n.about, id: 'about'),
          onTap: onAbout,
        ),
        DSeparator(color: theme.shell.divider, space: 17),
        _RowTile(
          row: UserMenuRow(
            DIcons.rightFromBracket,
            context.l10n.disconnect,
            id: 'disconnect',
          ),
          destructive: true,
          onTap: onDisconnect,
        ),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: fillSheet ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (showHeader) _SectionHeader(section: section),
        Flexible(
          fit: fillSheet ? FlexFit.tight : FlexFit.loose,
          child: ListenableBuilder(
            listenable: controller.draftList,
            builder: (context, _) => ListView(
              shrinkWrap: !fillSheet,
              padding: DesktopHeaderMenu.isActiveOf(context)
                  ? const EdgeInsets.all(6)
                  : const EdgeInsets.symmetric(vertical: 6),
              children: rows(),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _openAboutAfterMenu(
  BuildContext context,
  VoidCallback dismiss,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  dismiss();
  await WidgetsBinding.instance.endOfFrame;
  if (!navigator.mounted) return;
  await showNativeAboutDialog(navigator.context);
}

/// Profile actions composed inside the Native dropdown's interaction owner.
class UserProfileMenuItems extends StatelessWidget {
  const UserProfileMenuItems({
    super.key,
    required this.onDismiss,
    this.siteUrl,
    this.statusOnly = false,
  });

  final VoidCallback onDismiss;
  final String? siteUrl;
  final bool statusOnly;

  @override
  Widget build(BuildContext context) => ShellSelector<_SectionListSnapshot>(
    select: (controller) => _sectionListSnapshot(
      controller,
      siteUrl ?? controller.currentInstance?.url ?? '',
    ),
    builder: (context, state, _) {
      final siteUrl = state.siteUrl;
      final user = state.user;
      if (siteUrl == null || user == null) return const SizedBox.shrink();
      final controller = state.controller;
      final tokens = DTokens.of(context);
      Widget rule() => DDropdownMenuSeparator(
        inset: true,
        space: 11,
        color: Color.lerp(tokens.background, tokens.foreground, .12),
      );
      final rows =
          userMenuSections(
                null,
                user: user,
                userStatusEnabled: state.userStatusEnabled,
              )
              .firstWhere((section) => section.isProfile)
              .rows
              .where(
                (row) =>
                    !statusOnly ||
                    row.isUserStatus ||
                    row.isHidePresence ||
                    row.isDoNotDisturb,
              );
      VoidCallback? action(UserMenuRow row) {
        if (row.isUserStatus) {
          return () {
            final editor = showUserStatusEditor(context, siteUrl: siteUrl);
            onDismiss();
            unawaited(editor);
          };
        }
        return () {
          onDismiss();
          if (row.isSummary) controller.openUserSummary(siteUrl);
          if (row.isActivity) controller.openUserActivity(siteUrl);
          if (row.isDrafts) controller.openDrafts(siteUrl);
          if (row.isPreferences) controller.openPreferences(siteUrl);
        };
      }

      return DIconGlyphTheme(
        scale: 1,
        naturalWidth: true,
        child: ListenableBuilder(
          listenable: controller.draftList,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!statusOnly) ...[
                _OwnCardMenuEntry(
                  siteUrl: siteUrl,
                  onDismiss: onDismiss,
                  dropdown: true,
                ),
                rule(),
              ],
              for (final row in rows)
                if (row.isHidePresence)
                  _HidePresenceTile(siteUrl: siteUrl, dropdown: true)
                else if (row.isDoNotDisturb)
                  _DoNotDisturbTile(
                    siteUrl: siteUrl,
                    dropdown: true,
                    onPause: () {
                      final dialog = showDoNotDisturbDialog(
                        context,
                        siteUrl: siteUrl,
                        controller: controller,
                      );
                      onDismiss();
                      unawaited(dialog);
                    },
                  )
                else ...[
                  if (row.isSummary) rule(),
                  DDropdownMenuItem(
                    key: ValueKey('user-menu-row-${row.id}'),
                    leadingGap: 9,
                    leading: row.isUserStatus && row.status != null
                        ? UserStatusMessage(
                            siteUrl: siteUrl,
                            userId: row.userId,
                            status: row.status,
                            size: 14,
                          )
                        : DIcon(
                            row.isPreferences
                                ? DNativeIcons.profileSliders
                                : row.isUserStatus
                                ? DIcons.faceSmile
                                : row.icon,
                            size: 13,
                            color: tokens.mutedForeground,
                          ),
                    trailing: row.isDrafts
                        ? Text(
                            '${controller.draftCountFor(siteUrl)}',
                            style: TextStyle(
                              fontSize: DiscourseTypography.xs,
                              color: tokens.mutedForeground,
                            ),
                          )
                        : null,
                    onPressed: action(row),
                    child: Text(row.title),
                  ),
                ],
              if (!statusOnly) ...[
                rule(),
                DDropdownMenuItem(
                  key: const ValueKey('user-menu-row-about'),
                  leadingGap: 9,
                  leading: DIcon(
                    DIcons.circleQuestion,
                    size: 13,
                    color: tokens.mutedForeground,
                  ),
                  onPressed: () => _openAboutAfterMenu(context, onDismiss),
                  child: Text(context.l10n.about),
                ),
                DDropdownMenuItem(
                  key: const ValueKey('user-menu-row-disconnect'),
                  leadingGap: 9,
                  variant: DDropdownMenuItemVariant.destructive,
                  leading: const DIcon(DIcons.rightFromBracket, size: 13),
                  onPressed: () {
                    onDismiss();
                    controller.disconnectInstance(siteUrl).ignore();
                  },
                  child: Text(context.l10n.disconnect),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Account status actions shared with feature headers through the plugin SDK.
class UserPresenceMenu extends StatefulWidget {
  const UserPresenceMenu({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<UserPresenceMenu> createState() => _UserPresenceMenuState();
}

class _UserPresenceMenuState extends State<UserPresenceMenu> {
  final _menu = DDropdownMenuController();

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    return ListenableBuilder(
      listenable: shell.doNotDisturb,
      builder: (context, _) {
        final hidden = shell.hidePresenceFor(widget.siteUrl);
        final paused = shell.doNotDisturb
            .stateFor(widget.siteUrl)
            .isActiveAt(DateTime.now());
        final label = paused
            ? context.l10n.notificationsPaused
            : hidden == true
            ? context.l10n.offline
            : hidden == false
            ? context.l10n.online
            : context.l10n.presenceUnavailable;
        return DDropdownMenu(
          controller: _menu,
          sheetOnMobile: true,
          mobileSheetVariant: DSheetVariant.adaptiveMenu,
          content: DDropdownMenuContent(
            width: 208,
            align: DPopoverAlign.end,
            semanticLabel: context.l10n.statusAndNotifications,
            children: [
              UserProfileMenuItems(
                siteUrl: widget.siteUrl,
                statusOnly: true,
                onDismiss: _menu.close,
              ),
            ],
          ),
          child: DDropdownMenuTrigger(
            builder: (context, state) => DButton(
              key: const ValueKey('user-presence-menu'),
              variant: DButtonVariant.secondary,
              shape: DButtonShape.pill,
              size: DControlSize.filter,
              tooltip: context.l10n.statusAndNotifications,
              semanticLabel: context.l10n.statusAndNotificationsUsermenu(
                (label).toString(),
              ),
              focusNode: state.focusNode,
              hasPopup: true,
              expanded: state.open,
              onPressed: state.toggle,
              icon: DIcon(
                paused ? DIcons.discourseBellSlash : DIcons.circle,
                color: !paused && hidden == false
                    ? DTokens.of(context).success
                    : DTokens.of(context).mutedForeground,
              ),
              label: const DIcon(DNativeIcons.filterChevron, size: 10),
            ),
          ),
        );
      },
    );
  }
}

class _DoNotDisturbTile extends StatelessWidget {
  const _DoNotDisturbTile({
    required this.siteUrl,
    required this.onPause,
    this.dropdown = false,
  });

  final bool dropdown;

  final String siteUrl;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    return ListenableBuilder(
      listenable: controller.doNotDisturb,
      builder: (context, _) {
        final lease = controller.lifecycle.capture(siteUrl);
        final state = controller.doNotDisturb.stateFor(siteUrl);
        final active = state.isActiveAt(DateTime.now());
        final until = state.until;
        final detail = active && until != null && !state.isEternal
            ? doNotDisturbRemainingLabel(until)
            : null;
        final localizations = MaterialLocalizations.of(context);
        final value = state.saving
            ? context.l10n.savingUsermenu
            : active
            ? state.isEternal
                  ? context.l10n.onNoExpiration
                  : context.l10n.onUntil(
                      (localizations.formatMediumDate(
                        until!.toLocal(),
                      )).toString(),
                      (clockTimeLabel(context, until.toLocal())).toString(),
                    )
            : context.l10n.off;
        final toastController = DToast.maybeOf(context);

        Future<void> resume() async {
          final error = await controller.doNotDisturb.resume(siteUrl);
          if (lease.isCurrent &&
              error != null &&
              toastController?.isDisposed == false) {
            toastController!.add(
              DToastOptions(description: error, type: DToastType.error),
            );
          }
        }

        final VoidCallback? action = state.saving
            ? null
            : () {
                if (!context.mounted || !lease.isCurrent) return;
                if (active) {
                  unawaited(resume());
                } else {
                  onPause();
                }
              };

        if (dropdown) {
          return DDropdownMenuCheckboxItem(
            key: const ValueKey('pause-notifications-row'),
            checked: active,
            indicatorSize: 11,
            leadingGap: 9,
            semanticLabel: context.l10n.pauseNotifications,
            semanticValue: value,
            onChanged: action == null ? null : (_) => action(),
            leading: DIcon(
              active ? DIcons.toggleOn : DIcons.toggleOff,
              size: 13,
              color: active
                  ? DTokens.of(context).foreground
                  : DTokens.of(context).mutedForeground,
            ),
            child: Text(context.l10n.pauseNotifications),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: MergeSemantics(
            child: Semantics(
              value: value,
              child: DToggle(
                key: const ValueKey('pause-notifications-row'),
                pressed: active,
                enabled: action != null,
                onPressedChanged: action == null ? null : (_) => action(),
                semanticLabel: context.l10n.pauseNotifications,
                visualStyle: const DToggleVisualStyle(expandArtwork: true),
                icon: state.saving
                    ? const DSpinner()
                    : DIcon(active ? DIcons.toggleOn : DIcons.toggleOff),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.pauseNotifications,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (detail != null)
                      DText(detail, variant: DTextVariant.muted),
                  ],
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
        border: Border(bottom: BorderSide(color: _userMenuBorderColor(theme))),
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

typedef _HidePresenceSnapshot = ({
  bool? hidden,
  bool saving,
  String? error,
  Object session,
});

class _HidePresenceTile extends StatelessWidget {
  const _HidePresenceTile({required this.siteUrl, this.dropdown = false});

  final bool dropdown;

  static const semanticsKey = ValueKey('user-menu-hide-presence');

  final String siteUrl;

  @override
  Widget build(BuildContext context) => ShellSelector<_HidePresenceSnapshot>(
    select: (controller) => (
      hidden: controller.hidePresenceFor(siteUrl),
      saving: controller.hidePresenceWriteInFlight(siteUrl),
      error: controller.hidePresenceErrorFor(siteUrl),
      // Equal settings can belong to a replacement account.
      session: controller.lifecycle.capture(siteUrl).session,
    ),
    builder: (context, state, _) {
      final controller = ShellScope.read(context);
      final lease = controller.lifecycle.capture(siteUrl);
      final theme = Theme.of(context);
      final hidden = state.hidden;
      final loading = hidden == null && state.error == null;
      final title = switch ((hidden, state.error)) {
        (true, _) => context.l10n.offline,
        (false, _) => context.l10n.online,
        (null, null) => context.l10n.loadingPresence,
        (null, _) => context.l10n.presenceUnavailable,
      };
      final VoidCallback? onTap = state.saving || loading
          ? null
          : () {
              if (!context.mounted || !lease.isCurrent) return;
              if (hidden == null) {
                unawaited(controller.retryHidePresence(siteUrl));
              } else {
                unawaited(controller.toggleHidePresence(siteUrl));
              }
            };
      final semanticsLabel = hidden == null ? context.l10n.presence : title;
      final semanticsValue = state.saving
          ? context.l10n.savingUsermenu
          : loading
          ? context.l10n.loadingDbutton
          : null;
      final semanticsHint = hidden == null && state.error != null
          ? context.l10n.retryLoadingThePresenceSetting
          : context.l10n.togglePresenceFeatures;

      if (dropdown) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DDropdownMenuCheckboxItem(
              key: semanticsKey,
              checked: hidden == false,
              indicatorSize: 11,
              leadingGap: 9,
              onChanged: onTap == null ? null : (_) => onTap(),
              semanticLabel: [semanticsLabel, ?semanticsValue].join(', '),
              leading: DIcon(
                hidden == false ? DIcons.toggleOn : DIcons.toggleOff,
                size: 13,
                color: hidden == false
                    ? DTokens.of(context).success
                    : DTokens.of(context).mutedForeground,
              ),
              child: Text(hidden == null ? title : context.l10n.online),
            ),
            if (state.error != null)
              DDropdownMenuLabel(child: Text(state.error!)),
          ],
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MergeSemantics(
              child: Semantics(
                value: semanticsValue,
                liveRegion: state.saving || loading,
                child: DTooltip(
                  message: context.l10n.togglePresenceFeatures,
                  excludeFromSemantics: true,
                  child: DToggle(
                    key: semanticsKey,
                    pressed: hidden == false,
                    enabled: onTap != null,
                    onPressedChanged: onTap == null ? null : (_) => onTap(),
                    semanticLabel: semanticsLabel,
                    semanticHint: semanticsHint,
                    visualStyle: const DToggleVisualStyle(expandArtwork: true),
                    icon: DIcon(
                      loading
                          ? DIcons.farClock
                          : hidden == false
                          ? DIcons.toggleOn
                          : DIcons.toggleOff,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hidden == null && !loading)
                          DText(
                            context.l10n.retry,
                            variant: DTextVariant.muted,
                          ),
                      ],
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
  const _RowTile({
    required this.row,
    this.detail,
    this.onTap,
    this.leading,
    this.destructive = false,
  });

  final UserMenuRow row;
  final String? detail;
  final VoidCallback? onTap;
  final Widget? leading;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rowKey = ValueKey('user-menu-row-${row.id ?? row.title}');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: DButton(
        key: rowKey,
        onPressed: onTap,
        variant: DButtonVariant.ghost,
        alignment: AlignmentDirectional.centerStart,
        foregroundColor: destructive
            ? theme.colorScheme.error
            : DTokens.of(context).foreground,
        semanticLabel: [row.title, ?detail].join(', '),
        icon: leading ?? DIcon(row.icon),
        label: Row(
          spacing: DSpacing.controlGap,
          children: [
            Expanded(
              child: Text(
                row.title,
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (detail case final detail?) Text(detail),
          ],
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
    final colors = Theme.of(context).discourse;
    return DBadge(
      size: DBadgeSize.compact,
      backgroundColor: colors.notificationIndicator,
      foregroundColor: colors.notificationForeground,
      semanticLabel: context.l10n.unreadUsermenuValue((count).toString()),
      child: Text(count > 99 ? '99+' : '$count'),
    );
  }
}

class UserMenuAvatar extends StatelessWidget {
  const UserMenuAvatar({
    super.key,
    required this.avatarUrl,
    required this.initial,
    required this.connecting,
  });

  final String? avatarUrl;

  final String? initial;

  final bool connecting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (connecting) {
      return const DAvatar(
        border: false,
        child: Padding(padding: EdgeInsets.all(4), child: DSpinner()),
      );
    }

    final fallback = DAvatarFallback(
      backgroundColor: initial == null
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.primary,
      foregroundColor: initial == null
          ? theme.colorScheme.onSurfaceVariant
          : theme.colorScheme.onPrimary,
      child: initial == null
          ? const DIcon(DIcons.user, size: 18)
          : Text(initial!, style: const TextStyle(fontWeight: FontWeight.w700)),
    );

    return DAvatar(
      border: false,
      child: AvatarImage(
        url: avatarUrl,
        size: DAvatarSize.standard.dimension,
        fallback: fallback,
      ),
    );
  }
}

class _OwnCardMenuEntry extends StatelessWidget {
  const _OwnCardMenuEntry({
    required this.siteUrl,
    required this.onDismiss,
    this.dropdown = false,
  });
  final String siteUrl;
  final VoidCallback onDismiss;
  final bool dropdown;
  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    final user = shell.currentUserFor(siteUrl);
    if (user == null) return const SizedBox.shrink();
    final lease = shell.lifecycle.capture(siteUrl);
    Future<void> open() async {
      if (!lease.isCurrent) return;
      final navigator = Navigator.of(context);
      onDismiss();
      await WidgetsBinding.instance.endOfFrame;
      if (!navigator.mounted ||
          !lease.isCurrent ||
          shell.accountSessionDisposed) {
        return;
      }
      await showUserCard(
        context: navigator.context,
        username: user.username,
        siteUrl: siteUrl,
      );
    }

    final avatar = UserMenuAvatar(
      avatarUrl: user.avatarUrl,
      initial: user.username.characters.firstOrNull?.toUpperCase(),
      connecting: false,
    );
    if (dropdown) {
      return DDropdownMenuItem(
        key: const ValueKey('user-menu-own-card'),
        leading: avatar,
        leadingGap: 10,
        padding: const EdgeInsets.all(8),
        semanticLabel: '${user.displayName}, @${user.username}',
        onPressed: () => unawaited(open()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user.displayName,
              style: TextStyle(
                fontSize: DiscourseTypography.compact,
                fontWeight: FontWeight.w600,
                color: DTokens.of(context).foreground,
              ),
            ),
            Text(
              '@${user.username}',
              style: TextStyle(
                fontSize: DiscourseTypography.xs,
                color: DTokens.of(context).mutedForeground,
              ),
            ),
          ],
        ),
      );
    }
    return DItem(
      key: const ValueKey('user-menu-own-card'),
      onPressed: () => unawaited(open()),
      children: [
        DItemMedia(child: avatar),
        DItemContent(
          children: [
            DItemTitle(child: Text(user.name ?? user.username)),
            DItemDescription(child: Text('@${user.username}')),
          ],
        ),
      ],
    );
  }
}
