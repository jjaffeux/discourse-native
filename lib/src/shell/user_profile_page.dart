import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/icons/d_icons.dart';
import '../models/discourse_instance.dart';
import '../models/user_profile.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/discourse_typography.dart';
import 'content_reading_lane.dart';
import 'cooked_html.dart';
import 'external_link.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'skeleton_fill.dart';
import 'user_activity.dart';
import 'user_card_details.dart';
import 'user_card_header.dart';
import 'user_profile_controller.dart';
import 'user_summary.dart';

/// One person's profile: who they are, then their summary or their activity.
class UserProfilePage extends StatelessWidget {
  const UserProfilePage({
    super.key,
    required this.siteUrl,
    required this.username,
    required this.title,
  });

  final String siteUrl;
  final String username;
  final String title;

  // A profile answers the account that asked, so each account session mounts
  // its own view and reads its own copy.
  @override
  Widget build(BuildContext context) =>
      ShellSelector<({ShellController controller, Object session})>(
        select: (controller) => (
          controller: controller,
          session: controller.lifecycle.capture(siteUrl).session,
        ),
        builder: (context, owner, _) => _ProfileView(
          key: ValueKey(owner),
          controller: owner.controller,
          siteUrl: siteUrl,
          username: username,
          title: title,
        ),
      );
}

enum _ProfileSection { summary, activity }

class _ProfileView extends StatefulWidget {
  const _ProfileView({
    super.key,
    required this.controller,
    required this.siteUrl,
    required this.username,
    required this.title,
  });

  final ShellController controller;
  final String siteUrl;
  final String username;
  final String title;

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  _ProfileSection _section = _ProfileSection.summary;
  bool _restored = false;
  bool _requestScheduled = false;

