import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'policies_api.dart';
import 'policy_data.dart';
import 'policy_definition.dart';

typedef PolicyActionCallback = Future<void> Function(PolicyAction action);
typedef PolicyParticipantsLoader =
    Future<PolicyUsersPage?> Function(PolicyParticipantList list, int offset);

class PolicyCard extends StatefulWidget {
  const PolicyCard({
    super.key,
    required this.body,
    required this.definition,
    required this.siteUrl,
    this.data,
    this.onAct,
    this.onLoadParticipants,
    this.onEditSettings,
    this.onCheckStatus,
    this.pending = false,
    this.uncertain = false,
    this.canPage = false,
    this.error,
  });

  final Widget body;
  final PolicyDefinition definition;
  final String? siteUrl;
  final PolicyPostData? data;
  final PolicyActionCallback? onAct;
  final PolicyParticipantsLoader? onLoadParticipants;
  final VoidCallback? onEditSettings;
  final Future<void> Function()? onCheckStatus;
  final bool pending;
  final bool uncertain;
  final bool canPage;
  final Object? error;

  @override
  State<PolicyCard> createState() => _PolicyCardState();
}

class _PolicyCardState extends State<PolicyCard> {
  var _submitting = false;
  Object? _actionError;

  Future<void> _act(PolicyAction action) async {
    if (_submitting ||
        widget.pending ||
        widget.uncertain ||
        widget.onAct == null) {
      return;
    }
    setState(() {
      _submitting = true;
      _actionError = null;
    });
    try {
      await widget.onAct!(action);
    } catch (error) {
      if (mounted) setState(() => _actionError = error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void didUpdateWidget(PolicyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data || widget.siteUrl != oldWidget.siteUrl) {
      _actionError = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final data = widget.data;
    final definition = widget.definition;
    final pending = _submitting || widget.pending;
    final disabled = pending || widget.uncertain || widget.onAct == null;
    final error = widget.error ?? _actionError;
    return DCard(
      children: [
        DCardHeader(
          title: DCardTitle(child: Text(l10n.policyTitle)),
          description: DCardDescription(
            child: Text(
              l10n.policyVersionGroups(
                definition.version,
                definition.audienceGroups.join(', '),
              ),
            ),
          ),
          action: widget.onEditSettings == null
              ? null
              : DCardAction(
                  child: DButton.iconOnly(
                    icon: const DIcon(DIcons.gear, size: 18),
                    tooltip: l10n.policyEditSettings,
                    variant: DButtonVariant.ghost,
                    onPressed: pending ? null : widget.onEditSettings,
                  ),
                ),
        ),
        DCardContent(child: widget.body),
        if (data != null)
          DCardContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                if (data.accepted) _AcceptedNotice(),
                if (widget.uncertain)
                  DAlert(
                    variant: DAlertVariant.destructive,
                    title: DAlertTitle(child: Text(l10n.policyStatusUnknown)),
                    description: DAlertDescription(
                      child: Text(l10n.policyStatusUnknownDescription),
                    ),
                    action: DAlertAction(
                      child: DButton(
                        label: Text(l10n.policyCheckStatus),
                        variant: DButtonVariant.outline,
                        loading: pending,
                        onPressed: pending || widget.onCheckStatus == null
                            ? null
                            : () => unawaited(widget.onCheckStatus!()),
                      ),
                    ),
                  )
                else if (error != null)
                  DAlert(
                    variant: DAlertVariant.destructive,
                    title: DAlertTitle(child: Text(l10n.policyCouldNotUpdate)),
                    description: DAlertDescription(
                      child: Text(_errorMessage(error)),
                    ),
                  ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final actions = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (data.canAccept)
                          DButton(
                            label: Text(
                              definition.acceptLabel ?? l10n.policyAccept,
                            ),
                            icon: data.accepted
                                ? const DIcon(DIcons.check, size: 16)
                                : null,
                            variant: data.accepted && !data.revoked
                                ? DButtonVariant.outline
                                : DButtonVariant.primary,
                            loading: pending,
                            onPressed: disabled
                                ? null
                                : () => unawaited(_act(PolicyAction.accept)),
                          ),
                        if (data.canRevoke)
                          DButton(
                            label: Text(
                              definition.revokeLabel ?? l10n.policyRevoke,
                            ),
                            icon: DIcon(
                              data.revoked
                                  ? DIcons.check
                                  : Directionality.of(context) ==
                                        TextDirection.rtl
                                  ? DIcons.arrowRotateRight
                                  : DIcons.arrowRotateLeft,
                              size: 16,
                            ),
                            variant: DButtonVariant.destructive,
                            loading: pending,
                            onPressed: disabled
                                ? null
                                : () => unawaited(_act(PolicyAction.revoke)),
                          ),
                      ],
                    );
                    final statistics = data.statistics;
                    final participants = statistics is! PolicyStatisticsVisible
                        ? null
                        : _InlineParticipants(
                            siteUrl: widget.siteUrl,
                            statistics: statistics,
                            canPage: widget.canPage,
                            loader: widget.onLoadParticipants,
                          );
                    if ((!data.canAccept && !data.canRevoke) ||
                        constraints.maxWidth < 500) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 12,
                        children: [
                          if (data.canAccept || data.canRevoke) actions,
                          ?participants,
                        ],
                      );
                    }
                    return Row(
                      spacing: 20,
                      children: [
                        actions,
                        if (participants != null)
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: participants,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AcceptedNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: DCard(
        size: DCardSize.small,
        sheenColor: tokens.success,
        backgroundColor: Color.lerp(tokens.background, tokens.success, .035),
        borderColor: Color.lerp(tokens.border, tokens.success, .3),
        children: [
          DCardContent(
            child: Row(
              spacing: 14,
              children: [
                ExcludeSemantics(
                  child: DIcon(
                    DIcons.circleCheck,
                    size: 30,
                    color: tokens.success,
                  ),
                ),
                Expanded(
                  child: DCardTitle(
                    child: Text(
                      context.l10n.policyAccepted,
                      style: TextStyle(
                        color: Color.lerp(
                          tokens.foreground,
                          tokens.success,
                          .6,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticipantPage {
  _ParticipantPage(List<PolicyUserSummary> preview, this.total)
    : users = [...preview],
      offset = preview.length;
  final List<PolicyUserSummary> users;
  final int total;
  int offset;
  bool loading = false;
  bool exhausted = false;
  Object? error;
}

class _InlineParticipants extends StatefulWidget {
  const _InlineParticipants({
    required this.siteUrl,
    required this.statistics,
    required this.canPage,
    required this.loader,
  });
  final String? siteUrl;
  final PolicyStatisticsVisible statistics;
  final bool canPage;
  final PolicyParticipantsLoader? loader;
  @override
  State<_InlineParticipants> createState() => _InlineParticipantsState();
}

class _InlineParticipantsState extends State<_InlineParticipants> {
  PolicyParticipantList _selected = PolicyParticipantList.accepted;
  late Map<PolicyParticipantList, _ParticipantPage> _pages = _initialPages();
  int _generation = 0;
  bool _unavailable = false;

  Map<PolicyParticipantList, _ParticipantPage> _initialPages() => {
    PolicyParticipantList.accepted: _ParticipantPage(
      widget.statistics.acceptedPreview,
      widget.statistics.acceptedCount,
    ),
    PolicyParticipantList.outstanding: _ParticipantPage(
      widget.statistics.outstandingPreview,
      widget.statistics.outstandingCount,
    ),
  };

  @override
  void didUpdateWidget(_InlineParticipants oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.statistics, oldWidget.statistics) ||
        widget.siteUrl != oldWidget.siteUrl ||
        (oldWidget.canPage && !widget.canPage)) {
      _generation++;
      _pages = _initialPages();
      _unavailable = false;
    }
  }

  Future<void> _loadMore() async {
    final list = _selected;
    final page = _pages[list]!;
    final loader = widget.loader;
    if (!widget.canPage ||
        loader == null ||
        page.loading ||
        page.exhausted ||
        _unavailable) {
      return;
    }
    final generation = _generation;
    setState(() {
      page.loading = true;
      page.error = null;
    });
    try {
      final result = await loader(list, page.offset);
      if (!mounted || generation != _generation) return;
      setState(() {
        if (result == null) {
          _unavailable = true;
          _pages.clear();
          _generation++;
          return;
        }
        final ids = page.users.map((user) => user.id).toSet();
        page.users.addAll(result.users.where((user) => ids.add(user.id)));
        page.offset += result.receivedCount;
        page.exhausted = result.receivedCount < 25 || page.offset >= page.total;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        if (_accessDenied(error)) {
          _unavailable = true;
          _pages.clear();
          _generation++;
        } else {
          page.error = error;
        }
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => page.loading = false);
      }
    }
  }

  bool _accessDenied(Object error) => switch (error) {
    SiteLookupException(:final statusCode) =>
      statusCode == 401 ||
          statusCode == 403 ||
          statusCode == 404 ||
          statusCode == 422,
    WriteException(:final failure, :final statusCode) =>
      failure == WriteFailure.forbidden ||
          statusCode == 404 ||
          statusCode == 422,
    _ => false,
  };

  Widget _count(PolicyParticipantList list, int count) {
    final accepted = list == PolicyParticipantList.accepted;
    return DTooltip(
      message: accepted
          ? context.l10n.policyAcceptedUsersTooltip
          : context.l10n.policyOutstandingUsersTooltip,
      child: DToggle(
        key: ValueKey('policy-participants-${list.name}'),
        variant: DToggleVariant.inline,
        pressed: _selected == list,
        semanticLabel: accepted
            ? context.l10n.policyAcceptedCount('$count')
            : context.l10n.policyOutstandingCount('$count'),
        icon: DIcon(accepted ? DNativeIcons.userCheck : DIcons.user, size: 16),
        onPressedChanged: (_) => setState(() => _selected = list),
        child: Text('$count'),
      ),
    );
  }

  Widget _avatar(PolicyUserSummary user) {
    final fallback = DAvatarFallback(
      child: Text(user.username.characters.first.toUpperCase()),
    );
    return DTooltip(
      message: user.username,
      child: DAvatar(
        size: DAvatarSize.sm,
        semanticLabel: user.username,
        child: widget.siteUrl == null
            ? fallback
            : SiteImage(
                url: resolveSiteUrl(
                  user.avatarTemplate.replaceAll('{size}', '48'),
                  widget.siteUrl,
                ),
                siteUrl: widget.siteUrl,
                width: 24,
                height: 24,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                loadingBuilder: (_) => fallback,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_unavailable) return Text(context.l10n.policyParticipantsUnavailable);
    final stats = widget.statistics;
    if (stats.acceptedCount == 0 && stats.outstandingCount == 0) {
      return Text(context.l10n.policyNoPossibleUsers);
    }
    final page = _pages[_selected]!;
    final remaining = (page.total - page.users.length).clamp(0, page.total);
    final avatars = <Widget>[
      for (final user in page.users) _avatar(user),
      if (remaining > 0 &&
          !page.exhausted &&
          widget.canPage &&
          widget.loader != null)
        DButton(
          key: const ValueKey('policy-participants-more'),
          label: Text('+$remaining'),
          icon: const DIcon(DIcons.user, size: 14),
          tooltip: context.l10n.policyLoadMoreUsers('$remaining'),
          semanticLabel: context.l10n.policyLoadMoreUsers('$remaining'),
          size: DButtonSize.small,
          variant: DButtonVariant.ghost,
          loading: page.loading,
          onPressed: page.loading ? null : () => unawaited(_loadMore()),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (stats.acceptedCount > 0)
              _count(PolicyParticipantList.accepted, stats.acceptedCount),
            if (_selected == PolicyParticipantList.accepted) ...avatars,
            if (stats.acceptedCount > 0 && stats.outstandingCount > 0)
              const DSeparator(orientation: Axis.vertical, length: 20),
            if (stats.outstandingCount > 0)
              _count(PolicyParticipantList.outstanding, stats.outstandingCount),
            if (_selected == PolicyParticipantList.outstanding) ...avatars,
          ],
        ),
        if (page.error case final error?)
          DAlert(
            variant: DAlertVariant.destructive,
            description: DAlertDescription(child: Text(_errorMessage(error))),
            action: DAlertAction(
              child: DButton(
                label: Text(context.l10n.retry),
                variant: DButtonVariant.outline,
                onPressed: page.loading ? null : () => unawaited(_loadMore()),
              ),
            ),
          ),
      ],
    );
  }
}

String _errorMessage(Object error) => switch (error) {
  WriteException() => error.message,
  SiteLookupException() => error.message,
  _ => appL10n.couldnTReachTheSite,
};
