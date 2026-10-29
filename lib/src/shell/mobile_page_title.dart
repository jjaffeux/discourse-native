import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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
              final opacity = page.layout == DPageHeaderLayout.expanded
                  ? 0.0
                  : page.value;
              final shown = opacity >= .5;
              return IgnorePointer(
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
                        label: SiteEmojiText.plain(
                          title,
                          siteUrl: siteUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: shown
                            ? () => unawaited(page.scrollToTop())
                            : null,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
  );
}
