import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../shell/avatar_image.dart';
import '../../shell/cooked_dom.dart';
import '../../shell/cooked_html.dart';
import '../../shell/inline_action.dart';
import '../../shell/open_link.dart';
import '../../shell/quote_panel.dart';
import '../../shell/site_url.dart';
import '../../shell/user_card.dart';
import '../../theme/app_theme.dart';

class ChatTranscriptData {
  const ChatTranscriptData({
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.createdAt,
    required this.dateText,
    required this.sourceLink,
    required this.channelName,
    required this.channelLink,
    required this.metaHtml,
    required this.bodyHtml,
    required this.nestedTranscriptsHtml,
    required this.chained,
  });

  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final DateTime? createdAt;
  final String? dateText;
  final String? sourceLink;
  final String? channelName;
  final String? channelLink;
  final String? metaHtml;
  final String bodyHtml;
  final List<String> nestedTranscriptsHtml;
  final bool chained;

  static ChatTranscriptData from(dom.Element element) {
    final user = _ownedDescendant(
      element,
      (candidate) => candidate.classes.contains('chat-transcript-user'),
    );
    final avatar = user == null
        ? null
        : descendantWhere(
            user,
            (candidate) =>
                candidate.localName == 'img' &&
                candidate.classes.contains('avatar'),
          );
    final usernameElement = user == null
        ? null
        : descendantWhere(
            user,
            (candidate) =>
                candidate.classes.contains('chat-transcript-username'),
          );
    final datetimeElement = user == null
        ? null
        : descendantWhere(
            user,
            (candidate) =>
                candidate.classes.contains('chat-transcript-datetime'),
          );
    final datetimeLink = datetimeElement == null
        ? null
        : descendantWhere(
            datetimeElement,
            (candidate) => candidate.localName == 'a',
          );
    final channel = user == null
        ? null
        : descendantWhere(
            user,
            (candidate) =>
                candidate.classes.contains('chat-transcript-channel'),
          );
    final messages = _ownedDescendant(
      element,
      (candidate) => candidate.classes.contains('chat-transcript-messages'),
    );
    final images = _ownedDescendant(
      element,
      (candidate) => candidate.classes.contains('chat-transcript-images'),
    );
    final meta = _ownedDescendant(
      element,
      (candidate) => candidate.classes.contains('chat-transcript-meta'),
    );
    final dateSource =
        element.attributes['data-datetime']?.nullIfEmpty ??
        datetimeLink?.attributes['title']?.nullIfEmpty ??
        datetimeElement?.attributes['title']?.nullIfEmpty;

    return ChatTranscriptData(
      username: element.attributes['data-username']?.nullIfEmpty,
      displayName:
          usernameElement?.text.trim().nullIfEmpty ??
          element.attributes['data-username']?.nullIfEmpty,
      avatarUrl: avatar?.attributes['src']?.nullIfEmpty,
      createdAt: _parseCoreDate(dateSource),
      dateText:
          datetimeElement?.text.trim().nullIfEmpty ?? dateSource?.nullIfEmpty,
      sourceLink: datetimeLink?.attributes['href']?.nullIfEmpty,
      channelName: channel?.text.trim().nullIfEmpty,
      channelLink: channel?.attributes['href']?.nullIfEmpty,
      metaHtml: meta?.innerHtml.trim().nullIfEmpty,
      bodyHtml: [
        ?messages?.innerHtml.trim().nullIfEmpty,
        ?images?.innerHtml.trim().nullIfEmpty,
      ].join('\n'),
      nestedTranscriptsHtml: [
        for (final candidate in descendantsWhere(
          element,
          (candidate) => candidate.classes.contains('chat-transcript'),
        ))
          if (_belongsToTranscript(candidate, element) &&
              !_isInside(candidate, messages) &&
              !_isInside(candidate, images))
            candidate.outerHtml,
      ],
      chained: element.classes.contains('chat-transcript-chained'),
    );
  }
}

Widget? chatTranscriptWidgetBuilder(dom.Element element, {String? siteUrl}) {
  final isTranscript =
      (element.localName == 'div' || element.localName == 'details') &&
      element.classes.contains('chat-transcript');
  if (!isTranscript) return null;
  return ChatTranscriptBlock(
    data: ChatTranscriptData.from(element),
    siteUrl: siteUrl,
  );
}

class ChatTranscriptBlock extends StatelessWidget {
  const ChatTranscriptBlock({super.key, required this.data, this.siteUrl});

