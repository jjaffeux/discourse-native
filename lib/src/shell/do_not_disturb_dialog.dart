import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/do_not_disturb.dart';
import 'external_link.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

Future<void> showDoNotDisturbDialog(
  BuildContext context, {
  required String siteUrl,
  ShellController? controller,
}) {
  final shell = controller ?? ShellScope.read(context);
  final instance = shell.instanceFor(siteUrl);
  final user = instance?.user;
  if (user == null) return Future.value();
  final lease = shell.lifecycle.capture(siteUrl);
  // User-menu routes may be dismissed as soon as this dialog is opened.
  final navigatorContext = Navigator.of(context, rootNavigator: true).context;
  final scope = ShellScope.maybeRead(navigatorContext);
  bool ownsAccount() =>
      navigatorContext.mounted &&
      !shell.accountSessionDisposed &&
      lease.isCurrent &&
      identical(ShellScope.maybeRead(navigatorContext), scope);
  return showDialog<void>(
    context: context,
    builder: (context) => _DoNotDisturbDialog(
      siteUrl: siteUrl,
      username: user.username,
      controller: shell,
      ownsAccount: ownsAccount,
    ),
  );
}

class _DoNotDisturbDialog extends StatefulWidget {
  const _DoNotDisturbDialog({
    required this.siteUrl,
    required this.username,
    required this.controller,
    required this.ownsAccount,
  });

  final String siteUrl;
  final String username;
  final ShellController controller;
  final bool Function() ownsAccount;

  @override
  State<_DoNotDisturbDialog> createState() => _DoNotDisturbDialogState();
}

class _DoNotDisturbDialogState extends State<_DoNotDisturbDialog> {
  DoNotDisturbOption? _saving;
  bool _openingSchedule = false;
  String? _error;

  bool get _isCurrent =>
      mounted &&
      widget.ownsAccount() &&
      ModalRoute.of(context)?.isActive == true;

  bool get _canAct =>
      _isCurrent &&
      ModalRoute.of(context)?.isCurrent == true &&
      _saving == null &&
      !_openingSchedule;

  Future<void> _save(DoNotDisturbOption option) async {
    if (!_canAct) return;
    setState(() {
      _saving = option;
      _error = null;
    });
    final error = await widget.controller.doNotDisturb.pause(
      widget.siteUrl,
      option.duration,
    );
    if (!mounted || !_isCurrent) return;
    if (error == null) {
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    } else {
      setState(() {
        _saving = null;
        _error = error;
      });
    }
  }

  Future<void> _openSchedule() async {
    if (!_canAct) return;
    _openingSchedule = true;
    final toast = DToast.maybeOf(context);
    final ownsAccount = widget.ownsAccount;
    Navigator.of(context).pop();
    final username = Uri.encodeComponent(widget.username);
    final opened = await openExternalLink(
      '${widget.siteUrl}/u/$username/preferences/notifications',
    );
    if (!opened && toast?.isDisposed == false && ownsAccount()) {
      toast!.add(
        const DToastOptions(
          description: 'Could not open notification preferences.',
          type: DToastType.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Pause notifications for…'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final option in DoNotDisturbOption.values)
                  SizedBox(
                    width: 190,
                    child: OutlinedButton(
                      key: ValueKey('do-not-disturb-${option.name}'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                      onPressed: _saving == null
                          ? () => unawaited(_save(option))
                          : null,
                      child: _saving == option
                          ? const SizedBox.square(
                              dimension: 16,
                              child: DSpinner(),
                            )
                          : Text(option.label),
                    ),
                  ),
              ],
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        DButton(
          label: const Text('Set a notification schedule'),
          onPressed: _saving == null ? _openSchedule : null,
        ),
        DButton(
          label: const Text('Cancel'),
          onPressed: _saving == null ? () => Navigator.of(context).pop() : null,
        ),
      ],
    );
  }
}
