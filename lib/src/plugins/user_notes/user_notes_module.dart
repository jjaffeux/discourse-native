import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'user_notes_api.dart';
import 'user_notes_controller.dart';
import 'user_notes_data.dart';
import 'user_notes_plugin.dart';

const userNotesModule = UserNotesModule();

final class UserNotesModule implements PluginModule {
  const UserNotesModule();
  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: userNotesPluginId);
  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const UserNotesPlugin());
    registrar.addSession(
      (bindings, _) {
        final controller = UserNotesController(
          api: UserNotesApiClient(bindings.require(corePluginTransportPort)),
          requests: bindings.require(corePluginRequestPort),
          account: bindings.require(corePluginFreshAccountPort),
          site: bindings.require(corePluginSiteStatePort),
          cooking: bindings.require(corePluginCookingPort),
          emoji: bindings.require(corePluginEmojiPort),
        );
        return PluginSessionContribution(
          lifecycle: _Lifecycle(controller),
          capabilities: [controller],
          services: [
            PluginService<Object>(userNotesControllerService, controller),
          ],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginRequestPort,
        corePluginFreshAccountPort,
        corePluginSiteStatePort,
        corePluginCookingPort,
        corePluginEmojiPort,
      ],
    );
  }
}

final class _Lifecycle extends PluginSessionLifecycle {
  _Lifecycle(this.controller);
  final UserNotesController controller;
  @override
  void forget(String siteUrl) => controller.forget(siteUrl);
  @override
  void setForeground(bool foreground) => controller.setForeground(foreground);
  @override
  void close() => controller.dispose();
}
