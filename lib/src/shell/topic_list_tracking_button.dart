import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/user_preferences.dart';
import '../theme/d_native_icons.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

/// Changes the site's automatic topic-tracking preference from the list header.
class TopicListTrackingButton extends StatefulWidget {
  const TopicListTrackingButton({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<TopicListTrackingButton> createState() =>
      _TopicListTrackingButtonState();
}

class _TopicListTrackingButtonState extends State<TopicListTrackingButton> {
  ShellController? _shell;

  static const _options = [
    DNotificationLevelOption(
      value: -1,
      label: 'Never',
      description: 'Do not automatically track topics you read',
      icon: DIcon(DNativeIcons.bellOff),
    ),
    DNotificationLevelOption(
      value: 0,
      label: 'Immediately',
      description: 'Track a topic as soon as you read it',
      icon: DIcon(DNativeIcons.bell),
    ),
    DNotificationLevelOption(
      value: 30000,
      label: 'After 30 seconds',
      description: 'Track a topic after reading it for 30 seconds',
      icon: DIcon(DNativeIcons.bell),
    ),
    DNotificationLevelOption(
      value: 60000,
      label: 'After 1 minute',
      description: 'Track a topic after reading it for 1 minute',
      icon: DIcon(DNativeIcons.bell),
    ),
    DNotificationLevelOption(
      value: 120000,
      label: 'After 2 minutes',
      description: 'Track a topic after reading it for 2 minutes',
      icon: DIcon(DNativeIcons.bell),
    ),
    DNotificationLevelOption(
      value: 180000,
      label: 'After 3 minutes',
      description: 'Track a topic after reading it for 3 minutes',
      icon: DIcon(DNativeIcons.bell),
    ),
    DNotificationLevelOption(
      value: 240000,
      label: 'After 4 minutes',
      description: 'Track a topic after reading it for 4 minutes',
      icon: DIcon(DNativeIcons.bell),
    ),
    DNotificationLevelOption(
      value: 300000,
      label: 'After 5 minutes',
      description: 'Track a topic after reading it for 5 minutes',
      icon: DIcon(DNativeIcons.bell),
    ),
    DNotificationLevelOption(
      value: 600000,
      label: 'After 10 minutes',
      description: 'Track a topic after reading it for 10 minutes',
      icon: DIcon(DNativeIcons.bell),
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = ShellScope.identityOf(context);
    if (identical(shell, _shell)) return;
    _shell = shell;
    _loadAfterFrame();
  }

  @override
  void didUpdateWidget(TopicListTrackingButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl) _loadAfterFrame();
  }

  void _loadAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final shell = ShellScope.read(context);
      final instance = shell.currentInstance;
      if (instance?.url == widget.siteUrl && instance!.isConnected) {
        unawaited(shell.preferences.load(instance));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    return ListenableBuilder(
      listenable: shell.preferences,
      builder: (context, _) {
        final state = shell.preferences.stateFor(widget.siteUrl);
        final preferences = state?.draft;
        final instance = shell.currentInstance;
        final lease = shell.lifecycle.capture(widget.siteUrl);
        final accountIdentity = shell.currentAccountIdentity;
        final enabled =
            instance?.url == widget.siteUrl &&
            instance?.isConnected == true &&
            state?.username.toLowerCase() ==
                instance?.user?.username.toLowerCase() &&
            preferences?.canEdit == true &&
            preferences?.canChangeTrackingPreferences == true &&
            state?.saving == false &&
            state?.dirty(PreferenceSection.tracking) == false;
        return DNotificationLevelMenu<int>(
          key: ValueKey((shell, widget.siteUrl, lease.session)),
          buttonKey: const ValueKey('topic-list-tracking-button'),
          semanticLabel: 'Automatic topic tracking',
          value: preferences?.autoTrackTopicsAfterMsecs ?? 300000,
          options: _options,
          showChevron: true,
          size: DButtonSize.large,
          variant: DButtonVariant.outline,
          onChanged: enabled
              ? (value) {
                  final currentInstance = shell.currentInstance;
                  if (!lease.isCurrent ||
                      shell.currentAccountIdentity != accountIdentity ||
                      currentInstance?.url != widget.siteUrl ||
                      currentInstance?.isConnected != true) {
                    return;
                  }
                  shell.preferences.edit(
                    widget.siteUrl,
                    PreferenceSection.tracking,
                    (current) =>
                        current.copyWith(autoTrackTopicsAfterMsecs: value),
                  );
                  unawaited(
                    shell.preferences.save(
                      currentInstance!,
                      PreferenceSection.tracking,
                    ),
                  );
                }
              : null,
        );
      },
    );
  }
}
