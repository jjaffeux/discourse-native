String relativeTime(DateTime when) {
  final delta = DateTime.now().difference(when);
  if (delta.inDays >= 365) return '${delta.inDays ~/ 365}y';
  if (delta.inDays >= 30) return '${delta.inDays ~/ 30}mo';
  if (delta.inDays >= 1) return '${delta.inDays}d';
  if (delta.inHours >= 1) return '${delta.inHours}h';
  if (delta.inMinutes >= 1) return '${delta.inMinutes}m';
  return 'now';
}

typedef DurationLabel = ({String short, String long});

/// [seconds] spent, as the web's `duration` spells it: `short` in its tiny
/// format for a compact stat, `long` in its medium one for a sentence or a
/// screen reader. Every read-time figure goes through this so a profile and
/// its card never disagree about how long someone has read.
DurationLabel durationLabel(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final minutes = (safe / 60).round().clamp(1, 1 << 31);
  if (safe <= 59) {
    return (short: '<1m', long: 'less than 1 min');
  }
  if (minutes <= 44) {
    return (
      short: '${minutes}m',
      long: '$minutes ${minutes == 1 ? 'min' : 'mins'}',
    );
  }
  if (minutes <= 89) {
    return (short: '1h', long: 'about 1 hour');
  }
  if (minutes <= 1409) {
    final count = (minutes / 60).round();
    return (
      short: '${count}h',
      long: 'about $count ${count == 1 ? 'hour' : 'hours'}',
    );
  }
  if (minutes <= 2519) {
    return (short: '1d', long: '1 day');
  }
  if (minutes <= 129599) {
    final count = (minutes / 1440).round();
    return (short: '${count}d', long: '$count days');
  }
  if (minutes <= 525599) {
    final count = (minutes / 43200).round();
    return (
      short: '${count}mon',
      long: '$count ${count == 1 ? 'month' : 'months'}',
    );
  }

  final years = minutes / 525600;
  final remainder = years % 1;
  if (remainder < 0.25) {
    final count = years.floor();
    return (
      short: '${count}y',
      long: 'about $count ${count == 1 ? 'year' : 'years'}',
    );
  }
  if (remainder < 0.75) {
    final count = years.floor();
    return (
      short: '> ${count}y',
      long: 'over $count ${count == 1 ? 'year' : 'years'}',
    );
  }
  final count = years.floor() + 1;
  return (
    short: '${count}y',
    long: 'almost $count ${count == 1 ? 'year' : 'years'}',
  );
}
