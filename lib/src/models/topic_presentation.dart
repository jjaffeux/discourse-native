enum TopicPresentation {
  sheet('Sheet'),
  docked('Dock right');

  const TopicPresentation(this.label);
  final String label;
}
