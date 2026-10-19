import 'reaction_toggle_result.dart';

extension ReactionTogglePresentation on ReactionToggleResult {
  String? get message => !isCurrent
      ? null
      : switch (kind) {
          ReactionToggleKind.refused ||
          ReactionToggleKind.notSent ||
          ReactionToggleKind.uncertain => failure!.message,
          ReactionToggleKind.applied ||
          ReactionToggleKind.unchanged ||
          ReactionToggleKind.busy ||
          ReactionToggleKind.inactive ||
          ReactionToggleKind.acceptedRetired ||
          ReactionToggleKind.unavailable => null,
        };
}
