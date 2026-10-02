import 'dart:async';

import 'package:flutter/widgets.dart';

import '../plugins/voice/voice_settings.dart';
import 'external_link.dart';
import 'forum_about_page.dart';
import 'shell_scope.dart';

typedef _AboutOwner = ({
  Object? session,
  String? username,
  bool private,
  bool voiceEnabled,
});

class ForumAboutHost extends StatelessWidget {
  const ForumAboutHost({super.key, required this.siteUrl, this.pageKey});

  final String siteUrl;
  final GlobalKey<ForumAboutPageState>? pageKey;

  @override
  Widget build(BuildContext context) => ShellSelector<_AboutOwner>(
    select: (shell) {
      final instance = shell.instanceFor(siteUrl);
      return (
        session: shell.lifecycle.capture(siteUrl).session,
        username: instance?.user?.username,
        private:
            instance == null ||
            (instance.loginRequired && !instance.isConnected),
        voiceEnabled: shell.siteConfigFor(siteUrl).voiceSettings.enabled,
      );
    },
    builder: (context, owner, _) => ForumAboutPage(
      // A new account or site starts with a skeleton and never retains the
      // previous account's permission-gated About data, even during a reload.
      key: pageKey,
      requestIdentity: (siteUrl, owner.session, owner.username, owner.private),
      load: () => ShellScope.read(context).loadForumAbout(siteUrl),
      loginRequired: owner.private,
      voiceEnabled: owner.voiceEnabled,
      onOpenFullPage: () => unawaited(openExternalLink('$siteUrl/about')),
    ),
  );
}
