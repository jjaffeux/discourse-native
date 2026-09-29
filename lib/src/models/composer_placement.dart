import 'package:discourse_native/l10n/strings.dart';

/// Physical dock position of the composer inside the main content area.
enum ComposerPlacement {
  left(),
  bottom(),
  right(),
  fullScreen();

  const ComposerPlacement();
  String get label => switch (this) {
    left => appL10n.dockLeft,
    bottom => appL10n.dockBottom,
    right => appL10n.dockRight,
    fullScreen => appL10n.fullScreen,
  };
  bool get isSide => this == left || this == right;
}
