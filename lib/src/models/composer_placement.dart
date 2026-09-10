/// Physical dock position of the composer inside the main content area.
enum ComposerPlacement {
  left('Dock left'),
  bottom('Dock bottom'),
  right('Dock right');

  const ComposerPlacement(this.label);
  final String label;
  bool get isSide => this == left || this == right;
}
