import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;

import '../../foundation/count_label.dart';
import '../../theme/d_icons.dart';
import '../../theme/discourse_typography.dart';
import '../cooked_dom.dart';
import '../cooked_html.dart';
import '../open_link.dart';
import '../site_image.dart';
import 'markup.dart';
import 'onebox.dart';

/// The fields actually supplied by Discourse's twitterstatus template.
class TwitterOneboxData {
  const TwitterOneboxData({
    required this.name,
    required this.bodyHtml,
    this.url,
    this.handle,
    this.avatarUrl,
    this.timestamp,
    this.likes,
    this.reposts,
    this.isReply = false,
    this.quote,
  });

  final String name;
  final String bodyHtml;
  final String? url;
  final String? handle;
  final String? avatarUrl;
  final String? timestamp;
  final String? likes;
  final String? reposts;
  final bool isReply;
  final TwitterOneboxData? quote;

  String? get profileUrl => handle == null ? null : 'https://x.com/$handle';
  String? get statusId => url == null ? null : Uri.parse(url!).pathSegments[2];

  static TwitterOneboxData? from(dom.Element aside, OneboxData envelope) {
    final description = _withClass(aside, 'tweet-description');
    if (description == null) return null;
    final avatar = _withClass(aside, 'onebox-avatar');
    final quoted = _withClass(aside, 'quoted');
    final title = quoted == null ? null : _withClass(quoted, 'quoted-title');
    final quoteHandle = title == null
        ? null
        : descendantWhere(title, (e) => e.localName == 'span');
    final quoteBody = quoted == null
        ? null
        : childWhere(quoted, (e) => e.localName == 'div');
    final quoteLink = quoted == null ? null : _withClass(quoted, 'quoted-link');
    final url = _postUrl(envelope.url);
    return TwitterOneboxData(
      name: envelope.title ?? 'Post on X',
      bodyHtml: description.innerHtml,
      url: url,
      handle: _handle(_withClass(aside, 'twitter-screen-name')?.text),
      avatarUrl: avatar?.attributes['src']?.trim().nullIfEmpty,
      timestamp: _text(_withClass(aside, 'timestamp')),
      likes: _text(_withClass(aside, 'like')),
      reposts: _text(_withClass(aside, 'retweet')),
      isReply: _withClass(aside, 'is-reply') != null,
      quote: quoted == null || quoteBody == null
          ? null
          : TwitterOneboxData(
              name:
                  title?.nodes
                      .where((node) => node != quoteHandle)
                      .map((node) => node.text ?? '')
                      .join()
                      .trim()
                      .nullIfEmpty ??
                  'Quoted post',
              handle: _handle(quoteHandle?.text),
              url: _postUrl(quoteLink?.attributes['href']),
              bodyHtml: quoteBody.innerHtml,
            ),
    );
  }

  static dom.Element? _withClass(dom.Element root, String name) =>
      descendantWhere(root, (e) => e.classes.contains(name));

  static String? _text(dom.Element? element) =>
      element?.text.trim().replaceAll(RegExp(r'\s+'), ' ').nullIfEmpty;

  static String? _handle(String? text) {
    final handle = text?.trim().replaceFirst(RegExp(r'^@'), '');
    return handle != null && RegExp(r'^[a-zA-Z0-9_]{1,15}$').hasMatch(handle)
        ? handle
        : null;
  }

  static String? _postUrl(String? value) {
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null ||
        !const {'https', 'http'}.contains(uri.scheme) ||
        !const {
          'x.com',
          'www.x.com',
          'twitter.com',
          'www.twitter.com',
          'mobile.twitter.com',
        }.contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        !RegExp(r'^/[^/]+/status/\d+/?$').hasMatch(uri.path)) {
      return null;
    }
    return uri.toString();
  }
}

final twitterBlock = OneboxEngine(
  matches: (aside) => aside.classes.contains('twitterstatus'),
  build: (aside, envelope, siteUrl) {
    final data = TwitterOneboxData.from(aside, envelope);
    return data == null
        ? OneboxCard(data: envelope, siteUrl: siteUrl)
        : TwitterOnebox(data: data, siteUrl: siteUrl);
  },
);

class TwitterOnebox extends StatelessWidget {
  const TwitterOnebox({super.key, required this.data, this.siteUrl});

