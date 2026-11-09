import 'dart:convert';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import 'chat_reader_time.dart';

// Discourse's vendor/assets/svg-icons/discourse-additional.svg.
const _threadIcon = DIconData(
  'discourse-threads',
  '<svg viewBox="0 0 16 17" fill-rule="evenodd" clip-rule="evenodd">'
      '<path d="M5 0L4.57143 3H1V5H4.28571L3.71429 9H0V11H3.42857L3 14L4.9799 14.2828L5.44888 11H7V9H5.73459L6.30602 5H11.2857L11 7H13.0203L13.306 5H16V3H13.5917L13.9799 0.282843L12 0L11.5714 3H6.59173L6.9799 0.282843L5 0ZM8 13.5V9C8 8.44772 8.44771 8 9 8H15C15.5523 8 16 8.44771 16 9V13.5C16 14.0523 15.5523 14.5 15 14.5H12.1194C11.5042 15.2014 10.396 16.3544 10.0417 16C9.97944 15.9223 9.99982 15.0667 10.0206 14.5H9C8.44771 14.5 8 14.0523 8 13.5Z"/>'
      '</svg>',
);

@immutable
class ChatTranscriptData {
  const ChatTranscriptData({
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.createdAt,
    required this.dateText,
    required this.sourceLink,
    required this.bodyHtml,
    required this.metaHtml,
    required this.parts,
    required this.threadTitleHtml,
    required this.threadLink,
  });

  final String? username, displayName, avatarUrl, dateText, sourceLink;
  final DateTime? createdAt;
  final String bodyHtml;
  final String? metaHtml;
  final List<ChatTranscriptPart> parts;
  Iterable<ChatTranscriptData> get replies =>
      parts.whereType<ChatTranscriptReply>().map((part) => part.message);
  final String? threadTitleHtml, threadLink;

  static ChatTranscriptData from(
    dom.Element element, {
    String? linkableChannel,
    String? parentThreadId,
  }) {
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
    final username = user == null
        ? null
        : descendantWhere(
            user,
            (candidate) =>
                candidate.classes.contains('chat-transcript-username'),
          );
    final datetime = user == null
        ? null
        : descendantWhere(
            user,
            (candidate) =>
                candidate.classes.contains('chat-transcript-datetime'),
          );
    final datetimeLink = _timestampLink(datetime);
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
    final title = _ownedDescendant(
      visible,
      (candidate) =>
          candidate.classes.contains('chat-transcript-thread-header__title'),
    );
    final titleLink = title == null
        ? null
        : descendantWhere(title, (candidate) => candidate.localName == 'a');
    final dateSource =
        element.attributes['data-datetime']?.nullIfEmpty ??
        datetimeLink?.attributes['title']?.nullIfEmpty ??
        datetime?.attributes['title']?.nullIfEmpty ??
        (datetime == null
            ? null
            : descendantWhere(
                datetime,
                (candidate) => candidate.attributes.containsKey('title'),
              )?.attributes['title']);
    final id = _positiveId(element.attributes['data-message-id']);
    final threadId = _positiveId(element.attributes['data-thread-id']);
    final source =
        datetimeLink?.attributes['href']?.nullIfEmpty ??
        (linkableChannel != null && id != null
            ? '$linkableChannel${parentThreadId == null ? '' : '/t/$parentThreadId'}/$id'
            : null);
    return ChatTranscriptData(
      username: element.attributes['data-username']?.nullIfEmpty,
      displayName:
          username?.text.trim().nullIfEmpty ??
          element.attributes['data-username']?.nullIfEmpty,
      avatarUrl: avatar?.attributes['src']?.nullIfEmpty,
      createdAt: _parseCoreDate(dateSource),
      dateText: datetime?.text.trim().nullIfEmpty ?? dateSource?.nullIfEmpty,
      sourceLink: source,
      metaHtml: meta?.innerHtml.trim().nullIfEmpty,
      bodyHtml: [
        ?messages?.innerHtml.trim().nullIfEmpty,
        ?images?.innerHtml.trim().nullIfEmpty,
      ].join('\n'),
      parts: _transcriptParts(
        element,
        excluded: [
          summary,
          user,
          messages,
          images,
          meta,
          _ownedDescendant(
            element,
            (candidate) =>
                candidate.classes.contains('chat-transcript-thread-header'),
          ),
        ],
        linkableChannel: linkableChannel,
        parentThreadId: threadId ?? parentThreadId,
      ),
      threadTitleHtml:
          title?.innerHtml.trim().nullIfEmpty ??
          switch (element.attributes['data-thread-title']?.nullIfEmpty) {
            final value? => const HtmlEscape().convert(value),
            null => null,
          },
      threadLink:
          titleLink?.attributes['href']?.nullIfEmpty ??
          (linkableChannel != null && threadId != null
              ? '$linkableChannel/t/$threadId'
              : null),
    );
  }
}

