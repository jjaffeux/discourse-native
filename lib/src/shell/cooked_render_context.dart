import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../models/post.dart';
import '../models/post_checklist.dart';
import '../models/user_status.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/site_plugin_api.dart';
import 'cooked_document.dart';

abstract interface class CookedActions {
  Future<bool> openUrl(String url, {bool newTab = false});
  Future<void> toggleChecklist(PostChecklistTarget target, bool checked);
}

/// Resolved once by the root; nested content keeps its document and action ports.
@immutable
final class CookedRenderContext {
  CookedRenderContext({
    required this.document,
    required this.siteUrl,
    required this.post,
    required this.topic,
    required this.registry,
    required this.linkStyle,
    required this.revisionDiff,
    required this.canToggle,
    required this.actions,
    required Map<String, UserStatusReference> mentionedUserStatuses,
  }) : body = CookedBodyDependencies(
         siteUrl: siteUrl,
         post: post,
         topic: topic,
         registry: registry,
         linkStyle: linkStyle,
         revisionDiff: revisionDiff,
         canToggle: canToggle,
         checklist: document.checklist,
         mentionedUserStatuses: mentionedUserStatuses,
       );

  final CookedDocument document;
  final String? siteUrl;
  final Post? post;
  final PluginContainingTopic? topic;
  final PluginRegistry registry;
  final TextStyle? linkStyle;
  final bool revisionDiff;
  final bool canToggle;
  final CookedActions actions;
  final CookedBodyDependencies body;
}

/// Only facts read by body rendering participate in equality. Whole Post instances,
/// callbacks and unrelated plugin records must not invalidate a cached body.
@immutable
final class CookedBodyDependencies {
  CookedBodyDependencies({
    required String? siteUrl,
    required Post? post,
    required PluginContainingTopic? topic,
    required PluginRegistry registry,
    required TextStyle? linkStyle,
    required bool revisionDiff,
    required bool canToggle,
    required PostChecklistDocument? checklist,
    required Map<String, UserStatusReference> mentionedUserStatuses,
  }) : _facts = (
         siteUrl,
         registry,
         topic,
         post?.id,
         post?.postNumber,
         post?.canEdit,
         post?.isLocalized,
         post?.isDeleted,
         canToggle,
         linkStyle,
         revisionDiff,
       ),
       _records = List.unmodifiable(
         registry.postBodyRecords(post?.plugins ?? PluginData.none),
       ),
       linkCounts = List.unmodifiable(post?.linkCounts ?? const []),
       mentionedUserStatuses = Map.unmodifiable(mentionedUserStatuses),
       _targets = List.unmodifiable([
         for (final target in checklist?.targets ?? <PostChecklistTarget>[])
           (
             target.index,
             target.count,
             target.checked,
             target.permanent,
             target.source,
           ),
       ]);

  final (
    String?,
    PluginRegistry,
    PluginContainingTopic?,
    int?,
    int?,
    bool?,
    bool?,
    bool?,
    bool,
    TextStyle?,
    bool,
  )
  _facts;
  final List<Object?> _records;
  final List<(int, int, bool, bool, String?)> _targets;
  final List<PostLinkCount> linkCounts;
  final Map<String, UserStatusReference> mentionedUserStatuses;

  @override
  bool operator ==(Object other) =>
      other is CookedBodyDependencies &&
      _facts == other._facts &&
      listEquals(_records, other._records) &&
      listEquals(_targets, other._targets) &&
      listEquals(linkCounts, other.linkCounts) &&
      mapEquals(mentionedUserStatuses, other.mentionedUserStatuses);

  @override
  int get hashCode => Object.hash(
    _facts,
    Object.hashAll(_records),
    Object.hashAll(_targets),
    Object.hashAll(linkCounts),
    Object.hashAllUnordered([
      for (final entry in mentionedUserStatuses.entries)
        Object.hash(entry.key, entry.value),
    ]),
  );
}

/// HtmlWidget additionally compares its own HTML/base URL/parsing options.
/// This snapshot covers everything captured by our custom builders.
typedef CookedRenderInputs = ({
  CookedBodyDependencies body,
  TextStyle? style,
  TextScaler textScaler,
  Locale locale,
  TextDirection direction,
  String searchWords,
  Color searchColor,
  Color mutedForeground,
  RenderMode renderMode,
  bool compactParagraphs,
  bool contentSized,
  String horizontalRuleColor,
  String? insertedBackground,
  String? deletedBackground,
  String linkCountBackground,
  String linkCountForeground,
});
