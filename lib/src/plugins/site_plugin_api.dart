import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import '../models/content_route.dart';
import '../models/post.dart';
import '../models/sidebar.dart';
import '../models/topic.dart';
import '../models/user_card.dart';
import '../shell/composer_controller.dart';
import '../shell/post_action.dart';
import '../theme/d_icon.dart';
import 'chat/chat_preview.dart';
import 'plugin_data.dart';

export 'plugin_data.dart';

/// One optional Discourse feature this app knows how to draw.
///
/// Discourse core is a floor, not a ceiling: a given site may have reactions,
/// solved, assign, chat — or none of them. This is where an app that has to
/// work on all of them keeps what it knows about one.
///
/// ## The rule
///
/// **The record decides whether a feature is drawn. Site config decides only
/// how to draw it, or what to offer inside it.**
///
/// `Plugin::Instance#add_to_serializer` defaults `respect_plugin_enabled: true`
/// server side, so a disabled plugin's attributes are simply *absent* from
/// every payload. That absence is the enablement signal, and it is a better one
/// than any setting: it is scoped by the same guardian that decided the rest of
/// the payload, it can never be stale relative to what is on screen, and it
/// costs no request. So a record reader returning null means "this site did not
/// mention this feature", and everything else keys off that.
///
/// Site config, from `/site/settings.json`, answers the other question, the one
/// no record can: what may be *offered* that has not happened yet. A picker's
/// emoji list has no record behind it. Config must never gate whether an
/// affordance exists, because it arrives late and can be refused, and a gate
/// that is wrong for one frame produces a wrong *write* rather than merely a
/// missing button.
///
/// A feature implements only the capability interfaces it actually contributes
/// to. The registry owns dispatch and ordering, so consumers do not need to
/// know which feature implements which capability and features do not carry a
/// collection of unrelated no-op methods.
abstract interface class SitePlugin implements PluginCapability {
  /// The plugin's own name, `discourse-reactions`. For documentation and debug
  /// output; nothing dispatches on it.
  @override
  String get name;
}

/// The typed key shared by a plugin's records.
abstract interface class PluginRecord<T extends Object> {
  /// The type a record reader answers with, and the key `PluginData.get` finds
  /// it under.
  ///
  /// Written out rather than taken from the value's `runtimeType`, which would
  /// quietly file a private subclass somewhere no reader looks, and rather than
  /// from [T], which is erased by the time the plugin list is walked.
  PluginDataKey<T> get record;
}

/// A feature record embedded in a post payload.
abstract interface class PostRecordPlugin<T extends Object>
    implements PluginRecord<T> {
  /// What this plugin added to a post payload, or null when the site did not
  /// mention it.
  ///
  /// Null is the whole answer to "this site does not have this feature", so it
  /// must be returned for an absent key rather than defaulted into an empty
  /// value — a default would claim the feature is present everywhere.
  T? readPost(Map<String, dynamic> json, String siteUrl);

  /// Chooses this plugin's record after a normal post edit response.
  ///
  /// Edit serializers do not all carry reader state. Reactions keeps the held
  /// record; Poll deliberately takes the incoming value, including null when
  /// its block was removed.
  T? mergeAfterPostEdit(T? held, T? incoming);
}

/// A feature record embedded in a topic or topic-list payload.
abstract interface class TopicRecordPlugin<T extends Object>
    implements PluginRecord<T> {
  /// What this plugin added to a topic payload, or null when the site did not
  /// mention it.
  ///
  /// A topic list row and a full topic response can carry different subsets of
  /// one feature's state, so the reader owns that distinction. Core merely
  /// preserves the typed answer on the record it came from.
  T? readTopic(Map<String, dynamic> json, String siteUrl);
}

/// A feature record embedded in the user-card payload.
///
/// User cards are intentionally parsed through the same installed registry as
/// posts and topics. Fields such as Chat's `can_chat_user` only exist when the
/// corresponding server plugin contributes them; keeping them opaque to core
/// preserves that ownership while still letting the native card expose the
/// feature's controls.
abstract interface class UserCardRecordPlugin<T extends Object>
    implements PluginRecord<T> {
  T? readUserCard(Map<String, dynamic> json, String siteUrl);
}

/// Adds controls to a user card.
///
/// The card owns the responsive controls region. Contributions are widgets so
/// a plugin can retain its own pending/error state while core controls only
/// their placement and ordering.
abstract interface class UserCardActionPlugin {
  List<Widget> userCardActions(
    BuildContext context,
    String siteUrl,
    UserCard user,
    VoidCallback close,
  );
}

