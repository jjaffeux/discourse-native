import 'package:flutter/material.dart';

import '../data/discourse_api.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

Future<void> showAddInstanceSheet(BuildContext context) {
  return showShellSheet<void>(
    context: context,
    title: 'Add a site',
    builder: (context) => const _AddInstanceForm(),
  );
}

/// Takes whatever the user types, resolves it to a real Discourse, and adds it.
class _AddInstanceForm extends StatefulWidget {
  const _AddInstanceForm();

  @override
  State<_AddInstanceForm> createState() => _AddInstanceFormState();
}

class _AddInstanceFormState extends State<_AddInstanceForm> {
  final TextEditingController _field = TextEditingController();
  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final term = _field.text.trim();
    if (term.isEmpty || _connecting) return;

    setState(() {
      _connecting = true;
      _error = null;
    });

    final controller = ShellScope.of(context);
    String failure;

    try {
      // The duplicate check uses the resolved URL, not what was typed —
      // "meta.discourse.org" and "https://meta.discourse.org/" are one site.
      final instance = await controller.api.lookup(term);

      if (!controller.contains(instance.url)) {
        await controller.addInstance(instance);
        if (mounted) Navigator.of(context).pop();
        return;
      }
      failure = '${instance.title} is already in your list.';
    } on SiteLookupException catch (e) {
      failure = e.message;
    } catch (_) {
      failure = "Couldn't reach $term.";
    }

    if (!mounted) return;
    setState(() {
      _connecting = false;
      _error = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the address of a Discourse forum.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _field,
          autofocus: true,
          enabled: !_connecting,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _connect(),
          decoration: InputDecoration(
            hintText: 'meta.discourse.org',
            prefixIcon: const DIcon(DIcons.globe, size: 20),
            border: const OutlineInputBorder(),
            errorText: _error,
            // Keeps the sheet from resizing as the message appears.
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _connecting ? null : _connect,
          child: _connecting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Connect'),
        ),
      ],
    );
  }
}
