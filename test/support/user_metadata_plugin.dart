import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

const userMetadataTestModule = UserMetadataTestModule();

final class UserMetadataTestModule implements PluginModule {
  const UserMetadataTestModule();
  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('user-metadata-test'));
  @override
  void register(PluginRegistrar registrar) =>
      registrar.addCapability(const UserMetadataTestPlugin());
}

final class UserMetadataTestPlugin
    implements
        SitePlugin,
        UserCardMetadataPlugin,
        UserProfileMetadataPlugin,
        UserDirectoryColumnLabelPlugin {
  const UserMetadataTestPlugin({this.name = 'user-metadata-test'});
  @override
  final String name;

  @override
  List<Widget> userCardMetadata(
    BuildContext context,
    String siteUrl,
    UserCard user,
    VoidCallback close,
  ) => [
    _OwnedMetadata(
      label: 'Card',
      siteUrl: siteUrl,
      user: user,
      callbackOwner: PluginUiScope.ownerOf(context),
    ),
    DButton(label: const Text('Close metadata'), onPressed: close),
  ];
  @override
  List<Widget> userProfileMetadata(
    BuildContext context,
    String siteUrl,
    UserCard user,
  ) => [
    _OwnedMetadata(
      label: 'Profile',
      siteUrl: siteUrl,
      user: user,
      callbackOwner: PluginUiScope.ownerOf(context),
    ),
  ];
  @override
  String? userDirectoryColumnLabel(
    BuildContext context,
    String siteUrl,
    String columnName,
  ) {
    if (PluginUiScope.ownerOf(context).value != name) {
      throw StateError('Wrong directory contribution owner');
    }
    return columnName == 'custom_metric' ? 'Community metric' : null;
  }
}

final class _OwnedMetadata extends StatelessWidget {
  const _OwnedMetadata({
    required this.label,
    required this.siteUrl,
    required this.user,
    required this.callbackOwner,
  });
  final String label, siteUrl;
  final UserCard user;
  final PluginId callbackOwner;
  @override
  Widget build(BuildContext context) => Text(
    '$label metadata ${user.username}: ${user.title ?? 'none'} '
    '${callbackOwner.value}/${PluginUiScope.ownerOf(context).value}',
    key: ValueKey('$label-metadata-$siteUrl-${user.username}'),
  );
}
