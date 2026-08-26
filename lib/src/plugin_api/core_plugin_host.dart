import '../data/api_credentials.dart';
import '../data/discourse_api.dart';
import '../data/site_lifecycle.dart';
import '../data/site_tracker.dart';
import '../data/store.dart';
import '../models/discourse_user.dart';
import '../models/site_config.dart';
import 'chat_preview.dart';
import 'plugin_data.dart';
import 'plugin_manifest.dart';
import 'plugin_runtime.dart';
import 'shell_extensions.dart';

typedef PluginCurrentUserReader = DiscourseUser? Function(String siteUrl);
typedef PluginSiteConfigReader = SiteConfig Function(String siteUrl);
typedef PluginCountDelta = void Function(String siteUrl, int delta);
typedef PluginSiteCallback = void Function(String siteUrl);
typedef PluginTrackerReader = SiteTracker? Function(String siteUrl);
typedef PluginUserIdReader = int? Function(String siteUrl);
typedef PluginCapabilityReader =
    Future<bool?> Function(String siteUrl, String capability);
typedef PluginTopicReloader =
    Future<void> Function(String siteUrl, int topicId);
typedef PluginFallbackInvalidator =
    void Function(String siteUrl, String capability);
typedef PluginTargetPermissionReader =
    bool Function(String siteUrl, String capability, bool? recordPermission);
typedef PluginTargetSnapshot = ({bool valid, PluginData data});
typedef PluginTargetDataReader =
    PluginTargetSnapshot Function(String siteUrl, PluginTarget target);
typedef PluginWriteCredential = ({String? apiKey, WriteException? failure});

/// A plugin-neutral reference to a serializer-backed topic or post target.
final class PluginTarget {
  const PluginTarget.topic(this.id) : kind = 'topic', topicId = id;

  const PluginTarget.post(this.id, {required this.topicId}) : kind = 'post';

  final String kind;
  final int id;
  final int topicId;
}

/// The complete core surface available while creating plugin session state.
///
/// Adding a host operation is an API change here, rather than an import from
/// core into one plugin's controller or model. Plugins adapt their own types at
/// this boundary and core never needs to know them.
final class CorePluginHost {
  const CorePluginHost({
    required this.api,
    required this.credentials,
    required this.store,
    required this.siteLifecycle,
    required this.currentUserFor,
    required this.siteConfigFor,
    required this.previewEngine,
    required this.applyNotificationDelta,
    required this.markSiteUnreachable,
    required this.canPerform,
    required this.dataForTarget,
    required this.reloadTopic,
    required this.invalidateFallback,
    required this.trackerFor,
    required this.userIdFor,
    required this.capabilityEnabledFor,
    required this.onCallSiteChanged,
    required this.navigation,
  });

  final DiscourseApi api;
  final ApiCredentialReader credentials;
  final Store store;
  final SiteLifecycle siteLifecycle;
  final PluginCurrentUserReader currentUserFor;
  final PluginSiteConfigReader siteConfigFor;
  final ChatPreviewEngine previewEngine;
  final PluginCountDelta applyNotificationDelta;
  final PluginSiteCallback markSiteUnreachable;
  final PluginTargetPermissionReader canPerform;
  final PluginTargetDataReader dataForTarget;
  final PluginTopicReloader reloadTopic;
  final PluginFallbackInvalidator invalidateFallback;
  final PluginTrackerReader trackerFor;
  final PluginUserIdReader userIdFor;
  final PluginCapabilityReader capabilityEnabledFor;
  final void Function() onCallSiteChanged;
  final PluginNavigationHost navigation;
}

const corePluginHostPort = PluginHostPortKey<CorePluginHost>(
  owner: PluginId('core'),
  name: 'host',
);
