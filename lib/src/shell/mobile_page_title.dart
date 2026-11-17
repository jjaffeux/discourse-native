import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../theme/discourse_typography.dart';
import 'site_emoji_text.dart';

/// The foreground page's name taking over as its own heading retracts.
class MobilePageTitle extends StatefulWidget {
  const MobilePageTitle({
    super.key,
    required this.header,
    required this.entry,
    required this.history,
    required this.siteUrl,
    this.previousEntry,
    this.showPreviousTitle = false,
    this.titleFallback,
    this.previousTitleFallback,
  });

  final ValueListenable<DPageHeader?> header;
  final String siteUrl;
  final Object entry;
  final Object? previousEntry;
  final Object history;
  final bool showPreviousTitle;
  final String? titleFallback;
  final ({Object entry, String title})? previousTitleFallback;

  static const _titleStyle = TextStyle(
    fontSize: DiscourseTypography.lg,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static const _metadataStyle = TextStyle(
    fontSize: DiscourseTypography.preview,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  /// Reserves both identity lines on every page, including an open sidebar.
  static double minimumExtentOf(BuildContext context) {
    final scaler = DReferenceTextScale.scalerOf(context);
    return (scaler.scale(_titleStyle.fontSize!) * _titleStyle.height!)
            .ceilToDouble() +
        (scaler.scale(_metadataStyle.fontSize!) * _metadataStyle.height!)
            .ceilToDouble() +
        1;
  }

  @override
  State<MobilePageTitle> createState() => _MobilePageTitleState();
}

typedef _TitlePresentation = ({
  String title,
  Widget? leading,
  Widget? metadata,
  double opacity,
});

class _MobilePageTitleState extends State<MobilePageTitle> {
  final _presentations = <Object, _TitlePresentation>{};
  ValueListenable<double>? _sheetPull;
  (Object history, Object entry)? _sheetPullVisit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pull = DSheetDragScope.dismissProgressOf(context);
    if (pull == _sheetPull) return;
    _sheetPull?.removeListener(_trackSheetPull);
    _sheetPull = pull;
    _sheetPullVisit = null;
    _sheetPull?.addListener(_trackSheetPull);
    _trackSheetPull();
  }

  void _trackSheetPull() {
    // The drag scope can clear the dismissed sheet after the next visit builds.
    if ((_sheetPull?.value ?? 0) == 0) {
      _sheetPullVisit = null;
    } else {
      _sheetPullVisit ??= (widget.history, widget.entry);
    }
  }

  @override
  void dispose() {
    _sheetPull?.removeListener(_trackSheetPull);
    super.dispose();
  }

  @override
  void didUpdateWidget(MobilePageTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.history != widget.history ||
        oldWidget.siteUrl != widget.siteUrl) {
      _presentations.clear();
    }
  }

