import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../theme/discourse_typography.dart';
import 'site_emoji_text.dart';

/// The foreground page's name taking over as its own heading retracts.
class MobilePageTitle extends StatelessWidget {
  const MobilePageTitle({
    super.key,
    required this.header,
    required this.siteUrl,
  });

  final ValueListenable<DPageHeader?> header;
  final String siteUrl;

  static const _titleStyle = TextStyle(
    fontSize: DiscourseTypography.lg,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static const _metadataStyle = TextStyle(
    fontSize: 12.5,
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
  Widget build(BuildContext context) => DReferenceTextScale(
    child: ValueListenableBuilder<DPageHeader?>(
      valueListenable: header,
      builder: (context, page, _) => page == null
          ? const SizedBox.shrink()
          : ListenableBuilder(
              listenable: page,
              builder: (context, _) {
                final title = page.titleText;
                if (title == null || title.isEmpty) {
                  return const SizedBox.shrink();
                }
                final opacity = page.barOpacity;
                final shown = opacity >= .5;
                // The fade follows every scroll frame, so it must not repaint
                // the rest of the bar. The gates below hide the action; a
                // disabled button would dim and rebuild halfway through it.
                final current = RepaintBoundary(
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
                            label: _identity(
                              context,
                              title,
                              page.leading,
                              page.metadata,
                            ),
                            onPressed: () => unawaited(page.scrollToTop()),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                final progress = DSheetDragScope.dismissProgressOf(context);
                final previous = DPageHeaderHost.previousTitleOf(context);
                if (progress == null || previous == null) return current;
                return ValueListenableBuilder<double>(
                  valueListenable: progress,
                  builder: (context, pull, child) => Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: [
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
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: Opacity(
                                opacity: pull,
                                child: Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: _identity(
                                    context,
                                    previous.title,
                                    previous.leading,
                                    previous.metadata,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  child: current,
                );
              },
            ),
    ),
  );

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
                siteUrl: siteUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _titleStyle,
              ),
            ),
          ],
        ),
        if (metadata != null)
          DefaultTextStyle.merge(
            style: _metadataStyle.copyWith(
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
