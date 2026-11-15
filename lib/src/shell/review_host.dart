import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import '../data/review_api.dart';
import '../models/content_route.dart';
import 'external_link.dart';
import 'forum_theme_surfaces.dart';
import 'open_link.dart';
import 'review_controller.dart';
import 'review_page.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'site_url.dart';

/// Mounts the review queue for one account and opens the item a link named.
class ReviewHost extends StatefulWidget {
  const ReviewHost({super.key, required this.siteUrl, this.reviewableId});

  final String siteUrl;

  /// The item a `/review/<id>` link asked for; null for the queue itself.
  final int? reviewableId;

  @override
  State<ReviewHost> createState() => ReviewHostState();
}

class ReviewHostState extends State<ReviewHost> {
  ReviewController? _controller;
  Object? _identity;
  final _queueKey = GlobalKey();
  bool _itemOpen = false;
  ReviewNotice? _announced;

  Future<void> refresh() => _controller?.refresh() ?? Future.value();

  /// A closed item must not stay the tab's destination: the same link would
  /// then count as already open, and a restored tab would reopen the item.
  void _followSelection() {
    _announce();
    final open = _controller?.state.selectedId != null;
    final closed = _itemOpen && !open;
    _itemOpen = open;
    final id = widget.reviewableId;
    if (!closed || id == null || !mounted) return;
    final shell = ShellScope.read(context);
    if (shell.currentContent?.sameDestinationAs(
          ContentRoute.review(reviewableId: id),
        ) ==
        true) {
      shell.replaceCurrentContent(ContentRoute.review());
    }
  }

  /// A finished action is said once, over whichever screen it left showing:
  /// the item usually closes with it, so a note on the item would go unread.
  void _announce() {
    final notice = _controller?.state.notice;
    if (notice is! ReviewPerformed || identical(notice, _announced)) return;
    _announced = notice;
    if (!mounted) return;
    DToast.show(
      context,
      notice.message ?? context.l10n.reviewPerformed,
      type: DToastType.success,
    );
  }

  @override
  void didUpdateWidget(ReviewHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = widget.reviewableId;
    if (id != null &&
        id != oldWidget.reviewableId &&
        id != _controller?.state.selectedId &&
        widget.siteUrl == oldWidget.siteUrl) {
      unawaited(_controller?.open(id));
    }
  }

  @override
  Widget build(BuildContext context) =>
      ShellSelector<
        ({
          ShellController shell,
          Object session,
          String? username,
          bool reviews,
        })
      >(
        select: (shell) {
          final user = shell.instanceFor(widget.siteUrl)?.user;
          return (
            shell: shell,
            session: shell.lifecycle.capture(widget.siteUrl).session,
            username: user?.username,
            reviews: user?.reviews == true,
          );
        },
        builder: (context, owner, _) {
          final shell = owner.shell;
          final identity = (
            widget.siteUrl,
            shell,
            owner.session,
            owner.username,
            owner.reviews,
          );
          if (_identity != identity) {
            _controller?.dispose();
            _itemOpen = false;
            _identity = identity;
            final siteUrl = widget.siteUrl;
            final controller = ReviewController(
              api: DiscourseReviewApi(shell.api.pluginTransport),
              credentials: shell.credentials,
              lease: shell.lifecycle.capture(siteUrl),
              siteUrl: siteUrl,
              permitted: owner.reviews,
              onUnseenCount: (count) =>
                  shell.accountActivity.applyReviewableCounts(siteUrl, {
                    'unseen_reviewable_count': count,
                  }),
            );
            _controller = controller..addListener(_followSelection);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !identical(_controller, controller)) return;
              unawaited(controller.refresh());
              if (widget.reviewableId case final id?) {
                unawaited(controller.open(id));
              }
            });
          }
          final controller = _controller!;
          return ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final state = controller.state;
              final queue = ReviewQueuePage(
                key: _queueKey,
                state: state,
                permitted: owner.reviews,
                siteUrl: widget.siteUrl,
                categories: [
                  for (final category in shell.topicComposerCategories(
                    widget.siteUrl,
                  ))
                    (id: category.id, name: category.name),
                ],
                onRefresh: controller.refresh,
                onFilters: (filters) =>
                    unawaited(controller.setFilters(filters)),
                onLoadMore: () => unawaited(controller.loadMore()),
                onOpen: (item) => unawaited(controller.open(item.id)),
              );
              final id = state.selectedId;
              if (id == null || !owner.reviews) return queue;
              final page = ReviewItemPage(
                key: ValueKey((identity, id)),
                state: state,
                siteUrl: widget.siteUrl,
                onBack: controller.close,
                onRetry: () => unawaited(controller.open(id)),
                onPerform: (item, action) =>
                    unawaited(controller.perform(item, action)),
                onOpenInBrowser: () => unawaited(
                  openExternalLink(
                    resolveSiteRootPath(widget.siteUrl, '/review/$id'),
                  ),
                ),
                onViewInContext: (url) => unawaited(
                  openLink(
                    context,
                    resolveSiteUrl(url, widget.siteUrl),
                    siteUrl: widget.siteUrl,
                  ),
                ),
              );
              if (!shell.mobileNavigationEnabled) return page;
              return DSheetViewport(
                key: ValueKey(('review-item', id)),
                onDismiss: controller.close,
                underlay: queue,
                content: DSheetContent(
                  side: DSheetSide.bottom,
                  variant: DSheetVariant.page,
                  showCloseButton: false,
                  semanticLabel: state.selected == null
                      ? context.l10n.reviewTitle
                      : reviewItemSummary(state.selected!),
                  backgroundColor: ForumWindowBackground.panelColor(context),
                  children: [Expanded(child: page)],
                ),
              );
            },
          );
        },
      );

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