  final ChatTranscriptData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return QuotePanel(
      margin: EdgeInsets.symmetric(vertical: data.chained ? 0 : 8),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.metaHtml case final meta?) ...[
            CookedHtml(
              html: meta,
              siteUrl: siteUrl,
              textStyle: theme.textTheme.bodySmall?.copyWith(
                color: theme.discourse.primaryHigh,
              ),
              compactParagraphs: true,
            ),
            Divider(color: theme.dividerColor),
          ],
          if (data.username != null ||
              data.displayName != null ||
              data.avatarUrl != null ||
              data.createdAt != null ||
              data.dateText != null ||
              data.channelName != null) ...[
            _TranscriptHeader(data: data, siteUrl: siteUrl),
            const SizedBox(height: 8),
          ],
          if (data.bodyHtml.isNotEmpty)
            CookedHtml(
              html: data.bodyHtml,
              siteUrl: siteUrl,
              textStyle: theme.textTheme.bodyMedium,
              compactParagraphs: true,
            ),
          for (final transcript in data.nestedTranscriptsHtml)
            CookedHtml(html: transcript, siteUrl: siteUrl),
        ],
      ),
    );
  }
}

class _TranscriptHeader extends StatelessWidget {
  const _TranscriptHeader({required this.data, required this.siteUrl});

  final ChatTranscriptData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.discourse.primaryHigh;
    final dateText = data.createdAt == null
        ? data.dateText
        : _formatDate(context, data.createdAt!);

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (data.displayName != null || data.avatarUrl != null)
          _Author(
            username: data.username,
            label: data.displayName,
            avatarUrl: data.avatarUrl,
            siteUrl: siteUrl,
          ),
        if (dateText != null)
          _TranscriptLink(
            label: dateText,
            href: data.sourceLink,
            siteUrl: siteUrl,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        if (data.channelName case final channel?)
          _TranscriptLink(
            label: channel,
            href: data.channelLink,
            siteUrl: siteUrl,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
      ],
    );
  }

  String _formatDate(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final material = MaterialLocalizations.of(context);
    final date = material.formatShortMonthDay(local);
    final time = material.formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return '$date, $time';
  }
}

class _Author extends StatelessWidget {
  const _Author({
    required this.username,
    required this.label,
    required this.avatarUrl,
    required this.siteUrl,
  });

  final String? username;
  final String? label;
  final String? avatarUrl;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (avatarUrl case final avatar?) ...[
          ClipOval(
            child: SizedBox.square(
              dimension: 20,
              child: AvatarImage(
                url: _absoluteUrl(avatar),
                size: 20,
                fallback: ColoredBox(color: theme.shell.floating),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (label case final label?)
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
    if (username case final username?) {
      return UserCardTarget(username: username, siteUrl: siteUrl, child: row);
    }
    return row;
  }

  String? _absoluteUrl(String src) {
    final resolved = resolveSiteUrl(src, siteUrl);
    return resolved.startsWith('http') ? resolved : null;
  }
}

class _TranscriptLink extends StatelessWidget {
  const _TranscriptLink({
    required this.label,
    required this.href,
    required this.siteUrl,
    required this.style,
  });

  final String label;
  final String? href;
  final String? siteUrl;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final text = Text(label, style: style);
    if (href == null) return text;

    return InlineAction.link(
      onTap: () => openLink(context, href!, siteUrl: siteUrl),
      semanticLabel: label,
      excludeChildSemantics: true,
      child: text,
    );
  }
}

dom.Element? _ownedDescendant(
  dom.Element root,
  bool Function(dom.Element) test,
) {
  for (final candidate in descendantsWhere(root, test)) {
    if (_belongsToTranscript(candidate, root)) return candidate;
  }
  return null;
}

bool _belongsToTranscript(dom.Element element, dom.Element root) {
  dom.Node? parent = element.parentNode;
  while (parent != null && !identical(parent, root)) {
    if (parent is dom.Element && parent.classes.contains('chat-transcript')) {
      return false;
    }
    parent = parent.parentNode;
  }
  return identical(parent, root);
}

bool _isInside(dom.Element element, dom.Element? ancestor) {
  if (ancestor == null) return false;
  dom.Node? parent = element.parentNode;
  while (parent != null) {
    if (identical(parent, ancestor)) return true;
    parent = parent.parentNode;
  }
  return false;
}

DateTime? _parseCoreDate(String? source) {
  if (source == null) return null;
  final normalized = source.replaceFirst(
    RegExp(r'\s+UTC$', caseSensitive: false),
    'Z',
  );
  return DateTime.tryParse(normalized);
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
