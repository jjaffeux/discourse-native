part of 'review_page.dart';

/// One item: what it is about, why it is queued, and what can be done.
class ReviewItemPage extends StatelessWidget {
  const ReviewItemPage({
    super.key,
    required this.state,
    required this.siteUrl,
    required this.onBack,
    required this.onPerform,
    required this.onOpenInBrowser,
    this.onRetry,
    this.onViewInContext,
  });

  final ReviewState state;
  final String siteUrl;
  final VoidCallback onBack;
  final void Function(Reviewable item, ReviewableAction action) onPerform;

  /// Opens this item on the site, where the actions this app cannot carry
  /// out are performed.
  final VoidCallback onOpenInBrowser;
  final VoidCallback? onRetry;
  final ValueChanged<String>? onViewInContext;

  Future<void> _press(
    BuildContext context,
    Reviewable item,
    ReviewableAction action,
  ) async {
    final l10n = context.l10n;
    switch (item.routeFor(action)) {
      case ReviewableActionRoute.browser:
        onOpenInBrowser();
      case ReviewableActionRoute.perform:
        onPerform(item, action);
      case ReviewableActionRoute.confirm ||
          ReviewableActionRoute.confirmDestructive:
        final destructive =
            item.routeFor(action) == ReviewableActionRoute.confirmDestructive;
        final confirmed = await showDiscourseAlertDialog<bool>(
          context: context,
          title: Text(action.label),
          description: Text(
            action.confirmMessage ??
                action.description ??
                l10n.reviewConfirmDestructive,
          ),
          cancelLabel: Text(l10n.cancel),
          actionLabel: Text(action.label),
          cancelResult: false,
          actionResult: true,
          actionVariant: destructive
              ? DButtonVariant.destructive
              : DButtonVariant.primary,
          actionKey: const ValueKey('review-confirm-action'),
        );
        if (confirmed == true) onPerform(item, action);
    }
  }

