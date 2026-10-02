import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../models/forum_about.dart';
import '../theme/d_icons.dart';
import 'skeleton_fill.dart';

class ForumAboutPage extends StatefulWidget {
  const ForumAboutPage({
    super.key,
    required this.load,
    required this.onOpenFullPage,
    this.voiceEnabled = false,
    this.loginRequired = false,
    this.requestIdentity,
  });

  final Future<ForumAbout> Function() load;
  final VoidCallback onOpenFullPage;
  final bool voiceEnabled;
  final bool loginRequired;
  final Object? requestIdentity;

  @override
  State<ForumAboutPage> createState() => ForumAboutPageState();
}

class ForumAboutPageState extends State<ForumAboutPage> {
  ForumAbout? _about;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ForumAboutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestIdentity != widget.requestIdentity ||
        oldWidget.loginRequired != widget.loginRequired) {
      _request++;
      _about = null;
      _failed = false;
      unawaited(_load());
    }
  }

  Future<void> refresh() => _load();

  Future<void> _load() async {
    if (widget.loginRequired) return;
    final request = ++_request;
    setState(() {
      _about = null;
      _failed = false;
    });
    try {
      final about = await widget.load();
      if (!mounted || request != _request) return;
      setState(() => _about = about);
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DPageSurface(
      framed: false,
      limitContentSize: true,
      header: Padding(
        padding: const EdgeInsets.symmetric(vertical: DSpacing.lg),
        child: DCardHeader(
          title: DCardTitle(child: Text(l10n.forumAboutTitle)),
          action: widget.loginRequired
              ? null
              : DCardAction(
                  child: DButton.iconOnly(
                    tooltip: l10n.refresh,
                    icon: const DIcon(DIcons.arrowsRotate),
                    onPressed: () => unawaited(_load()),
                  ),
                ),
        ),
      ),
      footer: DCardFooter(
        child: DButton(
          key: const ValueKey('forum-about-browser'),
          variant: DButtonVariant.outline,
          onPressed: widget.onOpenFullPage,
          label: Text(l10n.forumAboutOpenFullPage),
        ),
      ),
      child: widget.loginRequired || _failed
          ? DScrollArea(
              child: DEmpty(
                children: [
                  DEmptyHeader(
                    children: [
                      DEmptyTitle(
                        widget.loginRequired
                            ? l10n.forumAboutLoginRequired
                            : l10n.forumAboutLoadFailed,
                      ),
                    ],
                  ),
                  if (!widget.loginRequired)
                    DEmptyContent(
                      children: [
                        DButton(
                          onPressed: () => unawaited(_load()),
                          label: Text(l10n.retry),
                        ),
                      ],
                    ),
                ],
              ),
            )
          : _about == null
          ? const _AboutSkeleton()
          : DScrollArea(
              key: const ValueKey('forum-about-content'),
              padding: const EdgeInsets.all(DSpacing.lg),
              child: DPageReadingLaneBox(
                limitContentSize: true,
                widthLimit: DPageReadingLane.maxWidth - 32,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final identity = _identity(context, _about!);
                    final activity = _activity(context, _about!);
                    final wide =
                        constraints.maxWidth /
                            MediaQuery.textScalerOf(context).scale(1) >=
                        680;
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: identity),
                          if (activity != null) ...[
                            const SizedBox(width: DSpacing.lg),
                            Expanded(child: activity),
                          ],
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        identity,
                        if (activity != null) ...[
                          const SizedBox(height: DSpacing.lg),
                          activity,
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
    );
  }

  Widget _identity(BuildContext context, ForumAbout about) {
    final l10n = context.l10n;
    final members = about.members;
    return DCard(
      children: [
        DCardHeader(
          title: DCardTitle(child: Text(about.title)),
          description: about.description == null
              ? null
              : DCardDescription(child: Text(about.description!)),
        ),
        if (members != null ||
            about.creationDate != null ||
            about.extendedDescription != null)
          DCardContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DSpacing.lg,
              children: [
                if (members != null)
                  Text(
                    l10n.forumAboutMembers(members, _number(context, members)),
                  ),
                if (about.creationDate case final date?)
                  Text(
                    l10n.forumAboutCreated(
                      DateFormat.yMMMd(l10n.localeName).format(date),
                    ),
                  ),
                if (about.extendedDescription case final description?)
                  Text(description),
              ],
            ),
          ),
      ],
    );
  }

  Widget? _activity(BuildContext context, ForumAbout about) {
    final l10n = context.l10n;
    final rows = <Widget>[];
    void add(
      int? count,
      DIconData icon,
      String Function(int, String) label,
      String period,
    ) {
      if (count == null) return;
      rows.add(
        DItem(
          children: [
            DItemMedia(variant: DItemMediaVariant.icon, child: DIcon(icon)),
            DItemContent(
              children: [
                DItemTitle(child: Text(label(count, _number(context, count)))),
                DItemDescription(child: Text(period)),
              ],
            ),
          ],
        ),
      );
    }

    add(
      about.stats['topics_7_days'],
      DIcons.comments,
      l10n.forumAboutTopics,
      l10n.forumAboutLastSevenDays,
    );
    add(
      about.stats['posts_last_day'],
      DIcons.pencil,
      l10n.forumAboutPosts,
      l10n.todayDcalendarevents,
    );
    add(
      about.stats['active_users_7_days'],
      DIcons.users,
      l10n.forumAboutActiveUsers,
      l10n.forumAboutLastSevenDays,
    );
    add(
      about.stats['users_7_days'],
      DIcons.userPlus,
      l10n.forumAboutSignUps,
      l10n.forumAboutLastSevenDays,
    );
    add(
      about.stats['likes_count'] ?? about.stats['like_count'],
      DIcons.heart,
      l10n.forumAboutLikes,
      l10n.allTime,
    );
    add(
      about.voiceParticipants(voiceEnabled: widget.voiceEnabled),
      DIcons.microphoneLines,
      l10n.forumAboutVoiceParticipants,
      l10n.forumAboutLastSevenDays,
    );
    if (rows.isEmpty) return null;
    return DCard(
      children: [
        DCardHeader(title: DCardTitle(child: Text(l10n.forumAboutActivity))),
        DCardContent(child: DItemGroup(children: rows)),
      ],
    );
  }

  String _number(BuildContext context, int count) =>
      NumberFormat.decimalPattern(context.l10n.localeName).format(count);
}

