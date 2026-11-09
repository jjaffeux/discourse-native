import 'dart:async';
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'gamification_controller.dart';
import 'gamification_labels.dart';
import 'gamification_models.dart';
import 'gamification_navigation.dart';
import 'gamification_route.dart';

class GamificationPage extends StatefulWidget {
  const GamificationPage({
    super.key,
    required this.site,
    required this.controller,
    required this.navigation,
    this.query = const GamificationQuery(),
  });
  final String site;
  final GamificationController controller;
  final GamificationNavigation navigation;
  final GamificationQuery query;
  @override
  State<GamificationPage> createState() => _GamificationPageState();
}

class _GamificationPageState extends State<GamificationPage> {
  late GamificationHandle handle;
  @override
  void initState() {
    super.initState();
    _acquire();
    widget.controller.addListener(_changed);
  }

  void _acquire() {
    handle = widget.controller.acquire(widget.site, widget.query);
    handle.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(GamificationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site != widget.site ||
        (oldWidget.query != widget.query && handle.query != widget.query) ||
        oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      handle.removeListener(_changed);
      handle.release();
      _acquire();
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    handle.removeListener(_changed);
    handle.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = handle.state;
    final ready = state is GamificationReady ? state : null;
    final board = ready?.snapshot.board;
    return DPageSurface.headed(
      title: Text(board?.name ?? context.l10n.gamificationTitle),
      controls: Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.sm,
        children: [
          if (board != null)
            DSelect<GamificationPeriod>.controlled(
              value: handle.query.period ?? board.defaultPeriod,
              enabled: !board.periodFilterDisabled,
              semanticLabel: context.l10n.gamificationDefaultPeriod,
              entries: [
                for (final period in GamificationPeriod.values)
                  DSelectOption(
                    value: period,
                    label: gamePeriodLabel(context, period),
                    child: Text(gamePeriodLabel(context, period)),
                  ),
              ],
              onChanged: (period) {
                if (period != null) {
                  unawaited(handle.selectPeriod(period));
                  widget.navigation.updatePeriod(widget.site, handle.query);
                }
              },
            ),
          DButton(
            label: Text(context.l10n.gamificationHelp),
            onPressed: () => showDDialog<void>(
              context: context,
              builder: (context, dialog) => DDialogContent(
                children: [
                  Text(context.l10n.gamificationHelp),
                  Text(context.l10n.gamificationHelpText),
                ],
              ),
            ),
          ),
          if (widget.controller.canManage(widget.site))
            DButton(
              label: Text(context.l10n.gamificationManage),
              onPressed: () =>
                  widget.navigation.open(const GamificationRoute(admin: true)),
            ),
        ],
      ),
      bodyBuilder: (context, header) => DPullToRefresh(
        onRefresh: ready?.refreshing == true || state is GamificationLoading
            ? null
            : handle.refresh,
        child: CustomScrollView(
          key: PageStorageKey((
            widget.site,
            widget.navigation.host.activeTabId,
            handle.query.target.id,
          )),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: header.spacer),
            SliverPadding(
              padding: const EdgeInsets.all(DSpacing.lg),
              sliver: SliverToBoxAdapter(
                child: GamificationResults(handle: handle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GamificationResults extends StatelessWidget {
  const GamificationResults({
    super.key,
    required this.handle,
    this.compact = false,
  });
  final GamificationHandle handle;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final state = handle.state;
    if (state is! GamificationReady) {
      if (state is GamificationLoading) return const Center(child: DSpinner());
      final message = switch (state) {
        GamificationPreparing(:final reason) => reason,
        GamificationUnavailable() => context.l10n.gamificationUnavailable,
        GamificationRestricted() => context.l10n.gamificationRestricted,
        GamificationUnsupported() => context.l10n.gamificationUnsupported,
        _ => context.l10n.gamificationFailed,
      };
      return DAlert(description: DAlertDescription(child: Text(message)));
    }
    final snapshot = state.snapshot;
    final board = snapshot.board;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.md,
      children: [
        if (state.error != null)
          DAlert(
            description: DAlertDescription(
              child: Text(context.l10n.gamificationStale),
            ),
          ),
        if (!compact) ...[
          if (board.fromDate != null || board.toDate != null)
            Wrap(
              spacing: DSpacing.md,
              children: [
                if (board.fromDate != null)
                  Text(
                    '${context.l10n.gamificationFromDate} ${gameDateLabel(context, board.fromDate!)}',
                  ),
                if (board.toDate != null)
                  Text(
                    '${context.l10n.gamificationToDate} ${gameDateLabel(context, board.toDate!)}',
                  ),
              ],
            ),
          switch (snapshot.personal) {
            AnonymousRank() => const SizedBox.shrink(),
            UnrankedMember() => DAlert(
              description: DAlertDescription(
                child: Text(context.l10n.gamificationUnranked),
              ),
            ),
            RankedMember(:final user) => DCard(
              size: DCardSize.small,
              variant: DCardVariant.well,
              children: [
                DCardContent(
                  child: Wrap(
                    spacing: DSpacing.xl,
                    runSpacing: DSpacing.md,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DText(
                        context.l10n.gamificationYourPosition,
                        variant: DTextVariant.muted,
                      ),
                      for (final (label, value) in [
                        (
                          context.l10n.gamificationRank,
                          gameNumber(context, user.position),
                        ),
                        (
                          context.l10n.gamificationCheers,
                          gameNumber(context, user.totalScore),
                        ),
                      ])
                        Semantics(
                          container: true,
                          label: '$label: $value',
                          excludeSemantics: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            spacing: DSpacing.xs,
                            children: [
                              DText(label, variant: DTextVariant.small),
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: DText(
                                  value,
                                  variant: DTextVariant.h3,
                                  headingLevel: 0,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          },
          if (snapshot.users.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    constraints.maxWidth >= 720 &&
                    MediaQuery.textScalerOf(context).scale(14) < 24;
                final width = wide
                    ? (constraints.maxWidth - 2 * DSpacing.md) / 3
                    : constraints.maxWidth;
                return Wrap(
                  spacing: DSpacing.md,
                  runSpacing: DSpacing.md,
                  children: [
                    for (final user in snapshot.users.take(3))
                      SizedBox(
                        width: width,
                        child: DCard(
                          size: DCardSize.small,
                          children: [
                            DCardContent(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: DSpacing.sm,
                                children: [
                                  Text(
                                    '${context.l10n.gamificationRank} ${gameNumber(context, user.position)}',
                                  ),
                                  _identity(context, user),
                                  Text(
                                    '${gameNumber(context, user.totalScore)} ${context.l10n.gamificationCheers}',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
        if (snapshot.users.isEmpty)
          DAlert(
            description: DAlertDescription(
              child: Text(context.l10n.gamificationEmpty),
            ),
          )
        else
          DTable(
            header: DTableHeader(
              rows: [
                DTableRow(
                  cells: [
                    DTableHead(child: Text(context.l10n.gamificationRank)),
                    DTableHead(child: Text(context.l10n.gamificationMember)),
                    DTableHead(child: Text(context.l10n.gamificationCheers)),
                  ],
                ),
              ],
            ),
            body: DTableBody(
              rows: [
                for (final user in snapshot.users)
                  DTableRow(
                    selected:
                        snapshot.personal is RankedMember &&
                        (snapshot.personal as RankedMember).user.id == user.id,
                    cells: [
                      DTableCell(
                        child: Text(gameNumber(context, user.position)),
                      ),
                      DTableCell(child: _identity(context, user)),
                      DTableCell(
                        child: Text(gameNumber(context, user.totalScore)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        if (!compact &&
            snapshot.users.isNotEmpty &&
            state.append != GamificationAppend.exhausted)
          DButton(
            label: Text(context.l10n.gamificationMore),
            onPressed:
                state.refreshing || state.append == GamificationAppend.loading
                ? null
                : () => unawaited(handle.loadNextPage()),
          ),
      ],
    );
  }

  Widget _identity(BuildContext context, GamificationRankedUser user) {
    final preferUsername = handle.owner.siteState
        .siteConfigFor(handle.site)
        .prioritizeUsernameInUx;
    final primary = preferUsername || user.name?.isNotEmpty != true
        ? user.username
        : user.name!;
    final secondary = preferUsername ? user.name : user.username;
    final url = resolveAvatarUrl(user.avatarTemplate, handle.site, size: 80);
    return UserCardTarget(
      username: user.username,
      siteUrl: handle.site,
      semanticLabel: context.l10n.gamificationMemberRank(
        primary,
        gameNumber(context, user.position),
        gameNumber(context, user.totalScore),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DAvatar(
            size: DAvatarSize.lg,
            decorative: true,
            fallback: DAvatarFallback(
              child: Text(
                user.username.isEmpty
                    ? '?'
                    : user.username.characters.first.toUpperCase(),
              ),
            ),
            child: url == null
                ? null
                : SiteImage(
                    siteUrl: handle.site,
                    url: url,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                  ),
          ),
          const SizedBox(width: DSpacing.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(primary),
                if (secondary?.isNotEmpty == true && secondary != primary)
                  Text(secondary!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
