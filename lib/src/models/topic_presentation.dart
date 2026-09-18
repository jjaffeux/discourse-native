/// Whether reading tabs share the list panel or occupy their own panel.
enum TopicPresentation {
  merged('Keep topic tabs with the list'),
  split('Split with the list');

  const TopicPresentation(this.label);
  final String label;
}
