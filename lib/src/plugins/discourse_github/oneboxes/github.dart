import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:html/dom.dart' as dom;

import '../../local_dates/local_dates_contract.dart';

export 'github_onebox_data.dart';

class GithubOneboxEngine {
  const GithubOneboxEngine({required this.matches, required this.build});

  final bool Function(dom.Element aside) matches;
  final Widget Function(
    dom.Element aside,
    OneboxData envelope,
    String? siteUrl,
    CookedTimeParser? cookedTimeParser,
  )
  build;
}

const Color githubAdditionColor = Color(0xFF3FB950);
const Color githubDeletionColor = Color(0xFFF85149);

/// Preserves upstream's legacy and status-plugin SVG slots without stretching
/// their square viewBoxes.
const double _githubOneboxFontSize = 16;
const double githubIconColumnWidth = _githubOneboxFontSize * 2.5;
const double githubIconGap = _githubOneboxFontSize * 0.75;
const Size githubLegacyIconSize = Size.square(_githubOneboxFontSize * 1.8);
const Size githubPrStatusIconSize = Size.square(githubIconColumnWidth);
const Size githubPrStatusSlotSize = Size(
  githubIconColumnWidth,
  githubIconColumnWidth / (12 / 16),
);

/// Uses upstream raw SVG sizing, not [DIcon]'s Font Awesome optical scaling.
class GithubOneboxIcon extends StatelessWidget {
  const GithubOneboxIcon({
    super.key,
    required this.icon,
    required this.color,
    this.isPrStatus = false,
  });

  final DIconData icon;
  final Color color;
  final bool isPrStatus;

  @override
  Widget build(BuildContext context) {
    final iconSize = isPrStatus ? githubPrStatusIconSize : githubLegacyIconSize;
    final slotSize = isPrStatus ? githubPrStatusSlotSize : githubLegacyIconSize;

    return SizedBox.fromSize(
      size: slotSize,
      child: Center(
        child: SizedBox.fromSize(
          size: iconSize,
          child: SvgPicture.string(
            icon.tintableSvg,
            fit: BoxFit.contain,
            theme: SvgTheme(currentColor: color),
          ),
        ),
      ),
    );
  }
}

class GithubUser extends StatelessWidget {
  const GithubUser({
    super.key,
    required this.login,
    required this.avatarUrl,
    required this.url,
    this.siteUrl,
  });

  final String login;
  final String? avatarUrl;
  final String? url;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final label = Text.rich(
      TextSpan(
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        children: [
          if (avatarUrl != null) ...[
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: DAvatar.frame(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox.square(
                  dimension: 20,
                  child: AvatarImage(
                    url: resolveSiteUrl(avatarUrl!, siteUrl),
                    size: 20,
                    fallback: ColoredBox(color: theme.shell.floating),
                  ),
                ),
              ),
            ),
            const WidgetSpan(child: SizedBox(width: 4)),
          ],
          TextSpan(text: login),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final url = this.url;
    if (url == null) return label;

    return _GithubInlineLink(
      label: login,
      url: url,
      siteUrl: siteUrl,
      child: label,
    );
  }
}

class GithubLineCounts extends StatelessWidget {
  const GithubLineCounts({
    super.key,
    required this.additions,
    required this.deletions,
    required this.url,
    this.siteUrl,
  });

  final int additions;
  final int deletions;
  final String? url;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );

    final counts = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '+$additions',
            style: style?.copyWith(color: githubAdditionColor),
          ),
          const WidgetSpan(child: SizedBox(width: 6)),
          TextSpan(
            text: '−$deletions',
            style: style?.copyWith(color: githubDeletionColor),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final url = this.url;
    if (url == null) return counts;

    return _GithubInlineLink(
      label: context.l10n.messageGithub(additions, deletions),
      url: url,
      siteUrl: siteUrl,
      child: counts,
    );
  }
}

class _GithubInlineLink extends StatelessWidget {
  const _GithubInlineLink({
    required this.label,
    required this.url,
    required this.siteUrl,
    required this.child,
  });

  final String label;
  final String url;
  final String? siteUrl;
  final Widget child;

  @override
  Widget build(BuildContext context) => LinkTarget(
    url: url,
    siteUrl: siteUrl,
    child: DItem(
      fitContent: true,
      size: DItemSize.artwork,
      highlightOnInteraction: false,
      link: true,
      onPressed: () => openLink(context, url, siteUrl: siteUrl),
      semanticLabel: label,
      children: [ExcludeSemantics(child: child)],
    ),
  );
}

class GithubBodyText extends StatelessWidget {
  const GithubBodyText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        maxLines: 10,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium
            ?.merge(monospaceTextStyle)
            .copyWith(
              fontSize: DiscourseTypography.sm,
              height: DiscourseTypography.codeLineHeight,
              color: theme.discourse.primaryVeryHigh,
            ),
      ),
    );
  }
}
