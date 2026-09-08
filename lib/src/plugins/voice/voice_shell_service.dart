// ignore_for_file: prefer_initializing_formals

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/widgets.dart';

import 'voice_controller.dart';
import 'voice_join.dart';
import 'voice_models.dart';
import 'voice_services.dart';

const voiceShellService = PluginServiceKey<VoiceShellService>(
  owner: voicePluginId,
  name: 'shell',
);

typedef VoiceRecordingEnabledReader = bool Function(String siteUrl);
typedef VoiceUsernameReader = String? Function(String siteUrl);

String? _noUsername(String _) => null;

bool _siteDefaultOn(String _) => true;

final class VoiceShellService
    implements PluginLinkHandler, PluginSiteActivator, PluginTrackerAttachment {
  VoiceShellService({
    required this.controller,
    required PluginRouteNavigationHost host,
    required VoiceRecordingEnabledReader recordingEnabled,
    VoiceSiteFlagReader meshPrivacyWarningEnabled = _siteDefaultOn,
    VoiceSiteFlagReader autoStatusEnabled = _siteDefaultOn,
    VoiceUsernameReader currentUsername = _noUsername,
  }) : _host = host,
       _recordingEnabled = recordingEnabled,
       _meshPrivacyWarningEnabled = meshPrivacyWarningEnabled,
       _autoStatusEnabled = autoStatusEnabled,
       _currentUsername = currentUsername;

  final VoiceController controller;
  final PluginRouteNavigationHost _host;
  final VoiceRecordingEnabledReader _recordingEnabled;
  final VoiceSiteFlagReader _meshPrivacyWarningEnabled;
  final VoiceSiteFlagReader _autoStatusEnabled;
  final VoiceUsernameReader _currentUsername;
  Object? _linkNavigation;

  PluginRouteSite? get currentInstance => _host.currentSite;
  ContentRoute? get currentContent => _host.currentContent;

  int? currentUserIdFor(String siteUrl) => controller.currentUserIdFor(siteUrl);

  bool recordingEnabledFor(String siteUrl) => _recordingEnabled(siteUrl);

  bool meshPrivacyWarningEnabledFor(String siteUrl) =>
      _meshPrivacyWarningEnabled(siteUrl);

  bool autoStatusEnabledFor(String siteUrl) => _autoStatusEnabled(siteUrl);

  /// The shareable invite link for [room]: the same URL the plugin's
  /// notifications carry, so joining through it credits this user as the
  /// inviter. Null without a signed-in username to credit.
  String? inviteLinkFor(String siteUrl, VoiceRoom room) {
    final username = _currentUsername(siteUrl);
    if (username == null || username.isEmpty) return null;
    return '$siteUrl/voice/r/${Uri.encodeComponent(room.slug)}/invited-by/'
        '${Uri.encodeComponent(username.toLowerCase())}';
  }

  /// Calls [username]: creates the call room, lands on its page, and joins.
  /// Server refusals propagate so the caller can show them.
  Future<void> callUser(
    BuildContext context, {
    required String siteUrl,
    required String username,
  }) async {
    final room = await controller.callUser(siteUrl, username);
    if (!context.mounted) return;
    await _openAndJoin(context, siteUrl: siteUrl, room: room);
  }

  /// Answers the ringing call: opens its room page and joins it.
  Future<void> answerIncomingCall(BuildContext context) async {
    final accepted = await controller.acceptIncomingCall();
    if (accepted == null || !context.mounted || !accepted.isCurrent) return;
    await _openAndJoin(
      context,
      siteUrl: accepted.siteUrl,
      room: accepted.room,
      ifCurrent: () => accepted.isCurrent,
    );
  }

  Future<void> _openAndJoin(
    BuildContext context, {
    required String siteUrl,
    required VoiceRoom room,
    bool Function()? ifCurrent,
  }) async {
    final siteName =
        _host.sites.where((site) => site.url == siteUrl).firstOrNull?.title ??
        siteUrl;
    if (ifCurrent?.call() == false) return;
    openRoom(
      siteUrl: siteUrl,
      route: ContentRoute(
        id: 'voice-room-${room.id}',
        title: room.name,
        icon: DIcons.microphoneLines,
      ),
      ifCurrent: ifCurrent,
    );
    if (!context.mounted || ifCurrent?.call() == false) return;
    final privacyWarningEnabled = meshPrivacyWarningEnabledFor(siteUrl);
    if (ifCurrent?.call() == false) return;
    await joinVoiceRoom(
      context,
      controller: controller,
      siteUrl: siteUrl,
      siteName: siteName,
      room: room,
      meshPrivacyWarningEnabled: privacyWarningEnabled,
      ifCurrent: ifCurrent,
    );
  }

  void openRoom({
    required String siteUrl,
    required ContentRoute route,
    bool replaceCurrent = false,
    bool Function()? ifCurrent,
  }) {
    final index = _host.sites.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0) return;
    final sameInstance = _host.currentSite?.url == siteUrl;
    if (ifCurrent?.call() == false) return;
    if (!sameInstance) _host.selectInstance(index);
    if (ifCurrent?.call() == false) return;
    if (sameInstance && _host.currentContent?.id == route.id) {
      _host.replaceCurrentContent(route);
      return;
    }
    if (sameInstance && replaceCurrent && _host.currentContent != null) {
      _host.replaceCurrentContent(route);
      return;
    }
    _host.pushContent(route);
  }

  @override
  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
  }) async {
    if (!controller.supportedPlatform) return false;
    final absolute = resolveSiteUrl(url, _host.currentSite?.url);
    final uri = Uri.tryParse(absolute);
    if (uri == null) return false;
    final sites = _host.sites;
    final index = sites.indexWhere((instance) => instance.serves(uri));
    if (index < 0) return false;
    final instance = sites[index];
    if (!instance.isConnected) return false;
    final path = instance.pathWithin(uri);
    if (path == null) return false;
    final match = RegExp(
      r'^/voice/r/([^/]+)(?:/invited-by/([^/]+))?/?$',
    ).firstMatch(path);
    if (match == null) return false;
    final navigation = Object();
    _linkNavigation = navigation;
    final sessionIsCurrent = controller.captureSiteSession(instance.url);
    if (!sessionIsCurrent()) return true;
    if (_host.currentSite?.url != instance.url) {
      _host.selectInstance(index);
    }
    final content = _host.currentContent;
    bool isCurrent() {
      final selected = _host.currentSite;
      return identical(_linkNavigation, navigation) &&
          sessionIsCurrent() &&
          selected?.url == instance.url &&
          selected?.isConnected == true &&
          _host.sites.any(
            (site) => site.url == instance.url && site.isConnected,
          ) &&
          identical(_host.currentContent, content);
    }

    // Retired Voice links remain handled so cancellation cannot launch an
    // external fallback. Only current work may navigate or credit an inviter.
    if (!isCurrent()) return true;
    await controller.ensureLoaded(instance.url);
    if (!isCurrent()) return true;
    final room = await controller.resolveRoom(
      instance.url,
      Uri.decodeComponent(match.group(1)!),
    );
    if (!isCurrent()) return true;
    if (room == null) return false;
    final invitedBy = match.group(2);
    if (invitedBy != null) {
      controller.rememberInviteRef(
        siteUrl: instance.url,
        roomSlug: room.slug,
        username: Uri.decodeComponent(invitedBy).toLowerCase(),
      );
    }
    _host.pushContent(
      ContentRoute(
        id: 'voice-room-${room.id}',
        title: room.name,
        icon: DIcons.microphoneLines,
      ),
    );
    return true;
  }

  @override
  Future<void> activatePluginSite(
    String siteUrl, {
    required bool connected,
  }) async {
    if (connected) await controller.ensureLoaded(siteUrl);
  }

  @override
  void attachPluginTracker(String siteUrl, PluginLiveChannelHandle channels) =>
      controller.attachTracker(siteUrl, channels);
}
