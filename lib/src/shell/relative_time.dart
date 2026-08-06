/// Compact relative time, the way a topic list or a post header reads it.
String relativeTime(DateTime when) {
  final delta = DateTime.now().difference(when);
  if (delta.inDays >= 365) return '${delta.inDays ~/ 365}y';
  if (delta.inDays >= 30) return '${delta.inDays ~/ 30}mo';
  if (delta.inDays >= 1) return '${delta.inDays}d';
  if (delta.inHours >= 1) return '${delta.inHours}h';
  if (delta.inMinutes >= 1) return '${delta.inMinutes}m';
  return 'now';
}