sealed class ChatTranscriptPart {
  const ChatTranscriptPart();
}

final class ChatTranscriptReply extends ChatTranscriptPart {
  const ChatTranscriptReply(this.message);
  final ChatTranscriptData message;
}

final class ChatTranscriptFragment extends ChatTranscriptPart {
  const ChatTranscriptFragment(this.html);
  final String html;
}

List<ChatTranscriptPart> _transcriptParts(
  dom.Element element, {
  required List<dom.Element?> excluded,
  required String? linkableChannel,
  required String? parentThreadId,
}) {
  final parts = <ChatTranscriptPart>[];
  final containers = <dom.Node>{};
  for (final field in excluded) {
    dom.Node? parent = field?.parentNode;
    while (parent != null && !identical(parent, element)) {
      containers.add(parent);
      parent = parent.parentNode;
    }
  }
  var fragment = dom.DocumentFragment();
  void flush() {
    final html = fragment.outerHtml.trim();
    if (html.isNotEmpty) parts.add(ChatTranscriptFragment(html));
    fragment = dom.DocumentFragment();
  }

  void visit(dom.Node node) {
    if (excluded.any((held) => identical(node, held))) return;
    if (node is dom.Element && _isTranscript(node)) {
      flush();
      parts.add(
        ChatTranscriptReply(
          ChatTranscriptData.from(
            node,
            linkableChannel: linkableChannel,
            parentThreadId: parentThreadId,
          ),
        ),
      );
    } else if (node is dom.Element &&
        (containers.contains(node) ||
            descendantsWhere(node, _isTranscript).isNotEmpty)) {
      for (final child in node.nodes) {
        visit(child);
      }
    } else {
      fragment.append(node.clone(true));
    }
  }

  for (final node in element.nodes) {
    visit(node);
  }
  flush();
  return List.unmodifiable(parts);
}

@immutable
class ChatTranscriptGroupData {
  const ChatTranscriptGroupData({
    required this.name,
    required this.channelLink,
    required this.fromChannel,
    required this.messages,
  });
  final String? name, channelLink;
  final bool fromChannel;
  final List<ChatTranscriptData> messages;

  static ChatTranscriptGroupData from(
    List<dom.Element> elements, {
    String? siteUrl,
  }) {
    final first = elements.first;
    final channel = first.attributes['data-channel-name']?.nullIfEmpty;
    final id = _positiveId(first.attributes['data-channel-id']);
    final user = _ownedDescendant(
      first,
      (candidate) => candidate.classes.contains('chat-transcript-datetime'),
    );
    final linked = _timestampLink(user) != null;
    final path = id == null
        ? null
        : siteUrl == null
        ? '/chat/c/-/$id'
        : resolveSiteRootPath(siteUrl, '/chat/c/-/$id');
    return ChatTranscriptGroupData(
      name: channel ?? first.attributes['data-source']?.nullIfEmpty,
      channelLink: channel == null ? null : path,
      fromChannel: channel != null,
      messages: List.unmodifiable([
        for (final element in elements)
          ChatTranscriptData.from(
            element,
            linkableChannel: linked ? path : null,
          ),
      ]),
    );
  }
}

