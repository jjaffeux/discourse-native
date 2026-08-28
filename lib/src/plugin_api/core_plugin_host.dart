import 'package:flutter/foundation.dart';

import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/plugin_transport.dart';
import '../data/site_lifecycle.dart';
import '../data/site_tracker.dart';
import '../data/store.dart';
import '../models/discourse_user.dart';
import '../models/notification_totals.dart';
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
typedef PluginTrackerReader = SiteTracker? Function(String siteUrl);
typedef PluginUserIdReader = int? Function(String siteUrl);
typedef PluginSiteConfigResolver = Future<SiteConfig?> Function(String siteUrl);
typedef PluginTopicReloader =
    Future<void> Function(String siteUrl, int topicId);
typedef PluginTargetSnapshot = ({bool valid, PluginData data});
typedef PluginTargetDataReader =
    PluginTargetSnapshot Function(String siteUrl, PluginTarget target);
typedef PluginTrackingSync = void Function();
typedef PluginWriteCredential = ({String? apiKey, WriteException? failure});
typedef PluginComposerBuilder =
    ComposerController? Function(ComposerTargetRequest request);
typedef PluginEmojiCatalogLoader =
    Future<SiteEmojiCatalog?> Function(String siteUrl, {bool refresh});
typedef PluginEmojiSearchAliasLoader =
    Future<Map<String, List<String>>?> Function(String siteUrl, {bool refresh});

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

/// Serializer snapshots and permission fallback used by target-based plugins.
///
/// This is deliberately separate from topic refresh. A plugin that only needs
/// to refresh a known topic does not receive permission or record inspection.
final class PluginTargetHost {
  const PluginTargetHost({
    required this.dataForTarget,
    required this.freshCurrentUserFor,
  });

  final PluginTargetDataReader dataForTarget;
  final PluginCurrentUserReader freshCurrentUserFor;
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
    required this.credentials,
    required this.lifecycle,
    required this.siteConfigFor,
    required this.siteConfigListenableFor,
  });

  final PluginComposerBuilder buildComposer;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
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

const corePluginCredentialsPort = PluginHostPortKey<ApiCredentialReader>(
  owner: PluginId('core'),
  name: 'credentials',
);

const corePluginStorePort = PluginHostPortKey<Store>(
  owner: PluginId('core'),
  name: 'record-store',
);

const corePluginSiteLifecyclePort = PluginHostPortKey<SiteLifecycle>(
  owner: PluginId('core'),
  name: 'site-lifecycle',
);

const corePluginSiteStatePort = PluginHostPortKey<PluginSiteStateHost>(
  owner: PluginId('core'),
  name: 'site-state',
);

const corePluginPreviewPort = PluginHostPortKey<List<ChatPreviewPluginAdapter>>(
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

const corePluginTopicRefreshPort = PluginHostPortKey<PluginTopicRefreshHost>(
  owner: PluginId('core'),
  name: 'topic-refresh',
);

const corePluginTrackerPort = PluginHostPortKey<PluginTrackerReader>(
  owner: PluginId('core'),
  name: 'tracker',
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
