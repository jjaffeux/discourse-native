// ignore_for_file: prefer_initializing_formals

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'voice_controller.dart';
import 'voice_services.dart';

const voiceShellService = PluginServiceKey<VoiceShellService>(
  owner: voicePluginId,
  name: 'shell',
);

typedef VoiceRecordingEnabledReader = bool Function(String siteUrl);

final class VoiceShellService
    implements PluginLinkHandler, PluginSiteActivator, PluginTrackerAttachment {
  const VoiceShellService({
    required this.controller,
    required PluginRouteNavigationHost host,
    required VoiceRecordingEnabledReader recordingEnabled,
  }) : _host = host,
       _recordingEnabled = recordingEnabled;

  final VoiceController controller;
  final PluginRouteNavigationHost _host;
  final VoiceRecordingEnabledReader _recordingEnabled;

  PluginRouteSite? get currentInstance => _host.currentSite;
  ContentRoute? get currentContent => _host.currentContent;

  int? currentUserIdFor(String siteUrl) => controller.currentUserIdFor(siteUrl);

  bool recordingEnabledFor(String siteUrl) => _recordingEnabled(siteUrl);

  void openRoom({
    required String siteUrl,
    required ContentRoute route,
    bool replaceCurrent = false,
  }) {
    final index = _host.sites.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0) return;
    final sameInstance = _host.currentSite?.url == siteUrl;
    if (!sameInstance) _host.selectInstance(index);
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
    final match = RegExp(
      r'^/voice/r/([^/]+)(?:/invited-by/([^/]+))?/?$',
    ).firstMatch(uri.path);
    if (match == null) return false;
    final index = _host.sites.indexWhere((instance) => instance.serves(uri));
    if (index < 0 || !_host.sites[index].isConnected) return false;
    if (_host.currentSite?.url != _host.sites[index].url) {
      _host.selectInstance(index);
    }
    final instance = _host.sites[index];
    await controller.ensureLoaded(instance.url);
    final room = await controller.resolveRoom(
      instance.url,
      Uri.decodeComponent(match.group(1)!),
    );
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
