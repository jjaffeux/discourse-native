import '../../data/site_tracker.dart';
import '../../models/content_route.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../../plugin_api/plugin_runtime.dart';
import '../../plugin_api/shell_extensions.dart';
import '../../shell/shell_controller.dart';
import '../../shell/site_url.dart';
import '../../theme/d_icons.dart';
import 'resenha_controller.dart';
import 'resenha_services.dart';

const resenhaShellService = PluginServiceKey<ResenhaShellService>(
  owner: resenhaPluginId,
  name: 'shell',
);

final class ResenhaShellService
    implements
        PluginLinkHandler,
        PluginSiteActivator,
        PluginTrackerAttachment,
        PluginBackgroundSite,
        PluginComposerTargetProvider {
  const ResenhaShellService({required this.controller, required this.host});

  final ResenhaController controller;
  final PluginNavigationHost host;

  @override
  String? get pluginBackgroundSiteUrl => controller.activeSiteUrl;

  @override
  Future<bool> openPluginUrl(String url) async {
    if (!controller.supportedPlatform) return false;
    final absolute = resolveSiteUrl(url, host.currentInstance?.url);
    final uri = Uri.tryParse(absolute);
    if (uri == null) return false;
    final match = RegExp(r'^/resenha/r/([^/]+)/?$').firstMatch(uri.path);
    if (match == null) return false;
    final index = host.instances.indexWhere((instance) => instance.serves(uri));
    if (index < 0 || !host.instances[index].isConnected) return false;
    if (host.currentInstance?.url != host.instances[index].url) {
      host.selectInstance(index);
    }
    final instance = host.instances[index];
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
  void attachPluginTracker(String siteUrl, SiteTracker tracker) =>
      controller.attachTracker(siteUrl);

  @override
  bool supportsPluginComposerTarget(String siteUrl, String kind) =>
      kind == 'room' && controller.directory(siteUrl) != null;
}

extension ResenhaShellExtension on ShellController {
  ResenhaShellService get _resenhaShell =>
      pluginSession.require(resenhaShellService);

  ResenhaController get resenha =>
      pluginSession.require(resenhaControllerService);

  Future<bool> openResenhaUrl(String url) => _resenhaShell.openPluginUrl(url);
}
