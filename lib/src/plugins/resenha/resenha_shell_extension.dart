// ignore_for_file: prefer_initializing_formals

import '../../models/content_route.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../../plugin_api/plugin_runtime.dart';
import '../../plugin_api/shell_extensions.dart';
import '../../shell/site_url.dart';
import '../../theme/d_icons.dart';
import 'resenha_controller.dart';
import 'resenha_services.dart';

const resenhaShellService = PluginServiceKey<ResenhaShellService>(
  owner: resenhaPluginId,
  name: 'shell',
);

typedef ResenhaRecordingEnabledReader = bool Function(String siteUrl);

final class ResenhaShellService
    implements
        PluginLinkHandler,
        PluginSiteActivator,
        PluginChannelAttachment,
        PluginBackgroundSite,
        PluginComposerHashtagProvider {
  const ResenhaShellService({
    required this.controller,
    required PluginRouteNavigationHost host,
    required ResenhaRecordingEnabledReader recordingEnabled,
  }) : _host = host,
       _recordingEnabled = recordingEnabled;

  final ResenhaController controller;
  final PluginRouteNavigationHost _host;
  final ResenhaRecordingEnabledReader _recordingEnabled;

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
  String? get pluginBackgroundSiteUrl => controller.activeSiteUrl;

  @override
  Future<bool> openPluginUrl(String url) async {
    if (!controller.supportedPlatform) return false;
    final absolute = resolveSiteUrl(url, _host.currentSite?.url);
    final uri = Uri.tryParse(absolute);
    if (uri == null) return false;
    final match = RegExp(r'^/resenha/r/([^/]+)/?$').firstMatch(uri.path);
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
    _host.pushContent(
      ContentRoute(
        id: 'resenha-room-${room.id}',
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
  void attachPluginChannels(String siteUrl, PluginChannelHost channels) =>
      controller.attachChannels(siteUrl, channels);

  @override
  Iterable<String> composerHashtagTypes(String siteUrl) =>
      controller.directory(siteUrl) == null ? const [] : const ['room'];
}