Widget? chatTranscriptWidgetBuilder(dom.Element element, {String? siteUrl}) {
  if (element.classes.contains('chat-transcript-group')) {
    final transcripts = descendantsWhere(element, _isTranscript).where((
      candidate,
    ) {
      dom.Node? parent = candidate.parentNode;
      while (parent != null && !identical(parent, element)) {
        if (parent is dom.Element && _isTranscript(parent)) return false;
        parent = parent.parentNode;
      }
      return identical(parent, element);
    }).toList();
    if (transcripts.isEmpty) return null;
    return ChatTranscriptBlock(
      data: ChatTranscriptGroupData.from(transcripts, siteUrl: siteUrl),
      siteUrl: siteUrl,
    );
  }
  if (!_isTranscript(element)) return null;
  final previous = element.previousElementSibling;
  if (_isContinuation(element) && previous != null && _isTranscript(previous)) {
    return const SizedBox.shrink();
  }
  final elements = [element];
  var next = element.nextElementSibling;
  while (next != null && _isTranscript(next) && _isContinuation(next)) {
    elements.add(next);
    next = next.nextElementSibling;
  }
  return ChatTranscriptBlock(
    data: ChatTranscriptGroupData.from(elements, siteUrl: siteUrl),
    siteUrl: siteUrl,
  );
}

bool _isTranscript(dom.Element element) =>
    (element.localName == 'div' || element.localName == 'details') &&
    element.classes.contains('chat-transcript');

dom.Element? _timestampLink(dom.Element? timestamp) => timestamp == null
    ? null
    : childWhere(
        timestamp,
        (element) =>
            element.localName == 'a' &&
            !element.classes.contains('chat-transcript-channel'),
      );

bool _isContinuation(dom.Element element) =>
    (element.attributes['data-channel-name']?.isEmpty ?? true) &&
    (element.attributes['data-source']?.isEmpty ?? true);

String? _positiveId(String? value) {
  final id = value == null ? null : int.tryParse(value);
  return id != null && id > 0 ? '$id' : null;
}

