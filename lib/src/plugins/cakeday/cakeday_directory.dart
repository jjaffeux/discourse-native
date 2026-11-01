import 'dart:async';
import 'dart:math' as math;
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'cakeday_controller.dart';
import 'cakeday_data.dart';
import 'cakeday_navigation.dart';

class CakedayDirectory extends StatefulWidget {
  const CakedayDirectory({
    super.key,
    required this.site,
    required this.query,
    required this.controller,
    required this.navigation,
  });
  final String site;
  final CakedayQuery query;
  final CakedayController controller;
  final CakedayNavigation navigation;
  @override
  State<CakedayDirectory> createState() => _CakedayDirectoryState();
}

class _CakedayDirectoryState extends State<CakedayDirectory> {
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.controller.retain(widget.site, widget.query);
    _scroll.addListener(_scrollChanged);
  }

  @override
  void didUpdateWidget(CakedayDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.site != widget.site ||
        oldWidget.query != widget.query) {
      oldWidget.controller.removeListener(_changed);
      oldWidget.controller.release(oldWidget.site, oldWidget.query);
      widget.controller.addListener(_changed);
      widget.controller.retain(widget.site, widget.query);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _scrollChanged() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 300) {
      final state = widget.controller.state(widget.site, widget.query);
      if (state.failure == null) {
        unawaited(
          widget.controller.load(widget.site, widget.query, more: true),
        );
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.controller.release(widget.site, widget.query);
    _scroll.dispose();
    super.dispose();
  }

  String _kind(CakedayKind kind) => kind == CakedayKind.birthdays
      ? context.l10n.cakedayBirthdays
      : context.l10n.cakedayAnniversaries;
  String _period(CakedayPeriod period) => switch (period) {
    CakedayPeriod.today => context.l10n.todayDcalendarevents,
    CakedayPeriod.tomorrow => context.l10n.tomorrow,
    CakedayPeriod.upcoming => context.l10n.cakedayUpcoming,
    CakedayPeriod.month => context.l10n.all,
  };
  String _empty() {
    final l = context.l10n;
    return switch ((widget.query.kind, widget.query.period)) {
      (CakedayKind.birthdays, CakedayPeriod.today) =>
        l.cakedayBirthdaysTodayEmpty,
      (CakedayKind.birthdays, CakedayPeriod.tomorrow) =>
        l.cakedayBirthdaysTomorrowEmpty,
      (CakedayKind.birthdays, CakedayPeriod.upcoming) =>
        l.cakedayBirthdaysUpcomingEmpty,
      (CakedayKind.birthdays, CakedayPeriod.month) =>
        l.cakedayBirthdaysMonthEmpty,
      (CakedayKind.anniversaries, CakedayPeriod.today) =>
        l.cakedayAnniversariesTodayEmpty,
      (CakedayKind.anniversaries, CakedayPeriod.tomorrow) =>
        l.cakedayAnniversariesTomorrowEmpty,
      (CakedayKind.anniversaries, CakedayPeriod.upcoming) =>
        l.cakedayAnniversariesUpcomingEmpty,
      (CakedayKind.anniversaries, CakedayPeriod.month) =>
        l.cakedayAnniversariesMonthEmpty,
    };
  }

  String _range() {
    final today = widget.controller.viewerToday(widget.site),
        format = DateFormat.MMMMd();
    return switch (widget.query.period) {
      CakedayPeriod.today => format.format(today),
      CakedayPeriod.tomorrow => format.format(
        today.add(const Duration(days: 1)),
      ),
      CakedayPeriod.upcoming => context.l10n.cakedayRange(
        format.format(today.add(const Duration(days: 2))),
        format.format(today.add(const Duration(days: 9))),
      ),
      CakedayPeriod.month => DateFormat.MMMM().format(
        DateTime(2000, widget.query.month),
      ),
    };
  }

  void _select(CakedayKind kind, CakedayPeriod period, {int? month}) =>
      widget.navigation.open(
        CakedayQuery(
          kind,
          period,
          month:
              month ??
              (widget.query.period == CakedayPeriod.month
                  ? widget.query.month
                  : widget.controller.viewerToday(widget.site).month),
        ),
        replace: true,
      );
  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state(widget.site, widget.query),
        l10n = context.l10n;
    final available = widget.controller.enabled(widget.site, widget.query.kind);
    return DPageSurface.headed(
      identity: (widget.site, widget.query),
      title: Text(_kind(widget.query.kind)),
      icon: DIcons.cakeCandles,
      controls: available
          ? DReferenceTextScale(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DToggleGroup<CakedayKind>(
                    semanticLabel: l10n.cakedayBirthday,
                    values: [widget.query.kind],
                    allowEmptySelection: false,
                    wrap: true,
                    items: [
                      for (final kind in CakedayKind.values)
                        if (widget.controller.enabled(widget.site, kind))
                          DToggleGroupItem(
                            value: kind,
                            child: Text(_kind(kind)),
                          ),
                    ],
                    onChanged: (values) =>
                        _select(values.single, widget.query.period),
                  ),
                  const SizedBox(height: 8),
                  DToggleGroup<CakedayPeriod>(
                    values: [widget.query.period],
                    allowEmptySelection: false,
                    wrap: true,
                    items: [
                      for (final period in CakedayPeriod.values)
                        DToggleGroupItem(
                          value: period,
                          child: Text(_period(period)),
                        ),
                    ],
                    onChanged: (values) =>
                        _select(widget.query.kind, values.single),
                  ),
                  if (widget.query.period == CakedayPeriod.month)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: DSelect<int>.controlled(
                        value: widget.query.month,
                        semanticLabel: l10n.month,
                        entries: [
                          for (var m = 1; m <= 12; m++)
                            DSelectOption(
                              value: m,
                              label: DateFormat.MMMM().format(
                                DateTime(2000, m),
                              ),
                              child: Text(
                                DateFormat.MMMM().format(DateTime(2000, m)),
                              ),
                            ),
                        ],
                        onChanged: (m) {
                          if (m != null) {
                            _select(
                              widget.query.kind,
                              CakedayPeriod.month,
                              month: m,
                            );
                          }
                        },
                      ),
                    ),
                ],
              ),
            )
          : null,
      bodyBuilder: (context, header) => DPullToRefresh(
        onRefresh: available
            ? () => widget.controller.load(
                widget.site,
                widget.query,
                refresh: true,
              )
            : null,
        child: ContentReadingLane(
          builder: (context, lane) => CustomScrollView(
            controller: _scroll,
            key: PageStorageKey((widget.site, widget.query.id)),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: header.spacer),
              SliverPadding(
                padding: lane.padding.add(
                  EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    24 + DScrollChrome.bottomInsetOf(context),
                  ),
                ),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    if (!available)
                      SliverToBoxAdapter(
                        child: DEmpty(
                          children: [
                            DEmptyHeader(
                              children: [DEmptyTitle(l10n.cakedayUnavailable)],
                            ),
                          ],
                        ),
                      )
                    else ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: DText(_range(), variant: DTextVariant.muted),
                        ),
                      ),
                      if (!state.loaded && state.loading)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Center(
                              child: DSpinner(semanticLabel: l10n.loading),
                            ),
                          ),
                        )
                      else if (!state.loaded && state.failure != null)
                        SliverToBoxAdapter(child: _error())
                      else if (state.loaded && state.members.isEmpty)
                        SliverToBoxAdapter(
                          child: DEmpty(
                            children: [
                              DEmptyHeader(
                                children: [
                                  const DEmptyMedia(
                                    child: DIcon(DIcons.cakeCandles, size: 28),
                                  ),
                                  DEmptyTitle(_empty()),
                                ],
                              ),
                            ],
                          ),
                        )
                      else
                        SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.crossAxisExtent > 650
                                ? 2
                                : 1;
                            final rows = (state.members.length / columns)
                                .ceil();
                            return SliverList.builder(
                              itemCount: rows,
                              itemBuilder: (context, index) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (
                                      var column = 0;
                                      column < columns;
                                      column++
                                    ) ...[
                                      if (column > 0) const SizedBox(width: 16),
                                      Expanded(
                                        child:
                                            index * columns + column <
                                                state.members.length
                                            ? _member(
                                                state.members[index * columns +
                                                    column],
                                              )
                                            : const SizedBox.shrink(),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      if (state.loaded && state.failure != null)
                        SliverToBoxAdapter(
                          child: _error(more: (state.failedPage ?? 0) > 0),
                        ),
                      if (state.loadingMore)
                        SliverToBoxAdapter(
                          child: Center(
                            child: DSpinner(semanticLabel: l10n.loading),
                          ),
                        ),
                      if (state.nextPage != null &&
                          !state.loadingMore &&
                          state.failure == null)
                        SliverToBoxAdapter(
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: DButton(
                              variant: DButtonVariant.ghost,
                              label: Text(l10n.cakedayLoadMore),
                              onPressed: () => unawaited(
                                widget.controller.load(
                                  widget.site,
                                  widget.query,
                                  more: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _error({bool more = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: DAlert(
      variant: DAlertVariant.destructive,
      description: DAlertDescription(
        child: Text(context.l10n.cakedayDirectoryError),
      ),
      action: DAlertAction(
        child: DButton(
          variant: DButtonVariant.link,
          label: Text(context.l10n.retry),
          onPressed: () => unawaited(
            widget.controller.load(
              widget.site,
              widget.query,
              refresh: !more,
              more: more,
            ),
          ),
        ),
      ),
    ),
  );
  Widget _member(CakedayMember member) {
    final config = widget.controller.siteState.siteConfigFor(widget.site);
    final fullName = member.name?.trim();
    final name =
        !config.prioritizeUsernameInUx && (fullName?.isNotEmpty ?? false)
        ? fullName!
        : member.username;
    final secondary = name == member.username ? fullName : member.username;
    final date = member.birthday != null
        ? DateFormat.MMMMd().format(member.birthday!.date)
        : DateFormat.yMMMMd().format(member.joined!.date);
    return DItem(
      variant: DItemVariant.outline,
      shape: DItemShape.card,
      children: [
        DItemMedia(
          variant: DItemMediaVariant.avatar,
          child: UserCardTarget.avatar(
            username: member.username,
            siteUrl: widget.site,
            child: DAvatar.frame(
              child: AvatarImage(
                url: resolveAvatarUrl(
                  member.avatarTemplate,
                  widget.site,
                  size: 80,
                ),
                size: 40,
                fallback: DAvatar(
                  fallback: DAvatarFallback(
                    child: Text(
                      member.username
                          .substring(0, math.min(2, member.username.length))
                          .toUpperCase(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        DItemContent(
          children: [
            UserCardTarget(
              username: member.username,
              siteUrl: widget.site,
              child: DItemTitle(maxLines: null, child: Text(name)),
            ),
            if (secondary?.isNotEmpty ?? false)
              DItemDescription(child: Text(secondary!)),
            if (member.title?.isNotEmpty ?? false)
              DItemDescription(child: Text(member.title!)),
            DItemDescription(child: Text(date)),
          ],
        ),
      ],
    );
  }
}