/// Replaces a top-level element inside a post's cooked body.
abstract interface class PostBodyPlugin {
  /// A top-level element inside a post body this feature can replace.
  ///
  /// The owning post is deliberately available here: cooked plugin markup is
  /// often only a placeholder, while the personalized serializer record is
  /// authoritative. Recursive CookedHtml instances (quotes/oneboxes) receive
  /// no post and therefore never invoke this hook.
  Widget? postBodyElement(String siteUrl, Post post, dom.Element element);
}

/// Replaces plugin-owned cooked markup regardless of the containing record.
///
/// Unlike [PostBodyPlugin], this also runs for chat, oneboxes and other cooked
/// fragments. The first plugin to recognize an element owns it.
abstract interface class CookedElementPlugin {
  Widget? cookedElement(String? siteUrl, dom.Element element);
}

/// Claims the footer under a post.
abstract interface class PostFooterPlugin {
  /// What to draw under a post in place of the core footer, or null to leave it
  /// alone.
  ///
  /// An ordered fallthrough, the same shape as `cooked_html.dart`'s builder
  /// chain and `open_link.dart`'s dispatch: the first plugin with something to
  /// say wins, and the core answer is what is left when none of them do.
  Widget? postFooter(String siteUrl, Post post);
}

/// Adds content between a post's cooked body and its core footer.
abstract interface class PostDecorationPlugin {
  /// Decorations this feature contributes to [post], in visual order.
  ///
  /// [topic] is included because some server features attach state to the
  /// topic while presenting it beside the first post. Contributions are
  /// additive: several optional features can all have something to show.
  List<Widget> postDecorations(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
    Post post,
  );
}

/// Recognises and describes a plugin-owned small action in the post stream.
abstract interface class PostSmallActionPlugin {
  /// The one-line notice for [post], or null when this feature does not own it.
  ///
  /// Returning a contribution is also the classification signal. This lets a
  /// plugin recognise its serializer's post type and action codes together,
  /// without teaching the core [Post] model either value.
  PluginSmallAction? smallAction(Post post);
}

/// A plugin-owned small action's presentation.
@immutable
class PluginSmallAction {
  const PluginSmallAction({required this.icon, required this.phrase});

  final DIconData icon;
  final String phrase;
}

/// Adds compact metadata to a topic-list row.
abstract interface class TopicListMetadataPlugin {
  /// Metadata widgets placed alongside category, tags, counts and bump time.
  List<Widget> topicListMetadata(
    BuildContext context,
    String siteUrl,
    Topic topic,
  );
}

/// Adds actions or state to the header of an open topic.
abstract interface class TopicHeaderPlugin {
  /// Header widgets placed before core's reply action, in plugin order.
  List<Widget> topicHeader(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  );
}

/// Adds an action to the topic map beneath the opening post.
///
/// The map itself is core, while optional features such as Discourse AI attach
/// their own serializer-gated controls beside its reading time and summary.
abstract interface class TopicMapActionPlugin {
  List<Widget> topicMapActions(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  );
}

/// Contributes actions to a post menu.
abstract interface class PostMenuPlugin {
  /// What this feature adds to, or takes out of, the post action menu.
  ///
  /// Takes a [BuildContext] rather than the controller so that this interface
  /// stays out of the shell's way; an implementation reaches whatever it needs
  /// through `ShellScope.read` and selects any state that must repaint.
  PostMenuContribution postMenu(
    BuildContext context,
    String siteUrl,
    Post post,
  );
}

/// Contributes formatting actions to the composer.
abstract interface class ComposerToolbarPlugin {
  /// Formatting actions this feature contributes to an open composer.
  List<ComposerToolbarContribution> composerToolbar(
    BuildContext context,
    ComposerController composer,
  );
}

/// Contributes conservative, app-bundled syntax to optimistic chat previews.
///
/// Inspection is pure and returns typed claims or blockers. Rendering remains
/// a separate capability so the preview document never stores a Widget or
/// locally generated HTML. Server-only plugins cannot implement this Dart
/// interface and therefore remain literal source until canonical cooking
/// arrives.
abstract interface class ChatMessagePreviewPlugin
    implements SitePlugin, ChatPreviewPluginAdapter {
  @override
  String get previewFeatureId;

  @override
  ChatPreviewInspection inspect(ChatPreviewRequest request);

  Widget? buildPreviewNode(BuildContext context, PluginPreviewNode node);
}

