import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import '../diagnostics/diagnostics_controller.dart';
import '../models/content_route.dart';
import '../models/discourse_user.dart';
import '../models/forum_workspace.dart';
import '../models/group_route.dart';
import '../models/notification_totals.dart';
import '../models/post.dart';
import '../models/sidebar.dart';
import '../models/topic.dart';
import '../models/user_card.dart';
import '../shell/composer_controller.dart';
import '../shell/post_action.dart';
import '../theme/d_icon.dart';
import 'composer_syntax.dart';
import 'notification_counters.dart';
import 'notification_feed_host.dart';
import 'notification_types.dart';
import 'plugin_data.dart';
import 'plugin_icon_catalog.dart';

export 'background_retention.dart';
export 'composer_syntax.dart';
export 'emoji_usage.dart';
export 'hashtag_kind.dart';
export 'live_channels.dart';
export 'notification_counters.dart';
export 'notification_feed_host.dart';
export 'notification_types.dart';
export 'plugin_data.dart';
export 'plugin_icon_catalog.dart';
export 'plugin_manifest.dart' show PluginId;
export 'shell_extensions.dart';
export 'topic_recommendation_source.dart';

/// Serializer field presence decides whether a feature exists on a record.
/// `/site/settings.json` only describes how to render it or what new values may
/// be offered. Config can arrive late or be refused, so using it as a feature
/// gate can allow a write which the record's guardian did not authorize.
abstract interface class SitePlugin implements PluginCapability {
  @override
  String get name;
}

abstract interface class IconCatalogPlugin {
  PluginIconCatalog get iconCatalog;
}

abstract interface class PluginRecord<T extends Object> {
  /// Written out rather than taken from the value's `runtimeType`, which would
  /// misfile private subclasses, or from [T], which is erased while walking the
  /// plugin list.
  PluginDataKey<T> get record;
}

abstract interface class SiteSettingsPlugin<T extends Object> {
  PluginDataPersistenceCodec<T> get siteSettingsCodec;

  T? readSiteSettings(Map<String, dynamic> json, String siteUrl);
}

/// Presence-sensitive fields (for example Assign's nullable permissions) are
/// interpreted here rather than flattened by [DiscourseUser].
abstract interface class CurrentUserPlugin<T extends Object> {
  PluginDataPersistenceCodec<T> get currentUserCodec;

  T? readCurrentUser(Map<String, dynamic> json, String siteUrl);
}

abstract interface class PluginSiteFeature {
  bool siteFeatureEnabled(PluginData siteSettings);
}

abstract interface class PluginCurrentUserFeature {
  bool currentUserFeatureEnabled(PluginData currentUser);
}

abstract interface class GroupRecordPlugin<T extends Object> {
  PluginDataKey<T> get groupRecord;

  T? readGroup(Map<String, dynamic> json, String siteUrl);
}

abstract interface class PostRecordPlugin<T extends Object>
    implements PluginRecord<T> {
  /// An absent field must stay null; an empty default would enable the feature.
  T? readPost(Map<String, dynamic> json, String siteUrl);

  /// Edit serializers do not all carry reader state. Reactions keeps the held
  /// record; Poll deliberately takes the incoming value, including null when
  /// its block was removed.
  T? mergeAfterPostEdit(T? held, T? incoming);
}

abstract interface class TopicRecordPlugin<T extends Object>
    implements PluginRecord<T> {
  /// A topic list row and a full topic response can carry different subsets of
  /// one feature's state, so the plugin owns their interpretation.
  T? readTopic(Map<String, dynamic> json, String siteUrl);
}

abstract interface class UserCardRecordPlugin<T extends Object>
    implements PluginRecord<T> {
  T? readUserCard(Map<String, dynamic> json, String siteUrl);
}

abstract interface class UserCardActionPlugin {
  List<Widget> userCardActions(
    BuildContext context,
    String siteUrl,
    UserCard user,
    VoidCallback close,
  );
}

@immutable
final class PluginUserMenuSectionId {
  const PluginUserMenuSectionId({required this.owner, required this.name});

