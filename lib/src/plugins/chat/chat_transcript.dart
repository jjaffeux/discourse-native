import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

// Core's summary marker, drawn as a vector so it never depends on font coverage.
const _disclosureIcon = DIconData(
  'chat-transcript-disclosure',
  '<svg viewBox="0 0 16 16"><path d="M3 1v14l12-7z"/></svg>',
);

// Discourse's vendor/assets/svg-icons/discourse-additional.svg.
const _threadIcon = DIconData(
  'discourse-threads',
  '<svg viewBox="0 0 16 17" fill-rule="evenodd" clip-rule="evenodd">'
      '<path d="M5 0L4.57143 3H1V5H4.28571L3.71429 9H0V11H3.42857L3 14L4.9799 14.2828L5.44888 11H7V9H5.73459L6.30602 5H11.2857L11 7H13.0203L13.306 5H16V3H13.5917L13.9799 0.282843L12 0L11.5714 3H6.59173L6.9799 0.282843L5 0ZM8 13.5V9C8 8.44772 8.44771 8 9 8H15C15.5523 8 16 8.44771 16 9V13.5C16 14.0523 15.5523 14.5 15 14.5H12.1194C11.5042 15.2014 10.396 16.3544 10.0417 16C9.97944 15.9223 9.99982 15.0667 10.0206 14.5H9C8.44771 14.5 8 14.0523 8 13.5Z"/>'
      '</svg>',
);

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
    this.disclosure,
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
  final ChatTranscriptDisclosure? disclosure;

  static ChatTranscriptData from(dom.Element element) {
    // Core only wraps a thread in details when it includes replies. A thread
    // id alone also occurs on ordinary message quotes and must not collapse.
    final details = element.localName == 'details'
        ? element
        : childWhere(element, (child) => child.localName == 'details');
    final summary = details == null
        ? null
        : childWhere(details, (child) => child.localName == 'summary');
    final visible = summary ?? element;
    final user = _ownedDescendant(
      visible,
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
      visible,
      (candidate) => candidate.classes.contains('chat-transcript-messages'),
    );
    final images = _ownedDescendant(
      visible,
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
              !_isInside(candidate, images) &&
              (summary == null || !_isInside(candidate, details)))
            candidate.outerHtml,
      ],
      chained: element.classes.contains('chat-transcript-chained'),
      disclosure: details != null && summary != null
          ? ChatTranscriptDisclosure.from(details, summary)
          : null,
    );
  }
}

class ChatTranscriptDisclosure {
  const ChatTranscriptDisclosure({
    required this.titleHtml,
    required this.titleText,
    required this.bodyHtml,
    required this.open,
  });

  final String titleHtml;
  final String titleText;
  final String bodyHtml;
  final bool open;

  static ChatTranscriptDisclosure from(
    dom.Element details,
    dom.Element summary,
  ) {
    final title = _ownedDescendant(
      summary,
      (child) => child.classes.contains('chat-transcript-thread-header__title'),
    );
    final body = dom.Element.tag('div');
    for (final node in details.nodes) {
      if (!identical(node, summary)) body.append(node.clone(true));
    }
    return ChatTranscriptDisclosure(
      titleHtml: title?.innerHtml.trim() ?? '',
      titleText: title?.text.trim() ?? '',
      bodyHtml: body.innerHtml.trim(),
      open: details.attributes.containsKey('open'),
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
            DSeparator(color: theme.dividerColor),
            const SizedBox(height: 8),
          ],
          if (data.disclosure case final disclosure?)
            _TranscriptThread(
              data: data,
              disclosure: disclosure,
              siteUrl: siteUrl,
            )
          else
            _TranscriptMessage(data: data, siteUrl: siteUrl),
          for (final transcript in data.nestedTranscriptsHtml)
            CookedHtml(html: transcript, siteUrl: siteUrl),
        ],
      ),
    );
  }
}

class _TranscriptThread extends StatelessWidget {
  const _TranscriptThread({
    required this.data,
    required this.disclosure,
    required this.siteUrl,
  });

  final ChatTranscriptData data;
  final ChatTranscriptDisclosure disclosure;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DCollapsible(
      defaultOpen: disclosure.open,
      child: DCard(
        border: false,
        borderRadius: BorderRadius.zero,
        spacing: 0,
        backgroundColor: theme.colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DCollapsibleTrigger(
              interactiveChildren: true,
              semanticLabel: disclosure.titleText.isEmpty
                  ? context.l10n.thread
                  : disclosure.titleText,
              builder: (context, state) => Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    RotatedBox(
                      quarterTurns: state.open ? 1 : 0,
                      child: const DIcon(_disclosureIcon, size: 16),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 8,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 4,
                            children: [
                              const DIcon(_threadIcon, size: 18),
                              Expanded(
                                child: disclosure.titleHtml.isEmpty
                                    ? Text(context.l10n.thread)
                                    : CookedHtml(
                                        html: disclosure.titleHtml,
                                        siteUrl: siteUrl,
                                        textStyle: theme.textTheme.bodyLarge,
                                        buildAsync: false,
                                      ),
                              ),
                            ],
                          ),
                          _TranscriptMessage(data: data, siteUrl: siteUrl),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            DCollapsibleContent(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: CookedHtml(
                  html: disclosure.bodyHtml,
                  siteUrl: siteUrl,
                  buildAsync: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TranscriptMessage extends StatelessWidget {
  const _TranscriptMessage({required this.data, required this.siteUrl});

  final ChatTranscriptData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
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
          textStyle: Theme.of(context).textTheme.bodyLarge,
          compactParagraphs: true,
          buildAsync: false,
        ),
    ],
  );
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
    return '$date, ${clockTimeLabel(context, local)}';
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
          DAvatar.frame(
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
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
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

    return LinkTarget(
      url: href,
      siteUrl: siteUrl,
      child: InlineAction.link(
        onTap: () => openLink(context, href!, siteUrl: siteUrl),
        semanticLabel: label,
        excludeChildSemantics: true,
        child: text,
      ),
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