class ChatTranscriptBlock extends StatelessWidget {
  const ChatTranscriptBlock({super.key, required this.data, this.siteUrl});
  final ChatTranscriptGroupData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: DPageReadingLane.maxWidth),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: DSpacing.sm),
        child: DCard(
          size: DCardSize.small,
          children: [
            if (data.name case final name?)
              DCardHeader(
                title: Wrap(
                  spacing: DSpacing.sm,
                  runSpacing: DSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DIcon(
                      data.fromChannel ? DIcons.hashtag : DIcons.comment,
                      size: 16,
                    ),
                    _TranscriptLink(
                      label: name,
                      href: data.channelLink,
                      siteUrl: siteUrl,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      context.l10n.chatTranscript,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            DCardContent(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 480),
                child: DScrollArea(
                  thumbVisibility: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: DSpacing.md,
                    children: [
                      for (final message in data.messages)
                        _TranscriptEntry(
                          data: message,
                          siteUrl: siteUrl,
                          showMeta: data.name == null,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TranscriptEntry extends StatelessWidget {
  const _TranscriptEntry({
    required this.data,
    required this.siteUrl,
    this.showMeta = true,
  });
  final ChatTranscriptData data;
  final String? siteUrl;
  final bool showMeta;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: DSpacing.sm,
    children: [
      if (showMeta && data.metaHtml != null)
        CookedHtml(html: data.metaHtml!, siteUrl: siteUrl, buildAsync: false),
      if (data.threadTitleHtml case final title?)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DSpacing.xs,
          children: [
            const DIcon(_threadIcon, size: 16),
            Expanded(
              child: data.threadLink == null
                  ? CookedHtml(html: title, siteUrl: siteUrl, buildAsync: false)
                  : _TranscriptLink(
                      label: jsonHtmlText(title) ?? '',
                      href: data.threadLink,
                      siteUrl: siteUrl,
                      style: Theme.of(context).textTheme.labelLarge,
                      rich: CookedHtml(
                        html: title,
                        siteUrl: siteUrl,
                        buildAsync: false,
                      ),
                    ),
            ),
          ],
        ),
      DMessage(
        avatarAlignment: DMessageAvatarAlignment.top,
        children: [
          DMessageAvatar(
            minimumExtent: 28,
            shiftForFooter: false,
            child: _TranscriptAvatar(data: data, siteUrl: siteUrl),
          ),
          DMessageContent(
            flushMetadata: true,
            spacing: DSpacing.xs,
            children: [
              _TranscriptHeader(data: data, siteUrl: siteUrl),
              if (data.bodyHtml.isNotEmpty)
                CookedHtml(
                  html: data.bodyHtml,
                  siteUrl: siteUrl,
                  textStyle: Theme.of(context).textTheme.bodyLarge,
                  compactParagraphs: true,
                  buildAsync: false,
                ),
            ],
          ),
        ],
      ),
      for (final part in data.parts)
        switch (part) {
          ChatTranscriptReply(:final message) => Padding(
            padding: const EdgeInsetsDirectional.only(start: DSpacing.md),
            child: _TranscriptEntry(data: message, siteUrl: siteUrl),
          ),
          ChatTranscriptFragment(:final html) => CookedHtml(
            html: html,
            siteUrl: siteUrl,
            compactParagraphs: true,
            buildAsync: false,
          ),
        },
    ],
  );
}

class _TranscriptAvatar extends StatelessWidget {
  const _TranscriptAvatar({required this.data, required this.siteUrl});
  final ChatTranscriptData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final avatar = DAvatar(
      dimension: 28,
      child: data.avatarUrl == null
          ? Text(data.displayName?.characters.firstOrNull ?? '')
          : AvatarImage(
              url: resolveSiteUrl(data.avatarUrl!, siteUrl),
              size: 28,
              fallback: const SizedBox.shrink(),
            ),
    );
    return data.username == null
        ? avatar
        : UserCardTarget.avatar(
            username: data.username!,
            siteUrl: siteUrl,
            child: avatar,
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
            siteUrl: siteUrl,
          ),
        if (dateText != null)
          _TranscriptLink(
            label: dateText,
            href: data.sourceLink,
            siteUrl: siteUrl,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
      ],
    );
  }

  String _formatDate(BuildContext context, DateTime value) {
    final local = chatTimeFor(context, siteUrl).local(value);
    final material = MaterialLocalizations.of(context);
    final date = material.formatShortMonthDay(local);
    return '$date, ${clockTimeLabel(context, local)}';
  }
}

class _Author extends StatelessWidget {
  const _Author({
    required this.username,
    required this.label,
    required this.siteUrl,
  });

  final String? username;
  final String? label;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
}

class _TranscriptLink extends StatelessWidget {
  const _TranscriptLink({
    required this.label,
    required this.href,
    required this.siteUrl,
    required this.style,
    this.rich,
  });

  final String label;
  final String? href;
  final String? siteUrl;
  final TextStyle? style;
  final Widget? rich;

  @override
  Widget build(BuildContext context) {
    final text = rich ?? Text(label, style: style);
    if (href == null) return text;

    return LinkTarget(
      url: href,
      siteUrl: siteUrl,
      child: DItem(
        fitContent: true,
        size: DItemSize.artwork,
        highlightOnInteraction: false,
        link: true,
        onPressed: () => openLink(context, href!, siteUrl: siteUrl),
        semanticLabel: label,
        children: [ExcludeSemantics(child: text)],
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
