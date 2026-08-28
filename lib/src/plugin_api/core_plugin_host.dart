import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext, Widget;

import '../data/discourse_api_contracts.dart';
import '../data/plugin_transport.dart';
import '../models/discourse_user.dart';
import '../models/notification_totals.dart';
import '../models/post.dart';
import '../models/post_flag.dart';
import '../models/site_config.dart';
import '../models/site_emoji.dart';
import '../shell/composer_controller.dart';
import 'bookmark_host.dart';
import 'chat_preview.dart';
import 'discourse_model_codec.dart';
import 'emoji_preferences.dart';
import 'notification_feed_host.dart';
import 'plugin_data.dart';
import 'plugin_manifest.dart';
import 'shell_extensions.dart';

typedef PluginCurrentUserReader = DiscourseUser? Function(String siteUrl);
typedef PluginSiteConfigReader = SiteConfig Function(String siteUrl);
typedef PluginSiteConfigListenableReader =
    ValueListenable<SiteConfig> Function(String siteUrl);
typedef PluginTotalsFold =
    NotificationTotals Function(NotificationTotals current);
typedef PluginTotalsUpdater =
    void Function(String siteUrl, PluginTotalsFold fold);
typedef PluginSiteCallback = void Function(String siteUrl);
typedef PluginUserIdReader = int? Function(String siteUrl);
typedef PluginSiteConfigResolver = Future<SiteConfig?> Function(String siteUrl);
typedef PluginTopicReloader =
    Future<void> Function(String siteUrl, int topicId);
typedef PluginTargetSnapshot<T extends Object> = ({bool valid, T? value});
typedef PluginTrackingSync = void Function();
typedef PluginCurrentSiteReader = String? Function();
typedef PluginPostFlagCatalogReader =
    List<PostFlagType> Function(String siteUrl);
typedef PluginWriteCredential = ({String? apiKey, WriteException? failure});
typedef PluginComposerBuilder =
    ComposerController? Function(ComposerTargetRequest request);
typedef PluginEmojiCatalogLoader =
    Future<SiteEmojiCatalog?> Function(String siteUrl, {bool refresh});
typedef PluginEmojiSearchAliasLoader =
    Future<Map<String, List<String>>?> Function(String siteUrl, {bool refresh});
typedef PluginPreviewNodeBuilder =
    Widget? Function(BuildContext context, PluginPreviewNode node);

/// Read-only request credentials for one explicitly named site.
///
/// Plugins receive this snapshot instead of the process-wide credential
/// reader, so they cannot retain the authenticator or ask for a client id
/// independently of the site request they are about to make.
@immutable
final class PluginRequestCredentials {
  const PluginRequestCredentials({
    required this.apiKey,
    required this.clientId,
  });

  final String? apiKey;
  final String clientId;
}

/// Permission to publish synchronous state for one captured site session.
abstract interface class PluginSiteLease {
  bool get isCurrent;
  bool commit(VoidCallback mutation);
}

/// Least-privilege request and session-lifetime authority for plugins.
abstract interface class PluginRequestHost {
  PluginSiteLease capture(String siteUrl);

  Future<PluginRequestCredentials> credentialsFor(String siteUrl);

  Future<PluginWriteCredential> writeCredentialFor(String siteUrl);
}

/// The only account mutation a plugin-owned signed-out affordance may invoke.
///
/// Connection remains a host workflow (it presents the platform authorisation
/// UI and rotates the account session). Plugins can neither disconnect an
/// account nor select another forum through this port.
abstract interface class PluginAccountConnectionHost {
  bool isConnected(String siteUrl);

  /// Connects [siteUrl] when it is the host's currently presented forum and
  /// returns the user-facing failure, if any.
  Future<String?> connect(String siteUrl);
}

/// The shared post state needed by Poll and Reactions interactions.
///
/// This is intentionally not a generic [Store]. It grants access only to core
/// post/topic records and to the one serialized post-write lane used by those
/// plugins.
abstract interface class PluginPostHost {
  Post? readPost(String siteUrl, int postId);
  bool topicArchived(String siteUrl, int topicId);

