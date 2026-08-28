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

final class ResenhaShellService
    implements PluginLinkHandler, PluginSiteActivator, PluginTrackerAttachment {
  const ResenhaShellService({required this.controller, required this.host});

  final ResenhaController controller;
  final PluginRouteNavigationHost host;

  PluginRouteSite? get currentInstance => host.currentSite;
  ContentRoute? get currentContent => host.currentContent;

  void openRoom({
    required String siteUrl,
    required ContentRoute route,
    bool replaceCurrent = false,
  }) {
    final index = host.sites.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0) return;
    final sameInstance = host.currentSite?.url == siteUrl;
    if (!sameInstance) host.selectInstance(index);
    if (sameInstance && host.currentContent?.id == route.id) {
      host.replaceCurrentContent(route);
      return;
    }
    if (sameInstance && replaceCurrent && host.currentContent != null) {
      host.replaceCurrentContent(route);
      return;
    }
    host.pushContent(route);
  }

  @override
  Future<bool> openPluginUrl(String url) async {
    if (!controller.supportedPlatform) return false;
    final absolute = resolveSiteUrl(url, host.currentSite?.url);
    final uri = Uri.tryParse(absolute);
    if (uri == null) return false;
    final match = RegExp(r'^/resenha/r/([^/]+)/?$').firstMatch(uri.path);
    if (match == null) return false;
    final index = host.sites.indexWhere((instance) => instance.serves(uri));
    if (index < 0 || !host.sites[index].isConnected) return false;
    if (host.currentSite?.url != host.sites[index].url) {
      host.selectInstance(index);
    }
    final instance = host.sites[index];
    await controller.ensureLoaded(instance.url);
    final room = await controller.resolveRoom(
      instance.url,
      Uri.decodeComponent(match.group(1)!),
    );
    if (room == null) return false;
    host.pushContent(
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
  void attachPluginTracker(String siteUrl, PluginLiveChannelHandle channels) =>
      controller.attachTracker(siteUrl, channels);
}
