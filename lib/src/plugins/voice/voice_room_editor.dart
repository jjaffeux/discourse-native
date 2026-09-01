import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/material.dart';

import '../../theme/d_button.dart';
import 'voice_controller.dart';
import 'voice_models.dart';
import 'voice_services.dart';

Future<void> showVoiceRoomEditor(
  BuildContext context, {
  required String siteUrl,
  VoiceRoom? room,
  VoiceController? controller,
  VoiceController Function()? controllerResolver,
}) async {
  final result = await showDialog<VoiceRoomDraft>(
    context: context,
    builder: (context) => _VoiceRoomEditorDialog(room: room),
  );
  if (result == null || !context.mounted) return;
  await (controllerResolver?.call() ??
          controller ??
          PluginUiScope.require(context, voiceControllerService))
      .saveRoom(siteUrl: siteUrl, draft: result, roomId: room?.id);
}

/// A `showDialog` future completes when the route is popped, before its exit
/// animation has removed the form. Disposing these controllers in the caller
/// at that point leaves the outgoing text fields listening to dead objects.
class _VoiceRoomEditorDialog extends StatefulWidget {
  const _VoiceRoomEditorDialog({required this.room});

  final VoiceRoom? room;

  @override
  State<_VoiceRoomEditorDialog> createState() => _VoiceRoomEditorDialogState();
}

class _VoiceRoomEditorDialogState extends State<_VoiceRoomEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _maximum;
  late final TextEditingController _chatChannel;
  late final TextEditingController _chatIdle;
  late bool _isPublic;
  late bool _stage;
  late bool _video;
  late bool _livekit;
  late VoiceQualityProfile _quality;

  VoiceRoom? get _room => widget.room;

  @override
  void initState() {
    super.initState();
    final room = _room;
    _name = TextEditingController(text: room?.name);
    _description = TextEditingController(text: room?.description);
    _maximum = TextEditingController(text: room?.maxParticipants?.toString());
    _chatChannel = TextEditingController(text: room?.chatChannelId?.toString());
    _chatIdle = TextEditingController(text: room?.chatIdleMinutes?.toString());
    _isPublic = room?.isPublic ?? true;
    _stage = room?.type == VoiceRoomType.stage;
    _video = room?.videoEnabled ?? true;
    _livekit = room?.livekitEnabled ?? false;
    _quality = room?.maxQualityProfile ?? VoiceQualityProfile.maximum;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_room == null ? 'Create voice room' : 'Edit voice room'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              isRequired: true,
              child: TextField(
                controller: _name,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Name',
                  helperText: 'Required',
                ),
              ),
            ),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
              minLines: 2,
              maxLines: 5,
            ),
            SwitchListTile.adaptive(
              value: _isPublic,
              onChanged: (value) => setState(() => _isPublic = value),
              title: const Text('Public room'),
            ),
            SwitchListTile.adaptive(
              value: _stage,
              onChanged: (value) => setState(() => _stage = value),
              title: const Text('Stage room'),
            ),
            SwitchListTile.adaptive(
              value: _video,
              onChanged: (value) => setState(() => _video = value),
              title: const Text('Allow video'),
            ),
            TextField(
              controller: _maximum,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Maximum participants',
              ),
            ),
            DSelectField<VoiceQualityProfile>(
              initialValue: _quality,
              decoration: const InputDecoration(
                labelText: 'Maximum media quality',
              ),
              onChanged: (value) =>
                  setState(() => _quality = value ?? _quality),
              items: [
                for (final value in VoiceQualityProfile.values)
                  DropdownMenuItem(value: value, child: Text(value.name)),
              ],
            ),
            TextField(
              controller: _chatChannel,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Chat channel ID (optional)',
              ),
            ),
            TextField(
              controller: _chatIdle,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Chat idle minutes'),
            ),
            if (_room?.livekitEnabled != null)
              SwitchListTile.adaptive(
                value: _livekit,
                onChanged: (value) => setState(() => _livekit = value),
                title: const Text('Use LiveKit'),
              ),
          ],
        ),
      ),
    ),
    actions: [
      DButton(
        onPressed: () => Navigator.pop(context),
        label: const Text('Cancel'),
      ),
      DButton(
        onPressed: _name.text.trim().isEmpty ? null : _save,
        label: const Text('Save'),
        variant: DButtonVariant.primary,
      ),
    ],
  );

  void _save() => Navigator.pop(
    context,
    VoiceRoomDraft(
      name: _name.text.trim(),
      description: _description.text.trim(),
      isPublic: _isPublic,
      type: _stage ? VoiceRoomType.stage : VoiceRoomType.open,
      videoEnabled: _video,
      maxParticipants: int.tryParse(_maximum.text),
      chatChannelId: int.tryParse(_chatChannel.text),
      chatIdleMinutes: int.tryParse(_chatIdle.text),
      livekitEnabled: _room?.livekitEnabled == null ? null : _livekit,
      maxQualityProfile: _quality,
    ),
  );

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _maximum.dispose();
    _chatChannel.dispose();
    _chatIdle.dispose();
    super.dispose();
  }
}