  /// Back and the links out sit in the controls, which every layout keeps:
  /// a phone moves the title itself into its top bar.
  Widget _controls(BuildContext context, Reviewable? item) {
    final l10n = context.l10n;
    final target = item?.targetUrl;
    return DControlWrap(
      wrap: false,
      children: [
        DButton(
          key: const ValueKey('review-back'),
          icon: const DIcon(DIcons.arrowLeft),
          label: Text(l10n.reviewBackToQueue),
          variant: DButtonVariant.ghost,
          onPressed: onBack,
        ),
        const DControlExpanded(child: SizedBox.shrink()),
        DDropdownMenu(
          sheetOnMobile: true,
          mobileSheetVariant: DSheetVariant.adaptiveMenu,
          content: DDropdownMenuContent(
            semanticLabel: l10n.moreActions,
            align: DPopoverAlign.end,
            width: 220,
            children: [
              if (target != null && onViewInContext != null)
                DDropdownMenuItem(
                  leading: const DIcon(DIcons.comments),
                  onPressed: () => onViewInContext!(target),
                  child: Text(l10n.reviewViewInContext),
                ),
              DDropdownMenuItem(
                leading: const DIcon(DIcons.upRightFromSquare),
                onPressed: onOpenInBrowser,
                child: Text(l10n.reviewOpenInBrowser),
              ),
            ],
          ),
          child: DDropdownMenuTrigger(
            builder: (context, menu) => DButton.iconOnly(
              key: const ValueKey('review-item-menu'),
              icon: const DIcon(DIcons.ellipsis),
              tooltip: l10n.moreActions,
              variant: DButtonVariant.ghost,
              focusNode: menu.focusNode,
              hasPopup: true,
              expanded: menu.open,
              onPressed: menu.toggle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _identity(BuildContext context, Reviewable item) {
    final theme = Theme.of(context);
    final meta = _metaStyle(context);
    final author = item.accountUsername ?? item.targetCreatedBy?.username;
    final created = item.createdAt;
    return Row(
      spacing: DSpacing.md,
      children: [
        _ReviewAvatar(
          person: item.targetCreatedBy,
          username: author,
          siteUrl: siteUrl,
          size: DAvatarSize.lg.dimension,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                author ?? _itemTypeLabel(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (created != null)
                RelativeTimeBuilder(
                  when: created,
                  builder: (context, age) =>
                      Text(context.l10n.ago(age), style: meta),
                )
              else if (item.accountName case final name?)
                Text(name, style: meta),
            ],
          ),
        ),
        if (item.status != ReviewableStatus.pending)
          DBadge(
            variant: _statusVariant(item.status),
            child: Text(reviewStatusLabel(item.status)),
          ),
      ],
    );
  }

  Widget _field(BuildContext context, String label, String value) =>
      MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DSpacing.md,
          children: [
            SizedBox(
              width: 104,
              child: Text(label, style: _metaStyle(context)),
            ),
            Expanded(child: SelectableText(value)),
          ],
        ),
      );

  Widget _subject(BuildContext context, Reviewable item) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final heading = item.title ?? item.topicTitle;
    final fields = [
      if (item.kind == ReviewableKind.user) ...[
        if (item.accountName case final name?)
          _field(context, l10n.reviewAccountName, name),
        if (item.accountEmail case final email?)
          _field(context, l10n.reviewAccountEmail, email),
        if (item.rejectReason case final reason?)
          _field(context, l10n.reviewRejectReason, reason),
      ],
    ];
    final body = item.cooked != null
        ? CookedHtml(html: item.cooked!, siteUrl: siteUrl)
        : item.raw != null
        ? Text(item.raw!)
        : null;
    return DCard(
      child: DCardContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DSpacing.md,
          children: [
            _identity(context, item),
            if (heading != null)
              Semantics(
                header: true,
                child: Text(
                  heading,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ...fields,
            ?body,
            if (item.targetDeleted)
              Text(l10n.reviewContentDeleted, style: _metaStyle(context)),
          ],
        ),
      ),
    );
  }

  Widget _score(BuildContext context, ReviewableScore score) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final meta = _metaStyle(context);
    final status = _scoreStatusLabel(score.status);
    final created = score.createdAt;
    final user = score.user;
    return DCardContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DSpacing.sm,
        children: [
          MergeSemantics(
            child: Row(
              spacing: DSpacing.sm,
              children: [
                if (user != null)
                  _ReviewAvatar(
                    person: user,
                    siteUrl: siteUrl,
                    size: DAvatarSize.sm.dimension,
                  ),
                Expanded(
                  child: Wrap(
                    spacing: DSpacing.sm,
                    runSpacing: DSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (user != null)
                        Text(
                          user.username,
                          semanticsLabel: l10n.reviewFlaggedBy(user.username),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (score.title.isNotEmpty)
                        DBadge(
                          variant: DBadgeVariant.secondary,
                          child: Text(score.title),
                        ),
                      if (status.isNotEmpty &&
                          score.status != ReviewableScoreStatus.pending)
                        Text(status, style: meta),
                    ],
                  ),
                ),
                if (created != null)
                  RelativeTimeBuilder(
                    when: created,
                    builder: (context, age) => Text(age, style: meta),
                  ),
              ],
            ),
          ),
          if (score.reasonHtml case final reason?)
            CookedHtml(html: reason, siteUrl: siteUrl, compactParagraphs: true),
        ],
      ),
    );
  }

  Widget _reasons(BuildContext context, Reviewable item) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.sm,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DSpacing.xs),
          child: Semantics(
            header: true,
            child: Text(
              l10n.reviewReasons,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: DTokens.of(context).mutedForeground,
              ),
            ),
          ),
        ),
        DCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, score) in item.scores.indexed) ...[
                if (index > 0) const DSeparator(space: DSpacing.xl),
                _score(context, score),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _menuItem(
    BuildContext context,
    Reviewable item,
    ReviewableAction action,
  ) {
    final browser = item.routeFor(action) == ReviewableActionRoute.browser;
    final note = browser
        ? context.l10n.reviewOpensInBrowser
        : action.description;
    return DDropdownMenuItem(
      key: ValueKey('review-action-${action.id}'),
      variant: action.isDestructive
          ? DDropdownMenuItemVariant.destructive
          : DDropdownMenuItemVariant.standard,
      trailing: browser ? const DIcon(DIcons.upRightFromSquare) : null,
      semanticLabel: browser
          ? context.l10n.reviewActionInBrowser(action.label)
          : null,
      onPressed: () => unawaited(_press(context, item, action)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(action.label),
          if (note != null)
            Text(
              note,
              style: TextStyle(
                fontSize: DiscourseTypography.xs,
                color: DTokens.of(context).mutedForeground,
              ),
            ),
        ],
      ),
    );
  }

  /// One control per bundle, as the site groups them: a lone action is a
  /// button, several are a menu under the bundle's name.
  Widget _bundle(
    BuildContext context,
    Reviewable item,
    ReviewableActionBundle bundle, {
    required bool leads,
  }) {
    final actions = bundle.actions;
    final busy = state.performing != null;
    final sending = actions.any((action) => action.id == state.performing);
    final destructive = actions.every((action) => action.isDestructive);
    final variant = destructive
        ? DButtonVariant.destructive
        : leads
        ? DButtonVariant.primary
        : DButtonVariant.outline;
    if (actions.length == 1) {
      final action = actions.single;
      final browser = item.routeFor(action) == ReviewableActionRoute.browser;
      return DButton(
        key: ValueKey('review-action-${action.id}'),
        variant: variant,
        label: Text(action.label),
        icon: browser ? const DIcon(DIcons.upRightFromSquare) : null,
        tooltip: action.description,
        semanticLabel: browser
            ? context.l10n.reviewActionInBrowser(action.label)
            : null,
        loading: sending,
        onPressed: busy ? null : () => _press(context, item, action),
      );
    }
    final label = bundle.label ?? actions.first.label;
    return DDropdownMenu(
      sheetOnMobile: true,
      mobileSheetVariant: DSheetVariant.adaptiveMenu,
      content: DDropdownMenuContent(
        semanticLabel: label,
        side: DPopoverSide.top,
        width: 280,
        children: [
          for (final action in actions) _menuItem(context, item, action),
        ],
      ),
      child: DDropdownMenuTrigger(
        builder: (context, menu) => DButton(
          key: ValueKey('review-bundle-${bundle.id}'),
          variant: variant,
          label: Text(label),
          icon: const DIcon(DIcons.chevronDown),
          iconPosition: DButtonIconPosition.end,
          loading: sending,
          focusNode: menu.focusNode,
          hasPopup: true,
          expanded: menu.open,
          onPressed: busy ? null : menu.toggle,
        ),
      ),
    );
  }

  Widget? _footer(BuildContext context, Reviewable? item) {
    if (item == null) return null;
    final bundles = [
      for (final bundle in item.bundles)
        if (bundle.actions.isNotEmpty) bundle,
    ];
    if (bundles.isEmpty) return null;
    final lead = bundles.indexWhere(
      (bundle) => !bundle.actions.every((action) => action.isDestructive),
    );
    final controls = [
      for (final (index, bundle) in bundles.indexed)
        _bundle(context, item, bundle, leads: index == lead),
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: DScrollChrome.bottomInsetOf(context)),
      child: DPageReadingLane(
        basePadding: const EdgeInsets.symmetric(
          horizontal: DSpacing.lg,
          vertical: DSpacing.md,
        ),
        builder: (context, lane) => DCardFooter(
          padding: lane.padding,
          child: Semantics(
            container: true,
            label: context.l10n.reviewActions,
            child: lane.width < 420 && controls.length <= 3
                ? Row(
                    spacing: DSpacing.sm,
                    children: [
                      for (final control in controls) Expanded(child: control),
                    ],
                  )
                : Wrap(
                    spacing: DSpacing.sm,
                    runSpacing: DSpacing.sm,
                    children: controls,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _skeleton(BuildContext context) => DSkeletonRegion(
    semanticsLabel: context.l10n.reviewLoadingItem,
    color: skeletonFill(context),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DSpacing.md,
      children: [
        Row(
          spacing: DSpacing.md,
          children: [
            DSkeleton.circle(diameter: 40),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DSpacing.sm,
              children: [
                DSkeleton(width: 140, height: 12),
                DSkeleton(width: 80, height: 8),
              ],
            ),
          ],
        ),
        FractionallySizedBox(widthFactor: .6, child: DSkeleton(height: 14)),
        FractionallySizedBox(widthFactor: .9, child: DSkeleton(height: 10)),
        FractionallySizedBox(widthFactor: .8, child: DSkeleton(height: 10)),
        FractionallySizedBox(widthFactor: .5, child: DSkeleton(height: 10)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final item = state.selected;
    final failure = state.selectedFailure;
    return DPageSurface.headed(
      title: Text(item == null ? l10n.reviewTitle : _itemTypeLabel(item)),
      controls: _controls(context, item),
      footer: _footer(context, item),
      bodyBuilder: (context, header) => DPageReadingLane(
        basePadding: const EdgeInsets.fromLTRB(
          DSpacing.lg,
          0,
          DSpacing.lg,
          DSpacing.xl,
        ),
        builder: (context, lane) => ListView(
          padding: lane.padding,
          children: [
            header.spacer,
            if (state.notice case final ReviewNotice notice
                when notice is! ReviewPerformed)
              Padding(
                padding: const EdgeInsets.only(bottom: DSpacing.md),
                child: DAlert(
                  variant: DAlertVariant.destructive,
                  icon: const DIcon(DIcons.triangleExclamation),
                  description: DAlertDescription(
                    child: Text(switch (notice) {
                      ReviewConflict() => l10n.reviewConflict,
                      ReviewActionFailed(:final message) => message,
                      ReviewPerformed() => '',
                    }),
                  ),
                ),
              ),
            if (failure != null)
              Padding(
                padding: const EdgeInsets.only(bottom: DSpacing.md),
                child: _retryAlert(
                  _failureText(failure, item: true),
                  failure == ReviewFailure.unavailable ? onRetry : null,
                ),
              ),
            if (item == null && failure == null) _skeleton(context),
            if (item != null) ...[
              if (item.kind == ReviewableKind.other)
                Padding(
                  padding: const EdgeInsets.only(bottom: DSpacing.md),
                  child: DAlert(
                    liveRegion: false,
                    icon: const DIcon(DIcons.circleInfo),
                    description: DAlertDescription(
                      child: Text(l10n.reviewUnsupportedType),
                    ),
                    action: DAlertAction(
                      child: DButton(
                        label: Text(l10n.reviewOpenInBrowser),
                        variant: DButtonVariant.link,
                        onPressed: onOpenInBrowser,
                      ),
                    ),
                  ),
                ),
              _subject(context, item),
              if (item.scores.isNotEmpty) ...[
                const SizedBox(height: DSpacing.xl),
                _reasons(context, item),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
