part of 'shell_controller.dart';

extension UserProfileNavigation on ShellController {
  /// Opens a person's profile. A visitor may open one: a public site shows
  /// profiles to readers with no account.
  void openUserProfile(
    String siteUrl, {
    required String username,
    String? displayName,
  }) {
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0) return;
    if (index != _instanceIndex) selectInstance(index);
    final route = ContentRoute.userProfile(
      username: username,
      displayName: displayName,
    );
    if (route.sameDestinationAs(currentContent)) {
      showPluginContent();
      return;
    }
    pushContent(route);
  }
}