  Object get _storageId =>
      ('user-profile-section', widget.siteUrl, widget.username.toLowerCase());

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored) return;
    _restored = true;
    _section =
        PageStorage.maybeOf(context)?.readState(context, identifier: _storageId)
            as _ProfileSection? ??
        _ProfileSection.summary;
  }

  DiscourseInstance? get _instance => widget.controller.instances
      .where((instance) => instance.url == widget.siteUrl)
      .firstOrNull;

  Future<void> _load({bool refresh = false}) async {
    final instance = _instance;
    if (instance == null) return;
    await widget.controller.userProfile.load(
      instance,
      widget.username,
      refresh: refresh,
    );
  }

  // A retired account session drops its profiles while this view can still
  // be mounted, and a load cannot start during the build that notices.
  void _scheduleRequest() {
    if (_requestScheduled) return;
    _requestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestScheduled = false;
      if (mounted) unawaited(_load());
    });
  }

  void _select(_ProfileSection? value) {
    if (value == null || value == _section) return;
    setState(() => _section = value);
    PageStorage.maybeOf(
      context,
    )?.writeState(context, value, identifier: _storageId);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller.userProfile,
    builder: (context, _) {
      final state = widget.controller.userProfile.stateFor(
        widget.siteUrl,
        widget.username,
      );
      if (state == null) _scheduleRequest();
      return switch (state) {
        null || UserProfileLoading() => _framed(const _ProfileSkeleton()),
        UserProfileLoaded(:final profile) => _loaded(profile),
        UserProfileHidden(:final profile) => _scrolling(
          profile,
          below: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: DAlert(
                icon: const DIcon(DIcons.lock),
                liveRegion: false,
                description: DAlertDescription(
                  child: Text(context.l10n.userProfileHidden),
                ),
              ),
            ),
          ],
        ),
        UserProfileMissing() => _framed(
          _ProfileMessage(
            icon: DIcons.user,
            title: context.l10n.userProfileMissing,
          ),
        ),
        UserProfileForbidden() => _framed(
          _ProfileMessage(
            icon: DIcons.lock,
            title: context.l10n.couldnTSeeThatProfile,
          ),
        ),
        UserProfileFailed(:final message) => _framed(
          _ProfileMessage(
            icon: DIcons.triangleExclamation,
            title: message,
            actionLabel: context.l10n.tryAgain,
            onAction: () => _load(refresh: true),
          ),
        ),
      };
    },
  );

  Widget _framed(Widget child) =>
      DPageSurface.headed(title: Text(widget.title), child: child);

  Widget _loaded(UserProfile profile) {
    // The site's spelling of the name, which the summary and activity
    // owners key by; a payload without one leaves the route's.
    final username = profile.card.username.isEmpty
        ? widget.username
        : profile.card.username;
    return DTabs<_ProfileSection>.controlled(
      value: _section,
      onChanged: _select,
      children: [
        Expanded(
          child: _scrolling(
            profile,
            below: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DTabList<_ProfileSection>(
                    children: [
                      DTabTrigger(
                        value: _ProfileSection.summary,
                        child: Text(context.l10n.summary),
                      ),
                      DTabTrigger(
                        value: _ProfileSection.activity,
                        child: Text(context.l10n.activity),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            section: switch (_section) {
              _ProfileSection.summary => SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: UserSummaryPanel(
                    siteUrl: widget.siteUrl,
                    username: username,
                  ),
                ),
              ),
              _ProfileSection.activity => SliverPadding(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                sliver: UserActivityView(
                  siteUrl: widget.siteUrl,
                  username: username,
                  embedded: true,
                ),
              ),
            },
          ),
        ),
      ],
    );
  }

  Widget _scrolling(
    UserProfile profile, {
    required List<Widget> below,
    Widget? section,
  }) => DPageSurface.headed(
    title: Text(widget.title),
    bodyBuilder: (context, header) => ContentReadingLane(
      builder: (context, lane) => DPageScrollInsets(
        builder: (context, insets) => CustomScrollView(
          key: PageStorageKey((
            'user-profile-scroll',
            widget.siteUrl,
            widget.username.toLowerCase(),
          )),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: lane.padding.add(insets),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProfileHeader(
                          profile: profile,
                          siteUrl: widget.siteUrl,
                        ),
                        ...below,
                      ],
                    ),
                  ),
                  ?section,
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.siteUrl});

  final UserProfile profile;
  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final card = profile.card;
    final bio = profile.bioCooked ?? card.bioExcerpt;
    final metadata = PluginScope.of(
      context,
    ).registry.userProfileMetadata(context, siteUrl, card);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UserCardHeader(card: card, siteUrl: siteUrl),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (bio != null)
                CookedHtml(
                  html: bio,
                  siteUrl: siteUrl,
                  textStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    height: DiscourseTypography.lineHeightCooked,
                  ),
                ),
              if (card.website != null || card.location != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    if (card.website case final website?)
                      UserCardDetail(
                        icon: const DIcon(DIcons.globe, size: 16),
                        label:
                            card.websiteName ?? userCardWebsiteLabel(website),
                        onTap: () => unawaited(openExternalLink(website)),
                      ),
                    if (card.location case final location?)
                      UserCardDetail(
                        icon: const DIcon(DIcons.locationDot, size: 16),
                        label: location,
                      ),
                  ],
                ),
              ],
              if (card.createdAt != null ||
                  profile.lastSeenAt != null ||
                  card.lastPostedAt != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (card.createdAt case final joined?)
                      UserCardMetadata(
                        label: context.l10n.joined,
                        value: userCardMonth(joined),
                      ),
                    if (profile.lastSeenAt case final seen?)
                      RelativeTimeBuilder(
                        when: seen,
                        builder: (context, label) => UserCardMetadata(
                          label: context.l10n.lastSeen,
                          value: label,
                        ),
                      ),
                    if (card.lastPostedAt case final posted?)
                      RelativeTimeBuilder(
                        when: posted,
                        builder: (context, label) => UserCardMetadata(
                          label: context.l10n.lastPost,
                          value: label,
                        ),
                      ),
                  ],
                ),
              ],
              if (metadata.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 12, runSpacing: 6, children: metadata),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) => ContentReadingLane(
    builder: (context, lane) => SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: lane.padding.add(const EdgeInsets.all(16)),
      child: DSkeletonRegion(
        semanticsLabel: context.l10n.loadingProfile,
        color: skeletonFill(context),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DSkeleton.circle(diameter: UserCardHeader.avatarSize),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      DSkeleton(width: 160, height: 16),
                      DSkeleton(width: 104, height: 14),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            DSkeleton(height: 14),
            SizedBox(height: 8),
            FractionallySizedBox(
              widthFactor: 0.75,
              child: DSkeleton(height: 14),
            ),
            SizedBox(height: 24),
            DSkeleton(height: 76),
            SizedBox(height: 16),
            DSkeleton(height: 240),
          ],
        ),
      ),
    ),
  );
}

class _ProfileMessage extends StatelessWidget {
  const _ProfileMessage({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final DIconData icon;
  final String title;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Center(
            child: DEmpty(
              children: [
                DEmptyHeader(
                  children: [
                    DEmptyMedia(
                      variant: DEmptyMediaVariant.icon,
                      child: DIcon(icon),
                    ),
                    DEmptyTitle(title),
                  ],
                ),
                if (actionLabel case final label?)
                  DEmptyContent(
                    children: [
                      DButton(
                        label: Text(label),
                        onPressed: onAction == null
                            ? null
                            : () => unawaited(onAction!()),
                        variant: DButtonVariant.primary,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