class _AboutSkeleton extends StatelessWidget {
  const _AboutSkeleton();

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    semanticsLabel: context.l10n.forumAboutLoading,
    color: skeletonFill(context),
    expand: true,
    child: LayoutBuilder(
      builder: (context, constraints) => DScrollArea(
        padding: const EdgeInsets.all(DSpacing.lg),
        child: DPageReadingLaneBox(
          limitContentSize: true,
          widthLimit: DPageReadingLane.maxWidth - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FractionallySizedBox(
                widthFactor: .7,
                child: DSkeleton(height: 24),
              ),
              const SizedBox(height: DSpacing.lg),
              const DSkeleton(height: 14),
              const SizedBox(height: DSpacing.sm),
              const FractionallySizedBox(
                widthFactor: .85,
                child: DSkeleton(height: 14),
              ),
              const SizedBox(height: DSpacing.xl),
              for (
                var i = 0;
                i < math.max(6, (constraints.maxHeight / 72).ceil());
                i++
              )
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: DSpacing.md),
                  child: Row(
                    children: [
                      DSkeleton.circle(diameter: 32),
                      SizedBox(width: DSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FractionallySizedBox(
                              widthFactor: .6,
                              child: DSkeleton(height: 16),
                            ),
                            SizedBox(height: DSpacing.sm),
                            FractionallySizedBox(
                              widthFactor: .35,
                              child: DSkeleton(height: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
