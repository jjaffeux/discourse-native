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

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DPageHeader?>(
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
                          foregroundColor: DTokens.of(context).foreground,
                          alignment: AlignmentDirectional.centerStart,
                          semanticLabel: context.l10n.backToTopOf(title),
                          icon: page.leading,
                          label: SiteEmojiText.plain(
                            title,
                            siteUrl: siteUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: DiscourseTypography.lg,
                              fontWeight: FontWeight.w600,
                            ),
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
                                child: SiteEmojiText.plain(
                                  previous.title,
                                  siteUrl: siteUrl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: DiscourseTypography.lg,
                                    fontWeight: FontWeight.w600,
                                  ),
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
  );
}
