import 'package:flutter/foundation.dart';

import '../data/api_credentials.dart';
import '../data/discourse_api.dart';
import '../data/site_lifecycle.dart';
import '../data/site_tracker.dart';
import '../data/store.dart';
import '../models/discourse_user.dart';
import '../models/site_config.dart';
import 'assign/assignment_controller.dart';
import 'chat/chat_preview.dart';
import 'plugin_manifest.dart';
import 'plugin_runtime.dart';
import 'resenha/resenha_diagnostics.dart';

typedef PluginCurrentUserReader = DiscourseUser? Function(String siteUrl);
typedef PluginSiteConfigReader = SiteConfig Function(String siteUrl);
typedef PluginCountDelta = void Function(String siteUrl, int delta);
typedef PluginSiteCallback = void Function(String siteUrl);
typedef PluginTrackerReader = SiteTracker? Function(String siteUrl);
typedef PluginUserIdReader = int? Function(String siteUrl);
typedef PluginCapabilityReader = Future<bool?> Function(String siteUrl);

const _core = PluginId('core');

const discourseApiPort = PluginHostPortKey<DiscourseApi>(
  owner: _core,
  name: 'discourse-api',
);
const credentialReaderPort = PluginHostPortKey<ApiCredentialReader>(
  owner: _core,
  name: 'credentials',
);
const storePort = PluginHostPortKey<Store>(owner: _core, name: 'store');
const siteLifecyclePort = PluginHostPortKey<SiteLifecycle>(
  owner: _core,
  name: 'site-lifecycle',
);
const currentUserReaderPort = PluginHostPortKey<PluginCurrentUserReader>(
  owner: _core,
  name: 'current-user-reader',
);
const siteConfigReaderPort = PluginHostPortKey<PluginSiteConfigReader>(
  owner: _core,
  name: 'site-config-reader',
);
const chatPreviewEnginePort = PluginHostPortKey<ChatPreviewEngine>(
  owner: _core,
  name: 'chat-preview-engine',
);
const chatNotificationsDeltaPort = PluginHostPortKey<PluginCountDelta>(
  owner: _core,
  name: 'chat-notifications-delta',
);
const siteUnreachablePort = PluginHostPortKey<PluginSiteCallback>(
  owner: _core,
  name: 'site-unreachable',
);
const assignmentPermissionPort = PluginHostPortKey<AssignmentPermissionReader>(
  owner: _core,
  name: 'assignment-permission',
);
const assignmentTopicReloaderPort = PluginHostPortKey<AssignmentTopicReloader>(
  owner: _core,
  name: 'assignment-topic-reloader',
);
const assignmentFallbackInvalidatorPort =
    PluginHostPortKey<AssignmentFallbackInvalidator>(
      owner: _core,
      name: 'assignment-fallback-invalidator',
    );
const trackerReaderPort = PluginHostPortKey<PluginTrackerReader>(
  owner: _core,
  name: 'tracker-reader',
);
const userIdReaderPort = PluginHostPortKey<PluginUserIdReader>(
  owner: _core,
  name: 'user-id-reader',
);
const resenhaCapabilityPort = PluginHostPortKey<PluginCapabilityReader>(
  owner: _core,
  name: 'resenha-capability',
);
const callSiteChangedPort = PluginHostPortKey<VoidCallback>(
  owner: _core,
  name: 'call-site-changed',
);
const resenhaDiagnosticsPort = PluginHostPortKey<ResenhaDiagnosticsRecorder>(
  owner: _core,
  name: 'resenha-diagnostics',
);