  void updatePluginRecord<T extends Object>(
    String siteUrl,
    int postId,
    PluginDataKey<T> key,
    T? Function(T? held) update,
  );

  bool beginWrite(String siteUrl, int postId);
  void endWrite(String siteUrl, int postId);
  bool writeInFlight(String siteUrl, int postId);

  Future<void> refreshPost({
    required String siteUrl,
    required int topicId,
    required int postId,
    required String? apiKey,
    required PluginSiteLease lease,
  });
}

/// A plugin-neutral reference to a serializer-backed topic or post target.
final class PluginTarget {
  const PluginTarget.topic(this.id) : kind = 'topic', topicId = id;

  const PluginTarget.post(this.id, {required this.topicId}) : kind = 'post';

  final String kind;
  final int id;
  final int topicId;
}

/// Read-only account and presentation state used by Chat's session services.
final class PluginSiteStateHost {
  const PluginSiteStateHost({
    required this.currentUserFor,
    required this.siteConfigFor,
  });

  final PluginCurrentUserReader currentUserFor;
  final PluginSiteConfigReader siteConfigFor;
}

/// Account-level events emitted by a plugin-owned background controller.
final class PluginAccountEventsHost {
  const PluginAccountEventsHost({
    required this.updateTotals,
    required this.markSiteUnreachable,
  });

  final PluginTotalsUpdater updateTotals;
  final PluginSiteCallback markSiteUnreachable;
}

/// The projection and rendering seam needed by Chat's optimistic preview.
///
/// Chat can inspect only the declared preview adapters and ask core to render
/// one typed node. It never receives the application-wide plugin registry;
/// the registry remains responsible for invoking the selected renderer with
/// that renderer's owner-scoped UI context.
@immutable
final class PluginPreviewHost {
  PluginPreviewHost({
    required Iterable<ChatPreviewPluginAdapter> plugins,
    required this.buildNode,
  }) : plugins = List<ChatPreviewPluginAdapter>.unmodifiable(plugins);

  final List<ChatPreviewPluginAdapter> plugins;
  final PluginPreviewNodeBuilder buildNode;
}

/// Owner-scoped serializer snapshots used by target-based plugins.
///
/// The shell validates the target and returns only the namespaced record owned
/// by the consuming plugin. Foreign plugin data never crosses this port.
abstract interface class PluginTargetHost {
  PluginTargetSnapshot<T> recordFor<T extends Object>(
    String siteUrl,
    PluginTarget target,
    PluginDataKey<T> key,
  );
}

/// Fresh account presentation fields which are safe for plugin UI policy.
@immutable
final class PluginFreshAccountProfile {
  PluginFreshAccountProfile({required this.staff, required List<String> groups})
    : groups = List<String>.unmodifiable(groups);

  final bool staff;
  final List<String> groups;
}

/// Owner-scoped view of the freshly authenticated account.
///
/// Plugins can read their own current-user record plus the presentation fields
/// needed by feature UI. Other plugin namespaces and core account authority
/// remain host-owned.
abstract interface class PluginFreshAccountHost {
  PluginFreshAccountProfile? profileFor(String siteUrl);

  T? recordFor<T extends Object>(String siteUrl, PluginDataKey<T> key);
}

/// Topic reconciliation after a plugin-owned mutation.
final class PluginTopicRefreshHost {
  const PluginTopicRefreshHost({required this.reloadTopic});

  final PluginTopicReloader reloadTopic;
}

/// The writing environment needed by a plugin-owned composer widget.
///
/// This facade deliberately exposes no navigation, topic mutation, or shell
/// state. [siteConfigListenableFor] exposes only the configuration for the
/// composer's own site rather than a broad shell change signal. The core port
/// scopes [buildComposer] to target kinds owned by the consuming plugin.
final class PluginComposerHost {
  const PluginComposerHost({
    required this.buildComposer,
    required this.isActive,
    required this.siteConfigFor,
    required this.siteConfigListenableFor,
  });

  final PluginComposerBuilder buildComposer;
  final bool Function(ComposerController composer) isActive;
  final PluginSiteConfigReader siteConfigFor;
  final PluginSiteConfigListenableReader siteConfigListenableFor;
}