  final PluginId owner;
  final String name;
  String get id => '${owner.value}/$name';

  @override
  bool operator ==(Object other) =>
      other is PluginUserMenuSectionId &&
      other.owner == owner &&
      other.name == name;

  @override
  int get hashCode => Object.hash(owner, name);
}

@immutable
final class PluginUserMenuContext {
  const PluginUserMenuContext({
    required this.siteUrl,
    required this.user,
    required this.totals,
  });

  final String siteUrl;
  final DiscourseUser user;
  final NotificationTotals? totals;

  int unreadCountFor(NotificationWireType type) {
    final live = totals?.groupedUnreadNotifications;
    if (live?.isAvailable == true) return live!.count(type);
    return user.groupedUnreadNotifications.count(type);
  }
}

@immutable
final class PluginUserMenuRenderContext {
  const PluginUserMenuRenderContext({required this.onDismiss});

  final VoidCallback onDismiss;
}

typedef PluginUserMenuSectionBuilder =
    Widget Function(BuildContext context, PluginUserMenuRenderContext actions);

@immutable
final class PluginUserMenuSection {
  const PluginUserMenuSection({
    required this.id,
    required this.icon,
    required this.label,
    required this.builder,
    this.badge = 0,
    this.linkWhenActive,
  });

  final PluginUserMenuSectionId id;
  final DIconData icon;
  final String label;
  final int badge;

  /// Relative forum path opened when an already-selected desktop tab is
  /// selected again. This mirrors Discourse's user-menu tab contract while
  /// leaving same-origin navigation and browser fallback with the shell.
  final String? linkWhenActive;
  final PluginUserMenuSectionBuilder builder;
}

abstract interface class UserMenuSectionPlugin {
  List<PluginUserMenuSection> userMenuSections(PluginUserMenuContext context);
}

abstract interface class NotificationFeedPlugin {
  List<PluginNotificationFeedSource> get notificationFeeds;
}

abstract interface class NotificationTypePlugin {
  List<PluginNotificationType> get notificationTypes;
}

abstract interface class NotificationCounterPlugin {
  List<PluginNotificationCounter> get notificationCounters;
}

@immutable
final class PluginContainingTopic {
  const PluginContainingTopic({
    required this.id,
    required this.slug,
    required this.archived,
  });

  final int id;
  final String slug;
  final bool archived;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PluginContainingTopic &&
          id == other.id &&
          slug == other.slug &&
          archived == other.archived;

  @override
  int get hashCode => Object.hash(id, slug, archived);
}

@immutable
final class PluginPostBodyContext {
  const PluginPostBodyContext({
    required this.buildContext,
    required this.siteUrl,
    required this.post,
    this.topic,
  });

  /// A context stamped with the contribution owner's service view.
  final BuildContext buildContext;
  final String siteUrl;
  final Post post;
  final PluginContainingTopic? topic;
}

abstract interface class PostBodyPlugin {
  /// Only top-level post markup reaches this hook; nested cooked fragments have
  /// no authoritative post serializer record.
  Widget? postBodyElement(PluginPostBodyContext context, dom.Element element);
}

/// Unlike [PostBodyPlugin], this also runs for chat and nested cooked fragments.
/// The first plugin to recognize an element owns it.
abstract interface class CookedElementPlugin {
  Widget? cookedElement(String? siteUrl, dom.Element element);
}

/// A normal cooked-element replacement becomes one indivisible [WidgetSpan].
/// Prefixes preserve the decorated element as wrapping text.
abstract interface class CookedInlinePlugin {
  CookedInlinePrefix? cookedInlinePrefix(dom.Element element);
}

@immutable
final class CookedInlinePrefix {
  const CookedInlinePrefix({
    required this.child,
    this.alignment = PlaceholderAlignment.middle,
    this.excludeLinkSemantics = false,
  });

  final Widget child;
  final PlaceholderAlignment alignment;

  /// Whether the link recognizer around [child] should be hidden from the
  /// semantics tree. Set this when the element's text already exposes the
  /// same named link and the prefix is only visual decoration.
  final bool excludeLinkSemantics;
}