  final TwitterOneboxData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 550),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: DSpacing.sm),
        child: Theme(
          data: _twitterTheme(context),
          child: Builder(
            builder: (context) => DCard(
              borderRadius: BorderRadius.circular(12),
              children: [
                DCardContent(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Author(data: data, siteUrl: siteUrl),
                      const SizedBox(height: DSpacing.md),
                      if (data.isReply) ...[
                        Text(
                          'Replying to a post',
                          style: TextStyle(
                            color: DTokens.of(context).mutedForeground,
                            fontSize: DiscourseTypography.control,
                          ),
                        ),
                        const SizedBox(height: DSpacing.xs),
                      ],
                      _PostBody(data: data, siteUrl: siteUrl),
                      if (data.quote case final quote?) ...[
                        const SizedBox(height: DSpacing.md),
                        _QuotedPost(data: quote, siteUrl: siteUrl),
                      ],
                      if (data.timestamp case final timestamp?) ...[
                        const SizedBox(height: DSpacing.sm),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: DButton(
                            size: DButtonSize.post,
                            variant: DButtonVariant.inline,
                            isLink: true,
                            label: Text(timestamp, softWrap: true, maxLines: 3),
                            onPressed: data.url == null
                                ? null
                                : () => openLink(context, data.url!),
                          ),
                        ),
                      ],
                      const SizedBox(height: DSpacing.sm),
                      const DSeparator(),
                      const SizedBox(height: DSpacing.sm),
                      _PostActions(data: data),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// Provider branding stays at this application boundary. Native components still
// own their surfaces, control geometry, focus, hover and accessible targets.
ThemeData _twitterTheme(BuildContext context) {
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  final background = dark ? const Color(0xff15202b) : const Color(0xffffffff);
  final foreground = dark ? const Color(0xfff7f9f9) : const Color(0xff0f1419);
  final muted = dark ? const Color(0xff8b98a5) : const Color(0xff536471);
  final border = dark ? const Color(0xff425364) : const Color(0xffcfd9de);
  final primary = dark ? const Color(0xff6bc9fb) : const Color(0xff006fd6);
  final colors = theme.colorScheme.copyWith(
    surface: background,
    onSurface: foreground,
    onSurfaceVariant: muted,
    primary: primary,
    outlineVariant: border,
  );
  return theme.copyWith(
    colorScheme: colors,
    extensions: [
      ...theme.extensions.values.where((extension) => extension is! DTokens),
      DTokens.of(context).copyWith(
        colors: colors,
        background: background,
        surface: background,
        muted: background,
        border: border,
      ),
    ],
  );
}

class _Author extends StatelessWidget {
  const _Author({required this.data, required this.siteUrl});
  final TwitterOneboxData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    const fallback = DAvatarFallback(child: Icon(Icons.person_outline));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DAvatar(
          dimension: 48,
          decorative: true,
          fallback: fallback,
          child: data.avatarUrl == null
              ? null
              : SiteImage(
                  url: data.avatarUrl!,
                  siteUrl: siteUrl,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  coverDecodeSize: const Size.square(48),
                  excludeFromSemantics: true,
                  loadingBuilder: (_) => fallback,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
        const SizedBox(width: DSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DButton(
                size: DButtonSize.post,
                variant: DButtonVariant.inline,
                foregroundColor: tokens.foreground,
                isLink: true,
                label: Text(
                  data.name,
                  softWrap: true,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: DiscourseTypography.base,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: (data.profileUrl ?? data.url) == null
                    ? null
                    : () => openLink(context, (data.profileUrl ?? data.url)!),
              ),
              if (data.handle case final handle?)
                Wrap(
                  spacing: DSpacing.controlGap,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '@$handle',
                      style: TextStyle(color: tokens.mutedForeground),
                    ),
                    Text('·', style: TextStyle(color: tokens.mutedForeground)),
                    DButton(
                      size: DButtonSize.post,
                      variant: DButtonVariant.inline,
                      foregroundColor: tokens.primary,
                      label: const Text(
                        'Follow',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      semanticLabel: 'Follow @$handle on X',
                      isLink: true,
                      onPressed: () => openLink(
                        context,
                        Uri.https('x.com', '/intent/follow', {
                          'screen_name': handle,
                        }).toString(),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(width: DSpacing.sm),
        DButton.iconOnly(
          variant: DButtonVariant.transparentBackground,
          size: DButtonSize.post,
          icon: DIcon(_xLogo, color: tokens.foreground),
          tooltip: 'View post on X',
          isLink: true,
          onPressed: data.url == null
              ? null
              : () => openLink(context, data.url!),
        ),
      ],
    );
  }
}

class _PostBody extends StatelessWidget {
  const _PostBody({
    required this.data,
    required this.siteUrl,
    this.quoted = false,
  });
  final TwitterOneboxData data;
  final String? siteUrl;
  final bool quoted;

  @override
  Widget build(BuildContext context) => CookedHtml(
    html: data.bodyHtml,
    siteUrl: siteUrl,
    compactParagraphs: true,
    textStyle: Theme.of(context).textTheme.bodyLarge!.copyWith(
      color: DTokens.of(context).foreground,
      fontSize: quoted ? 15 : 20,
      height: quoted ? 20 / 15 : 1.2,
    ),
    linkStyle: TextStyle(color: DTokens.of(context).primary),
  );
}

class _QuotedPost extends StatelessWidget {
  const _QuotedPost({required this.data, required this.siteUrl});
  final TwitterOneboxData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) => DCard(
    size: DCardSize.small,
    borderRadius: BorderRadius.circular(12),
    children: [
      DCardContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DButton(
                size: DButtonSize.post,
                variant: DButtonVariant.inline,
                foregroundColor: DTokens.of(context).foreground,
                isLink: true,
                label: Text.rich(
                  TextSpan(
                    text: data.name,
                    style: const TextStyle(
                      fontSize: DiscourseTypography.base,
                      fontWeight: FontWeight.w700,
                    ),
                    children: [
                      if (data.handle case final handle?)
                        TextSpan(
                          text: '  @$handle',
                          style: TextStyle(
                            color: DTokens.of(context).mutedForeground,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  softWrap: true,
                  maxLines: 4,
                ),
                onPressed: data.url == null
                    ? null
                    : () => openLink(context, data.url!),
              ),
            ),
            const SizedBox(height: DSpacing.xs),
            _PostBody(data: data, siteUrl: siteUrl, quoted: true),
          ],
        ),
      ),
    ],
  );
}

class _PostActions extends StatefulWidget {
  const _PostActions({required this.data});
  final TwitterOneboxData data;

  @override
  State<_PostActions> createState() => _PostActionsState();
}

class _PostActionsState extends State<_PostActions> {
  bool _copied = false;

  @override
  void didUpdateWidget(_PostActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.url != widget.data.url) _copied = false;
  }

  Future<void> _copy() async {
    final url = widget.data.url!;
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted && widget.data.url == url) setState(() => _copied = true);
    } on PlatformException {
      if (mounted) DToast.show(context, 'Could not copy link. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final url = data.url;
    final tokens = DTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: DSpacing.controlGap,
          runSpacing: DSpacing.xs,
          children: [
            if (data.likes case final likes?)
              DButton(
                variant: DButtonVariant.transparentBackground,
                size: DButtonSize.post,
                icon: const DIcon(DIcons.heart, color: Color(0xfff91880)),
                label: Text(
                  likes,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                semanticLabel: '${_metricLabel(likes, 'like')}. Like on X',
                isLink: true,
                onPressed: data.statusId == null
                    ? null
                    : () => openLink(
                        context,
                        'https://x.com/intent/like?tweet_id=${data.statusId}',
                      ),
              ),
            if (data.reposts case final reposts?)
              DButton(
                variant: DButtonVariant.transparentBackground,
                size: DButtonSize.post,
                icon: const Icon(Icons.repeat),
                label: Text(reposts),
                semanticLabel:
                    '${_metricLabel(reposts, 'repost')}. View post on X',
                isLink: true,
                onPressed: url == null ? null : () => openLink(context, url),
              ),
            if (url != null) ...[
              DButton(
                variant: DButtonVariant.transparentBackground,
                size: DButtonSize.post,
                icon: DIcon(DIcons.comment, color: tokens.primary),
                label: const Text(
                  'Reply',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                isLink: true,
                onPressed: () => openLink(
                  context,
                  'https://x.com/intent/tweet?in_reply_to=${data.statusId}',
                ),
              ),
              DButton(
                variant: DButtonVariant.transparentBackground,
                size: DButtonSize.post,
                icon: DIcon(_copied ? DIcons.check : DIcons.link),
                label: Text(
                  _copied ? 'Copied!' : 'Copy link',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: _copy,
              ),
            ],
          ],
        ),
        if (url != null) ...[
          const SizedBox(height: DSpacing.sm),
          DButton(
            variant: DButtonVariant.outline,
            size: DButtonSize.post,
            shape: DButtonShape.pill,
            foregroundColor: tokens.primary,
            backgroundColor: tokens.background,
            borderColor: tokens.border,
            label: const Text(
              'Read replies',
              softWrap: true,
              maxLines: 2,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            isLink: true,
            onPressed: () => openLink(context, url),
          ),
        ],
      ],
    );
  }
}

/// The onebox writes each metric through Discourse's prettify_number: a plain
/// whole number below a thousand, an abbreviation ("1.2K") from there. Only a
/// written "1" is singular; an abbreviation does not parse and never is.
String _metricLabel(String written, String noun) =>
    countLabel(int.tryParse(written) ?? 0, noun, number: written);

const _xLogo = DIconData(
  'onebox-x-logo',
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
      '<path d="M18.244 2.25h3.308l-7.227 8.26L22.827 21.75H16.17l-5.214-6.817-5.966 6.817H1.68l7.73-8.835L1.173 2.25H8l4.713 6.231zM17.083 19.77h1.833L7.084 4.126H5.117z"/>'
      '</svg>',
);
