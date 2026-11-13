import 'dart:convert';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;

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
    if (node is dom.Element && isChatTranscript(node)) {
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
            descendantsWhere(node, isChatTranscript).isNotEmpty)) {
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

bool isChatTranscript(dom.Element element) =>
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

String? _positiveId(String? value) {
  final id = value == null ? null : int.tryParse(value);
  return id != null && id > 0 ? '$id' : null;
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