abstract interface class PostFooterPlugin {
  /// Ordered fallthrough: the first non-null plugin replaces the core footer.
  Widget? postFooter(String siteUrl, Post post);
}

abstract interface class PostDecorationPlugin {
  /// Contributions are additive; topic state may decorate its opening post.
  List<Widget> postDecorations(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
    Post post,
  );
}

abstract interface class PostSmallActionPlugin {
  /// A non-null contribution is also the post-type classification signal.
  PluginSmallAction? smallAction(Post post);
}

@immutable
class PluginSmallAction {
  const PluginSmallAction({required this.icon, required this.phrase});

  final DIconData icon;
  final String phrase;
}

abstract interface class TopicListMetadataPlugin {
  List<Widget> topicListMetadata(
    BuildContext context,
    String siteUrl,
    Topic topic,
  );
}

enum TopicPropertySectionLayout { inline, standalone }

@immutable
final class TopicPropertySection {
  const TopicPropertySection({
    required this.label,
    required this.values,
    this.layout = TopicPropertySectionLayout.inline,
  });

  final String label;
  final List<Widget> values;
  final TopicPropertySectionLayout layout;
}

abstract interface class TopicPropertiesPlugin {
  List<TopicPropertySection> topicProperties(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  );
}

/// Invalidates transient contributions without replacing the topic record.
abstract interface class TopicPropertiesRebuildPlugin {
  Listenable? topicPropertiesRebuildOn(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  );
}

abstract interface class TopicMapActionPlugin {
  TopicMapActionContribution topicMapActions(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  );
}

@immutable
class TopicMapActionContribution {
  const TopicMapActionContribution({
    this.actions = const [],
    this.replacesSummary = false,
  });

  static const TopicMapActionContribution none = TopicMapActionContribution();

  final List<Widget> actions;

  final bool replacesSummary;
}

/// Each codec owns both its serializer decoding and presentation identity.
/// Registry order is presentation order.
abstract interface class TopicRecommendationSourcePlugin {
  List<TopicRecommendationSourceCodec> get topicRecommendationSourceCodecs;
}

abstract interface class PostMenuPlugin {
  PostMenuContribution postMenu(PostMenuContext context);
}

@immutable
final class PostMenuContext {
  const PostMenuContext({
    required this.buildContext,
    required this.siteUrl,
    required this.post,
    required this.topic,
    required this.currentUser,
  });

  final BuildContext buildContext;
  final String siteUrl;
  final Post post;
  final TopicDetail? topic;
  final DiscourseUser? currentUser;
}

abstract interface class ComposerToolbarPlugin {
  List<ComposerToolbarContribution> composerToolbar(
    BuildContext context,
    ComposerEditorHost editor,
  );
}

/// Resolves one exact, namespaced plugin composer target.
///
/// A capability claims a key rather than answering a predicate. This makes a
/// missing target fail closed and lets installation reject ambiguous owners
/// before a user has typed into a document.
abstract interface class ComposerTargetPlugin {
  ComposerTargetKind get composerTargetKind;

  ComposerTargetPolicy createComposerTarget(
    ComposerTargetRequest request,
    ComposerTargetContext context,
  );
}

@immutable
final class ComposerTargetContext {
  const ComposerTargetContext({
    required this.siteSettings,
    required this.currentUser,
  });

  final PluginData siteSettings;
  final PluginData currentUser;
}

abstract interface class SidebarPlugin {
  /// Additive model contributions, presented in registry order.
  List<SidebarSection> sidebarSections(BuildContext context);

  Listenable? sidebarListenable(BuildContext context);
}

abstract interface class ForumTabPlugin {
  SidebarDestination? forumTabDestination(
    BuildContext context,
    String siteUrl,
    ForumTab tab,
  );

  Listenable? forumTabListenable(BuildContext context, String siteUrl);
}

/// [groupData] and [currentUserData] stay opaque to core. A plugin reads only
/// its own typed keys.
@immutable
final class PluginGroupContext {
  const PluginGroupContext({
    required this.siteUrl,
    required this.route,
    required this.groupName,
    required this.canSeeMembers,
    required this.groupData,
    required this.currentUserData,
  });

