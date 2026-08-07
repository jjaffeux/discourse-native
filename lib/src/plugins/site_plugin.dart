import 'package:flutter/widgets.dart';

import '../models/content_route.dart';
import '../models/post.dart';
import '../models/sidebar.dart';
import '../shell/post_action.dart';
import 'chat/chat_plugin.dart';
import 'reactions/reactions_plugin.dart';

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
/// costs no request. So [readPost] returning null means "this site did not
/// mention this feature", and everything else keys off that.
///
/// Site config — [SiteConfig], from `/site/settings.json` — answers the other
/// question, the one no record can: what may be *offered* that has not happened
/// yet. A picker's emoji list has no record behind it. Config must never gate
/// whether an affordance exists, because it arrives late and can be refused,
/// and a gate that is wrong for one frame produces a wrong *write* rather than
/// merely a missing button.
///
/// ## Adding one
///
/// A module under `lib/src/plugins/<name>/` owning its models, its state and
/// its widgets; an entry in [sitePlugins]; and its endpoints on `DiscourseApi`
/// beside everything else's. The endpoints are the one deliberate exception to
/// the module owning its own code: `FakeDiscourseApi implements DiscourseApi`
/// is what turns a new call into a compile error until the fake grows a knob
/// for it, and that is worth more than the tidier boundary.
///
/// This interface grows with what a plugin actually needs rather than ahead of
/// it. Hooks are added when the second implementation wants one, not in
/// anticipation of it.
abstract interface class SitePlugin<T extends Object> {
  /// The plugin's own name, `discourse-reactions`. For documentation and debug
  /// output; nothing dispatches on it.
  String get name;

  /// The type [readPost] answers with, and the key [PluginData.get] finds it
  /// under.
  ///
  /// Written out rather than taken from the value's `runtimeType`, which would
  /// quietly file a private subclass somewhere no reader looks, and rather than
  /// from [T], which is erased by the time [sitePlugins] is walked.
  Type get record;

  /// What this plugin added to a post payload, or null when the site did not
  /// mention it.
  ///
  /// Null is the whole answer to "this site does not have this feature", so it
  /// must be returned for an absent key rather than defaulted into an empty
  /// value — a default would claim the feature is present everywhere.
  T? readPost(Map<String, dynamic> json, String siteUrl);

  /// What to draw under a post in place of the core footer, or null to leave it
  /// alone.
  ///
  /// An ordered fallthrough, the same shape as `cooked_html.dart`'s builder
  /// chain and `open_link.dart`'s dispatch: the first plugin with something to
  /// say wins, and the core answer is what is left when none of them do.
  Widget? postFooter(Post post);

  /// What this feature adds to, or takes out of, the post action menu.
  ///
  /// Takes a [BuildContext] rather than the controller so that this interface
  /// stays out of the shell's way; an implementation reaches whatever it needs
  /// through `ShellScope.of`.
  PostMenuContribution postMenu(BuildContext context, Post post);

  /// Sections this feature adds to the instance sidebar, after core's own.
  ///
  /// Empty for a feature with no navigation of its own, which is every feature
  /// that only decorates a record.
  ///
  /// Additive rather than an ordered fallthrough — the shape [postMenu] has,
  /// and for the same reason: two features both having somewhere to navigate to
  /// is ordinary, two features both owning one spot is not. The order is the
  /// order of [sitePlugins].
  ///
  /// Models rather than a widget, unlike [postFooter], because the sidebar is a
  /// list of peers rather than a canvas. A row a plugin drew itself would drift
  /// from core's the first time either changed, and `selectedId` and
  /// `selectDestination` would decay from *the* path into a convention that
  /// happens to be followed. A post's footer is a free-form decoration on one
  /// record; this is not.
  ///
  /// The state behind these arrives asynchronously, so whatever holds it has to
  /// reach `ShellController._notify` — either by being shell state or, as chat
  /// does, by forwarding its own notifier to it.
  List<SidebarSection> sidebarSections(BuildContext context);

  /// The screen this feature draws for [route], or null for a route it does not
  /// own.
  ///
  /// The other half of [sidebarSections]: an entry the sidebar offers needs
  /// somewhere to lead, and the shell's own answer has only two branches — a
  /// topic, and a list of them.
  ///
  /// An ordered fallthrough like [postFooter], asked *before* core, so that a
  /// route belonging to a feature this build does not have falls through to the
  /// placeholder rather than to something unrelated that happens to be cached.
  ///
  /// Matched on [ContentRoute.id], which `ContentRoute.fromDestination` copies
  /// straight from the [SidebarDestination] this plugin minted — so a feature
  /// recognises its own routes by the ids it wrote. Nothing about any one
  /// feature is written into [ContentRoute], for the reason nothing about
  /// reactions is written into [Post]: core does not learn a plugin's
  /// vocabulary, it hands the plugin back what it was given.
  Widget? content(BuildContext context, ContentRoute route);

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

/// Every optional feature this build knows about, in the order they are asked.
///
/// A `const` list rather than something with a `register` method: every
/// implementation is reachable from go-to-definition, the order is written
/// down, and nothing can be added from somewhere surprising. These are modules
/// in this repo, not third-party bundles — there is nothing to discover.
const List<SitePlugin<Object>> sitePlugins = <SitePlugin<Object>>[
  ReactionsPlugin(),
  ChatPlugin(),
];

/// What plugins had to say about one record.
///
/// Parsed once, when the record is, rather than on every build: a post is
/// rebuilt whenever anything about it changes and re-reading JSON each time
/// would be work for an answer that cannot have moved.
///
/// Keyed by the value type each plugin returns, so reading it is
/// `post.plugins.get<Reactions>()` — a compile-time name rather than a string.
@immutable
class PluginData {
  const PluginData._(this._values);

  /// A record no plugin claimed, which is every record on a site that has none
  /// of them. Const, so it costs nothing to be the default.
  static const PluginData none = PluginData._(<Type, Object>{});

  final Map<Type, Object> _values;

  /// This plugin's answer for the record, or null when the site did not mention
  /// the feature. **This is the gate** — see [SitePlugin].
  T? get<T extends Object>() => _values[T] as T?;

  /// Asks every plugin what it makes of a post payload.
  ///
  /// Returns [none] when none of them claimed anything, so the common case —
  /// a site running plain core — allocates nothing per post.
  static PluginData forPost(Map<String, dynamic> json, String siteUrl) {
    Map<Type, Object>? values;
    for (final plugin in sitePlugins) {
      final value = plugin.readPost(json, siteUrl);
      if (value == null) continue;
      (values ??= <Type, Object>{})[plugin.record] = value;
    }
    return values == null ? none : PluginData._(values);
  }

  /// The same data with one plugin's answer replaced, or dropped when [value]
  /// is null.
  ///
  /// Both directions are ordinary: taking a reaction back replaces, and a site
  /// that has stopped serving a feature drops.
  PluginData withValue<T extends Object>(T? value) {
    final next = Map<Type, Object>.of(_values);
    if (value == null) {
      next.remove(T);
    } else {
      next[T] = value;
    }
    return next.isEmpty ? none : PluginData._(next);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PluginData || other._values.length != _values.length) {
      return false;
    }
    for (final entry in _values.entries) {
      if (other._values[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(_values.values);
}
