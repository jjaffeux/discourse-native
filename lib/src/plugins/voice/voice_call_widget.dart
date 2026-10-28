import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_sdk.dart' show DIcons;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'voice_call_port.dart';

class VoiceCallWidget extends StatelessWidget {
  const VoiceCallWidget({super.key, required this.port});
  final VoiceCallPort port;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: port,
    builder: (context, _) {
      final state = port.state;
      final call = state.call;
      if (!state.supported ||
          call == null ||
          call.status == VoiceCallPresentationStatus.leaving) {
        return const SizedBox.shrink();
      }
      return _FloatingCall(
        key: ObjectKey(call.identity ?? port),
        port: port,
        state: state,
      );
    },
  );
}

class _FloatingCall extends StatefulWidget {
  const _FloatingCall({super.key, required this.port, required this.state});
  final VoiceCallPort port;
  final VoiceCallPortState state;
  @override
  State<_FloatingCall> createState() => _FloatingCallState();
}

class _FloatingCallState extends State<_FloatingCall> {
  final _panel = DFloatingPanelController();
  @override
  void dispose() {
    _panel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final call = state.call!;
    final tokens = DTokens.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    // Reserve the visible dock even while it retracts; browsing must never
    // move a call control onto a navigation action as the dock returns.
    final dock = state.usesMobileNavigation ? 62.0 * math.max(1.0, scale) : 0.0;
    return Offstage(
      offstage: state.roomVisible || state.pictureInPictureActive,
      child: ExcludeFocus(
        excluding: state.roomVisible || state.pictureInPictureActive,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: dock),
            child: DFloatingPanel(
              key: ObjectKey(call.identity ?? widget.port),
              controller: _panel,
              width: 192 * math.min(scale, 1.5),
              restoreLabel: context.l10n.floatingPanelRestore,
              child: DCard(
                spacing: DSpacing.xs,
                backgroundColor: tokens.surface,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: DSpacing.xs),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DAttachment(
                        orientation: DAttachmentOrientation.vertical,
                        constraints: const BoxConstraints(),
                        borderRadius: BorderRadius.circular(DRadius.control),
                        children: [
                          AspectRatio(
                            aspectRatio: 4 / 3,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                call.localVideoPreview ??
                                    Center(
                                      child: DIcon(
                                        DIcons.microphoneLines,
                                        size: 36,
                                        color: tokens.mutedForeground,
                                      ),
                                    ),
                                ?call.reactionOverlay,
                                PositionedDirectional(
                                  start: DSpacing.sm,
                                  end: DSpacing.sm,
                                  bottom: DSpacing.sm,
                                  child: DBadge(
                                    variant: DBadgeVariant.secondary,
                                    child: Text(
                                      call.roomName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                if (call.recording)
                                  PositionedDirectional(
                                    top: DSpacing.sm,
                                    start: DSpacing.sm,
                                    child: DBadge(
                                      variant: DBadgeVariant.destructive,
                                      leading: const DIcon(DIcons.circle),
                                      child: Text(context.l10n.recording),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          DAttachmentTrigger(
                            semanticLabel: context.l10n.voiceReturnToRoom,
                            onPressed: () =>
                                widget.port.dispatch(VoiceCallAction.openRoom),
                          ),
                        ],
                      ),
                      Text(
                        voiceCallStatusLabel(context, call.status),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      if (state.failureMessage ?? call.failureMessage
                          case final error?)
                        DTooltip(
                          message: error,
                          child: DIcon(
                            DIcons.triangleExclamation,
                            color: tokens.destructive,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: DSpacing.xs,
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: DSpacing.controlGap,
                          runSpacing: DSpacing.controlGap,
                          children: [
                            ?call.reactionControl,
                            DTooltip(
                              message: call.muted
                                  ? context.l10n.unmute
                                  : context.l10n.mute,
                              labelTrigger: true,
                              excludeFromSemantics: true,
                              child: DToggle.iconOnly(
                                variant: DToggleVariant.outline,
                                pressed: call.muted,
                                onPressedChanged: (_) => widget.port.dispatch(
                                  VoiceCallAction.toggleMuted,
                                ),
                                semanticLabel: call.muted
                                    ? context.l10n.unmute
                                    : context.l10n.mute,
                                icon: DIcon(
                                  call.muted
                                      ? DIcons.microphoneSlash
                                      : DIcons.microphoneLines,
                                ),
                              ),
                            ),
                            DDropdownMenu(
                              content: DDropdownMenuContent(
                                children: [
                                  DDropdownMenuItem(
                                    onPressed: _panel.tuck,
                                    child: Text(context.l10n.floatingPanelHide),
                                  ),
                                  DDropdownMenuItem(
                                    onPressed: () =>
                                        _panel.moveToEdge(right: false),
                                    child: Text(
                                      context.l10n.floatingPanelMoveLeft,
                                    ),
                                  ),
                                  DDropdownMenuItem(
                                    onPressed: () =>
                                        _panel.moveToEdge(right: true),
                                    child: Text(
                                      context.l10n.floatingPanelMoveRight,
                                    ),
                                  ),
                                ],
                              ),
                              child: DDropdownMenuTrigger(
                                builder: (context, state) => DButton.iconOnly(
                                  tooltip: context.l10n.moreOptions,
                                  icon: const DIcon(DIcons.ellipsis),
                                  variant: DButtonVariant.secondary,
                                  focusNode: state.focusNode,
                                  expanded: state.open,
                                  onPressed: state.toggle,
                                ),
                              ),
                            ),
                            DButton.iconOnly(
                              onPressed: () =>
                                  widget.port.dispatch(VoiceCallAction.leave),
                              variant: DButtonVariant.destructive,
                              tooltip: context.l10n.leaveRoom,
                              icon: const DIcon(DIcons.phoneSlash),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String voiceCallStatusLabel(
  BuildContext context,
  VoiceCallPresentationStatus status,
) => switch (status) {
  VoiceCallPresentationStatus.joining => context.l10n.joining,
  VoiceCallPresentationStatus.connected => context.l10n.voiceConnected,
  VoiceCallPresentationStatus.reconnecting => context.l10n.voiceReconnecting,
  VoiceCallPresentationStatus.leaving => context.l10n.leaving,
  VoiceCallPresentationStatus.failed => context.l10n.voiceCallFailed,
};