  final String siteUrl;
  final GroupRoute route;
  final String groupName;
  final bool canSeeMembers;
  final PluginData groupData;
  final PluginData currentUserData;
}

@immutable
final class PluginGroupTab {
  const PluginGroupTab({
    required this.section,
    required this.label,
    required this.icon,
    this.count,
  });

  final String section;
  final String label;
  final DIconData icon;
  final int? count;
}

@immutable
final class OwnedPluginGroupTab {
  const OwnedPluginGroupTab({required this.owner, required this.tab});

  final PluginId owner;
  final PluginGroupTab tab;
}

abstract interface class GroupTabPlugin {
  PluginGroupTab? groupTab(PluginGroupContext group);

  Widget? groupContent(BuildContext context, PluginGroupContext group);

  Listenable? groupListenable(BuildContext context, PluginGroupContext group);
}

abstract interface class ContentPlugin {
  /// Ordered before core and matched by the id the plugin put in its sidebar
  /// destination. Unknown plugin routes therefore fall through to a placeholder.
  Widget? content(BuildContext context, ContentRoute route);
}

abstract interface class ContentSearchPlugin {
  bool ownsContentSearch(BuildContext context, ContentRoute route);

  /// Returns null when this route owns search but search is unavailable.
  VoidCallback? contentSearchAction(BuildContext context, ContentRoute route);
}

abstract interface class ContentChromePlugin {
  bool ownsContentChrome(BuildContext context, ContentRoute route);
}

abstract interface class ContentHeaderPlugin {
  List<Widget> contentHeaderActions(BuildContext context, ContentRoute route);
}

abstract interface class ContentHeaderLeadingPlugin {
  Widget? contentHeaderLeading(BuildContext context, ContentRoute route);
}

abstract interface class ContentHeaderTitlePlugin {
  VoidCallback? contentHeaderTitleAction(
    BuildContext context,
    ContentRoute route,
  );
}

enum PluginHeaderSurface { titleBar, content }

abstract interface class ShellHeaderPlugin {
  List<Widget> shellHeaderActions(
    BuildContext context, {
    required PluginHeaderSurface surface,
    required bool compact,
    Color? ringColor,
  });
}

abstract interface class ShellOverlayPlugin {
  List<Widget> shellOverlays(BuildContext context);
}

abstract interface class DiagnosticsPlugin {
  /// Stable identity used to preserve the selected diagnostics surface when
  /// the application replaces a plugin capability instance.
  String get diagnosticsId;

  String get diagnosticsLabel;

  Listenable get diagnosticsStatusListenable;

  bool get isDiagnosticsRecording;

  String? get diagnosticsRecordingLabel;

  Widget buildDiagnostics(
    BuildContext context,
    PluginDiagnosticsReadExportHost diagnostics,
  );
}

abstract interface class BookmarkReminderPlugin {
  DateTime? futureBookmarkReminder(
    String cooked, {
    required String? accountTimezone,
  });
}

abstract interface class TopicLivePlugin {
  List<String> topicChannels(int topicId);

  /// These messages carry invalidation hints, not authoritative counts.
  List<int> stalePosts(String channel, Object? data);
}

abstract interface class TopicLiveReloadPlugin {
  bool staleTopic(int topicId, String channel, Object? data);
}

@immutable
class PostMenuContribution {
  const PostMenuContribution({
    this.entries = const [],
    this.replacesLike = false,
    this.rebuildOn,
  });

  static const PostMenuContribution none = PostMenuContribution();

  final List<PostAction> entries;

  /// A feature which replaces Like semantics must suppress the core write path.
  final bool replacesLike;

  /// Listened to only while this post menu is rendered.
  final Listenable? rebuildOn;
}

@immutable
class ComposerToolbarContribution {
  const ComposerToolbarContribution({
    required this.icon,
    required this.label,
    required this.onInvoke,
  });

  final DIconData icon;
  final String label;
  final VoidCallback onInvoke;
}