/// Catalog and preference operations shared by plugin-owned emoji pickers.
final class PluginEmojiHost {
  const PluginEmojiHost({
    required this.preferences,
    required this.siteConfigFor,
    required this.loadCatalog,
    required this.loadSearchAliases,
  });

  final EmojiPreferenceStore preferences;
  final PluginSiteConfigReader siteConfigFor;
  final PluginEmojiCatalogLoader loadCatalog;
  final PluginEmojiSearchAliasLoader loadSearchAliases;
}

const corePluginTransportPort = PluginHostPortKey<PluginApiTransport>(
  owner: PluginId('core'),
  name: 'transport',
);

const corePluginModelCodecPort = PluginHostPortKey<DiscourseModelCodec>(
  owner: PluginId('core'),
  name: 'model-codec',
);

const corePluginRequestPort = PluginHostPortKey<PluginRequestHost>(
  owner: PluginId('core'),
  name: 'requests',
);

const corePluginPostPort = PluginHostPortKey<PluginPostHost>(
  owner: PluginId('core'),
  name: 'posts',
);

const corePluginAccountConnectionPort =
    PluginHostPortKey<PluginAccountConnectionHost>(
      owner: PluginId('core'),
      name: 'account-connection',
    );

const corePluginSiteStatePort = PluginHostPortKey<PluginSiteStateHost>(
  owner: PluginId('core'),
  name: 'site-state',
);

const corePluginCurrentSitePort = PluginHostPortKey<PluginCurrentSiteReader>(
  owner: PluginId('core'),
  name: 'current-site',
);

const corePluginPostFlagCatalogPort =
    PluginHostPortKey<PluginPostFlagCatalogReader>(
      owner: PluginId('core'),
      name: 'post-flag-catalog',
    );

const corePluginPreviewPort = PluginHostPortKey<PluginPreviewHost>(
  owner: PluginId('core'),
  name: 'preview',
);

const corePluginAccountEventsPort = PluginHostPortKey<PluginAccountEventsHost>(
  owner: PluginId('core'),
  name: 'account-events',
);

const corePluginTargetPort = PluginHostPortKey<PluginTargetHost>(
  owner: PluginId('core'),
  name: 'target',
);

const corePluginFreshAccountPort = PluginHostPortKey<PluginFreshAccountHost>(
  owner: PluginId('core'),
  name: 'fresh-account',
);

const corePluginTopicRefreshPort = PluginHostPortKey<PluginTopicRefreshHost>(
  owner: PluginId('core'),
  name: 'topic-refresh',
);

const corePluginChannelPort = PluginHostPortKey<PluginChannelReader>(
  owner: PluginId('core'),
  name: 'channels',
);

const corePluginUserPort = PluginHostPortKey<PluginUserIdReader>(
  owner: PluginId('core'),
  name: 'user',
);

const corePluginPresentationPort = PluginHostPortKey<PluginSiteConfigResolver>(
  owner: PluginId('core'),
  name: 'presentation',
);

const corePluginTrackingSyncPort = PluginHostPortKey<PluginTrackingSync>(
  owner: PluginId('core'),
  name: 'tracking-sync',
);

const corePluginNavigationPort = PluginHostPortKey<PluginNavigationHost>(
  owner: PluginId('core'),
  name: 'navigation',
);

const corePluginRouteNavigationPort =
    PluginHostPortKey<PluginRouteNavigationHost>(
      owner: PluginId('core'),
      name: 'route-navigation',
    );

const corePluginBookmarkPort = PluginHostPortKey<PluginBookmarkHostFactory>(
  owner: PluginId('core'),
  name: 'bookmarks',
);

const corePluginComposerPort = PluginHostPortKey<PluginComposerHost>(
  owner: PluginId('core'),
  name: 'composer',
);

const corePluginEmojiPort = PluginHostPortKey<PluginEmojiHost>(
  owner: PluginId('core'),
  name: 'emoji',
);

const corePluginNotificationFeedPort =
    PluginHostPortKey<PluginNotificationFeedHost>(
      owner: PluginId('core'),
      name: 'notification-feed',
    );