  Widget _withSwipe(BuildContext context, Widget current, {bool ready = true}) {
    final identity = AnimatedOpacity(
      opacity: ready ? 1 : 0,
      duration: DMotion.duration(context, DMotion.open),
      child: current,
    );
    final swipe = DHistoryTransition.swipeOf(context);
    if (swipe == null) return identity;
    final target = _presentations[swipe.entry];
    final fallback = widget.previousTitleFallback;
    final title =
        target?.title ??
        (fallback != null && fallback.entry == swipe.entry
            ? fallback.title
            : null);
    if (title == null) return identity;
    return IgnorePointer(
      child: ExcludeFocus(
        child: ExcludeSemantics(
          child: Stack(
            alignment: AlignmentDirectional.centerStart,
            children: [
              Opacity(opacity: 1 - swipe.progress, child: identity),
              Opacity(
                opacity: swipe.progress * (target?.opacity ?? 1),
                child: _identity(
                  context,
                  title,
                  target?.leading,
                  target?.metadata,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DReferenceTextScale(
    child: ValueListenableBuilder<DPageHeader?>(
      valueListenable: widget.header,
      builder: (context, page, _) => ListenableBuilder(
        listenable: page ?? widget.header,
        builder: (context, _) => widget.showPreviousTitle
            ? _coveredTitle(context)
            : _withSheetPull(context, _currentTitle(context, page)),
      ),
    ),
  );

  _TitlePresentation? get _previousPresentation {
    final fallback = widget.previousTitleFallback;
    return _presentations[widget.previousEntry] ??
        (fallback != null && fallback.entry == widget.previousEntry
            ? (
                title: fallback.title,
                leading: null,
                metadata: null,
                opacity: 1.0,
              )
            : null);
  }

  Widget _coveredTitle(BuildContext context) {
    final presentation = _previousPresentation;
    if (presentation == null) {
      return _withSwipe(context, const SizedBox.shrink(), ready: false);
    }
    _remember(presentation);
    return _withSwipe(
      context,
      ExcludeSemantics(
        child: Opacity(
          opacity: presentation.opacity,
          child: _identity(
            context,
            presentation.title,
            presentation.leading,
            presentation.metadata,
          ),
        ),
      ),
    );
  }

  void _remember(_TitlePresentation presentation) {
    _presentations[widget.entry] = presentation;
    while (_presentations.length > 8) {
      _presentations.remove(_presentations.keys.first);
    }
  }

  Widget? _currentTitle(BuildContext context, DPageHeader? page) {
    final title = page?.titleText;
    if (page == null || title == null || title.isEmpty) {
      final fallback = widget.titleFallback;
      return fallback == null
          ? null
          : ExcludeSemantics(child: _identity(context, fallback, null, null));
    }
    _remember((
      title: title,
      leading: page.leading,
      metadata: page.metadata,
      opacity: page.barOpacity,
    ));
    final opacity = page.barOpacity;
    final shown = opacity >= .5;
    // The fade follows every scroll frame, so it must not repaint
    // the rest of the bar. The gates below hide the action; a
    // disabled button would dim and rebuild halfway through it.
    return RepaintBoundary(
      child: IgnorePointer(
        ignoring: !shown,
        child: ExcludeSemantics(
          excluding: !shown,
          child: ExcludeFocus(
            excluding: !shown,
            child: Opacity(
              opacity: opacity,
              child: DButton(
                key: const ValueKey('mobile-page-title'),
                variant: DButtonVariant.inline,
                density: DButtonDensity.inlineMetadata,
                foregroundColor: DTokens.of(context).foreground,
                alignment: AlignmentDirectional.centerStart,
                semanticLabel: context.l10n.backToTopOf(title),
                label: _identity(context, title, page.leading, page.metadata),
                onPressed: () => unawaited(page.scrollToTop()),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _withSheetPull(BuildContext context, Widget? current) {
    final progress = _sheetPull;
    final previous = DPageHeaderHost.previousTitleOf(context);
    final cached = previous == null ? _previousPresentation : null;
    final title = previous?.title ?? cached?.title;
    if (progress == null || title == null) {
      return _withSwipe(
        context,
        current ?? const SizedBox.shrink(),
        ready: current != null,
      );
    }
    return _withSwipe(
      context,
      ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, progress, child) {
          final pull = _sheetPullVisit == (widget.history, widget.entry)
              ? progress
              : 0.0;
          return Stack(
            alignment: AlignmentDirectional.centerStart,
            children: [
              if (child != null)
                IgnorePointer(
                  ignoring: pull >= .5,
                  child: ExcludeSemantics(
                    excluding: pull >= .5,
                    child: ExcludeFocus(
                      excluding: pull >= .5,
                      child: Opacity(opacity: 1 - pull, child: child),
                    ),
                  ),
                ),
              if (pull > 0)
                IgnorePointer(
                  child: ExcludeSemantics(
                    child: Opacity(
                      opacity: pull * (cached?.opacity ?? 1),
                      child: _identity(
                        context,
                        title,
                        previous?.leading ?? cached?.leading,
                        previous?.metadata ?? cached?.metadata,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        child: current,
      ),
    );
  }

  Widget _identity(
    BuildContext context,
    String title,
    Widget? leading,
    Widget? metadata,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: metadata == null ? 0 : 1,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            ?leading,
            Flexible(
              child: SiteEmojiText.plain(
                title,
                siteUrl: widget.siteUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MobilePageTitle._titleStyle,
              ),
            ),
          ],
        ),
        if (metadata != null)
          DefaultTextStyle.merge(
            style: MobilePageTitle._metadataStyle.copyWith(
              color: DTokens.of(context).mutedForeground,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: IconTheme.merge(
              data: IconThemeData(color: DTokens.of(context).mutedForeground),
              child: metadata,
            ),
          ),
      ],
    );
  }
}
