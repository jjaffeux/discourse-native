import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

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
  final result = await showDDialog<VoiceRoomDraft>(
    context: context,
    builder: (context, dialog) =>
        _VoiceRoomEditorDialog(room: room, dialog: dialog),
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
  const _VoiceRoomEditorDialog({required this.room, required this.dialog});

  final VoiceRoom? room;
  final DDialogController<VoiceRoomDraft> dialog;

  @override
  State<_VoiceRoomEditorDialog> createState() => _VoiceRoomEditorDialogState();
}

class _VoiceRoomEditorDialogState extends State<_VoiceRoomEditorDialog> {
  final _form = GlobalKey<FormState>();
  final _advanced = DAccordionController<String>();
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
  Widget build(BuildContext context) => DDialogContent(
    showCloseButton: false,
    maxWidth: 520,
    semanticLabel: _room == null ? 'Create voice room' : 'Edit voice room',
    children: [
      DDialogHeader(
        children: [
          DDialogTitle(
            child: Text(
              _room == null ? 'Create voice room' : 'Edit voice room',
            ),
          ),
          const DDialogDescription(
            child: Text('Choose how people join and participate in your room.'),
          ),
        ],
      ),
      DDialogScrollArea(
        maxHeightFactor: .65,
        child: Form(
          key: _form,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: DFieldGroup(
            children: [
              DFieldSet(
                semanticLabel: 'Room details',
                children: [
                  DInput(
                    isRequired: true,
                    controller: _name,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    labelText: 'Name',
                    hintText: 'e.g. Community lounge',
                    validator: (value) {
                      final name = value?.trim() ?? '';
                      if (name.isEmpty) return 'Enter a room name.';
                      if (name.runes.length > 80) {
                        return 'Use 80 characters or fewer.';
                      }
                      return null;
                    },
                  ),
                  DTextarea(
                    controller: _description,
                    labelText: 'Description',
                    hintText: 'What will people talk about? (optional)',
                    minLines: 2,
                    maxLines: 5,
                  ),
                ],
              ),
              const DFieldSeparator(),
              DFieldSet(
                children: [
                  const DFieldLegend(child: Text('Room settings')),
                  DFieldGroup(
                    variant: DFieldGroupVariant.choice,
                    children: [
                      DSwitchTile(
                        value: _isPublic,
                        onChanged: (value) => setState(() => _isPublic = value),
                        title: const DFieldLabel(child: Text('Public room')),
                        subtitle: const DFieldDescription(
                          child: Text('Visible to everyone on the forum.'),
                        ),
                      ),
                      DSwitchTile(
                        value: _stage,
                        onChanged: (value) => setState(() => _stage = value),
                        title: const DFieldLabel(child: Text('Stage room')),
                        subtitle: const DFieldDescription(
                          child: Text(
                            'People join as listeners until invited to speak.',
                          ),
                        ),
                      ),
                      DSwitchTile(
                        value: _video,
                        onChanged: (value) => setState(() => _video = value),
                        title: const DFieldLabel(child: Text('Allow video')),
                        subtitle: const DFieldDescription(
                          child: Text(
                            'Let participants share their camera and screen.',
                          ),
                        ),
                      ),
                    ],
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final horizontal =
                          constraints.maxWidth >= 440 &&
                          MediaQuery.textScalerOf(context).scale(14) <= 21;
                      return Flex(
                        direction: horizontal ? Axis.horizontal : Axis.vertical,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        spacing: DSpacing.lg,
                        children: [
                          Flexible(
                            flex: horizontal ? 1 : 0,
                            child: DInput(
                              controller: _maximum,
                              keyboardType: TextInputType.number,
                              labelText: 'Maximum participants',
                              hintText: 'Forum default',
                              helperText: _stage
                                  ? 'Optional, 2–200 people.'
                                  : 'Optional, 2–50 people.',
                              validator: (value) => _validateNumber(
                                value,
                                min: 2,
                                max: _stage ? 200 : 50,
                              ),
                            ),
                          ),
                          Flexible(
                            flex: horizontal ? 1 : 0,
                            child: DSelect<VoiceQualityProfile>.controlled(
                              isExpanded: true,
                              value: _quality,
                              label: const Text('Maximum media quality'),
                              onChanged: (value) =>
                                  setState(() => _quality = value ?? _quality),
                              entries: [
                                for (final value in VoiceQualityProfile.values)
                                  DSelectOption(
                                    value: value,
                                    label: _qualityLabel(value),
                                    child: Text(_qualityLabel(value)),
                                  ),
                              ],
                              initialValue: _quality,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
              const DFieldSeparator(),
              DAccordion<String>(
                controller: _advanced,
                keepMounted: true,
                children: [
                  DAccordionItem<String>(
                    value: 'advanced',
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const DAccordionTrigger(
                          child: Text('Advanced settings'),
                        ),
                        DAccordionContent(
                          child: DFieldGroup(
                            children: [
                              DInput(
                                controller: _chatChannel,
                                keyboardType: TextInputType.number,
                                labelText: 'Chat channel ID (optional)',
                                hintText: 'e.g. 42',
                                helperText:
                                    'Use a channel with threading enabled for room conversations.',
                                validator: (value) =>
                                    _validateNumber(value, min: 1),
                              ),
                              DInput(
                                controller: _chatIdle,
                                keyboardType: TextInputType.number,
                                labelText: 'New chat thread after (minutes)',
                                hintText: '15',
                                helperText:
                                    'Start a fresh thread after 2–1,440 minutes of inactivity. Defaults to 15.',
                                validator: (value) =>
                                    _validateNumber(value, min: 2, max: 1440),
                              ),
                              if (_room?.livekitEnabled != null)
                                DSwitchTile(
                                  value: _livekit,
                                  onChanged: (value) =>
                                      setState(() => _livekit = value),
                                  title: const DFieldLabel(
                                    child: Text('Use LiveKit'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      DDialogFooter(
        children: [
          DDialogClose<VoiceRoomDraft>(
            builder: (context, close) => DButton(
              onPressed: close,
              label: const Text('Cancel'),
              variant: DButtonVariant.outline,
            ),
          ),
          DButton(
            onPressed: _name.text.trim().isEmpty ? null : _save,
            label: Text(_room == null ? 'Create room' : 'Save changes'),
            variant: DButtonVariant.primary,
          ),
        ],
      ),
    ],
  );

  String _qualityLabel(VoiceQualityProfile quality) => switch (quality) {
    VoiceQualityProfile.standard => 'Standard',
    VoiceQualityProfile.high => 'High',
    VoiceQualityProfile.maximum => 'Maximum',
  };

  String? _validateNumber(String? value, {required int min, int? max}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final number = int.tryParse(text);
    if (number == null || number < min || (max != null && number > max)) {
      return max == null
          ? 'Enter a whole number of $min or more.'
          : 'Enter a whole number from $min to $max.';
    }
    return null;
  }

  void _save() {
    final invalid = _form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      if (_validateNumber(_chatChannel.text, min: 1) != null ||
          _validateNumber(_chatIdle.text, min: 2, max: 1440) != null) {
        _advanced.open('advanced');
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && invalid.first.mounted) {
          Scrollable.ensureVisible(invalid.first.context);
        }
      });
      return;
    }
    widget.dialog.close(
      VoiceRoomDraft(
        name: _name.text.trim(),
        description: _description.text.trim(),
        isPublic: _isPublic,
        type: _stage ? VoiceRoomType.stage : VoiceRoomType.open,
        videoEnabled: _video,
        maxParticipants: int.tryParse(_maximum.text.trim()),
        chatChannelId: int.tryParse(_chatChannel.text.trim()),
        chatIdleMinutes: int.tryParse(_chatIdle.text.trim()) ?? 15,
        livekitEnabled: _room?.livekitEnabled == null ? null : _livekit,
        maxQualityProfile: _quality,
      ),
    );
  }

  @override
  void dispose() {
    _advanced.dispose();
    _name.dispose();
    _description.dispose();
    _maximum.dispose();
    _chatChannel.dispose();
    _chatIdle.dispose();
    super.dispose();
  }
}