/// Contributes navigation sections to the instance sidebar.
abstract interface class SidebarPlugin {
  /// Sections this feature adds to the instance sidebar, after core's own.
  ///
  /// Empty for a feature with no navigation of its own, which is every feature
  /// that only decorates a record.
  ///
  /// Additive rather than an ordered fallthrough — the shape
  /// [PostMenuPlugin.postMenu] has, and for the same reason: two features both
  /// having somewhere to navigate to is ordinary, two features both owning one
  /// spot is not. The order is the order of the registry's plugin list.
  ///
  /// Models rather than a widget, unlike [PostFooterPlugin.postFooter], because
  /// the sidebar is a list of peers rather than a canvas. A row a plugin drew
  /// itself would drift from core's the first time either changed, and
  /// `selectedId` and `selectDestination` would decay from *the* path into a
  /// convention that happens to be followed. A post's footer is a free-form
  /// decoration on one record; this is not.
  ///
  /// The state behind these can arrive asynchronously. [sidebarListenable]
  /// identifies the feature-owned state the sidebar should rebuild for.
  List<SidebarSection> sidebarSections(BuildContext context);

  /// State that can change [sidebarSections], or null for a static contribution.
  Listenable? sidebarListenable(BuildContext context);
}

/// Claims a content route.
abstract interface class ContentPlugin {
  /// The screen this feature draws for [route], or null for a route it does not
  /// own.
  ///
  /// The other half of [SidebarPlugin.sidebarSections]: an entry the sidebar
  /// offers needs somewhere to lead, and the shell's own answer has only two
  /// branches — a topic, and a list of them.
  ///
  /// An ordered fallthrough like [PostFooterPlugin.postFooter], asked *before*
  /// core, so that a route belonging to a feature this build does not have
  /// falls through to the placeholder rather than to something unrelated that
  /// happens to be cached.
  ///
  /// Matched on [ContentRoute.id], which `ContentRoute.fromDestination` copies
  /// straight from the [SidebarDestination] this plugin minted — so a feature
  /// recognises its own routes by the ids it wrote. Nothing about any one
  /// feature is written into [ContentRoute], for the reason nothing about
  /// reactions is written into [Post]: core does not learn a plugin's
  /// vocabulary, it hands the plugin back what it was given.
  Widget? content(BuildContext context, ContentRoute route);
}

/// Lets a plugin-owned screen replace the shell's standard content header.
///
/// Most screens keep the common Back, title, search, and topic actions. A
/// richer nested screen can opt out route by route and draw that chrome as
/// part of its own responsive layout without teaching the shell its routing
/// vocabulary.
abstract interface class ContentChromePlugin {
  /// True when this plugin draws all chrome above [route]'s content itself.
  bool ownsContentChrome(BuildContext context, ContentRoute route);
}

/// Adds route-scoped actions to the shell's standard content header.
abstract interface class ContentHeaderPlugin {
  List<Widget> contentHeaderActions(BuildContext context, ContentRoute route);
}

enum PluginHeaderSurface { titleBar, content }

/// Adds app-level actions without teaching core which plugin owns them.
abstract interface class ShellHeaderPlugin {
  List<Widget> shellHeaderActions(
    BuildContext context, {
    required PluginHeaderSurface surface,
    required bool compact,
    Color? ringColor,
  });
}

/// Adds an app-global overlay above the adaptive shell.
abstract interface class ShellOverlayPlugin {
  List<Widget> shellOverlays(BuildContext context);
}

/// Adds topic-scoped message-bus subscriptions and invalidation hints.
abstract interface class TopicLivePlugin {
  /// The message_bus channels worth listening to while [topicId] is the topic
  /// on screen. Empty for a feature with nothing live about it.
  List<String> topicChannels(int topicId);

  /// Which posts a message on one of those channels says are out of date.
  ///
  /// An invalidation hint rather than a payload, because that is what these
  /// channels carry — the reactions one names the emoji that changed and no
  /// counts at all. Answering with ids rather than acting keeps this pure and
  /// lets the shell do the reading through the one path whose numbers are
  /// right.
  List<int> stalePosts(String channel, Object? data);
}

/// Marks the full topic serializer stale after a topic-scoped live message.
///
/// Kept separate from [TopicLivePlugin] so existing post-only live features do
/// not acquire a meaningless method. A feature that uses it also implements
/// [TopicLivePlugin] to name the channel that carries the invalidation.
abstract interface class TopicLiveReloadPlugin {
  /// Whether [data] says the open [topicId] must be fetched again.
  bool staleTopic(int topicId, String channel, Object? data);
}

/// A plugin's share of the post action menu.
@immutable
class PostMenuContribution {
  const PostMenuContribution({
    this.entries = const [],
    this.replacesLike = false,
  });

  /// For a feature with nothing to say about this post.
  static const PostMenuContribution none = PostMenuContribution();

  /// What to offer, in the order it should appear.
  final List<PostAction> entries;

  /// Whether the core Like entry must give way to [entries].
  ///
  /// Named after what Discourse's own client does — `dag.replace(LIKE, …)` —
  /// because it is the same idea and for the same reason: where a feature has
  /// taken over what a like *means*, offering the plain one writes to the wrong
  /// place. A feature that only adds does not set this.
  final bool replacesLike;
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
