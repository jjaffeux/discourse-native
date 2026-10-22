import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


root = Path(__file__).resolve().parent.parent
revision = sys.argv[1] if len(sys.argv) > 1 else None
source_path = 'lib/src/shell/topic_feed_controller.dart'
source = (
    subprocess.check_output(['git', 'show', f'{revision}:{source_path}'], cwd=root, text=True)
    if revision else (root / source_path).read_text()
)
fragment = source[source.index('typedef _RowRange'):source.index('  TopicFeed publish(')] + '}\n'
fragment = fragment.replace(
    'final Map<int, int> rows = {};',
    'final Map<int, int> rows = CountingMap<int, int>();',
)
assert 'rows = CountingMap<int, int>()' in fragment
probe = r'''
var visits = 0;
class CountingMap<K, V> extends MapBase<K, V> {
  final Map<K, V> inner = {};
  @override V? operator [](Object? key) => inner[key];
  @override void operator []=(K key, V value) { inner[key] = value; }
  @override void clear() => inner.clear();
  @override V? remove(Object? key) => inner.remove(key);
  @override Iterable<K> get keys => inner.keys;
  @override Iterable<MapEntry<K, V>> get entries => inner.entries.map((entry) {
    visits++;
    return entry;
  });
  @override void removeWhere(bool Function(K, V) test) =>
      inner.removeWhere((key, value) { visits++; return test(key, value); });
}
void main() {
  final results = <String, Object>{};
  for (final restoring in [false, true]) {
    final first = restoring ? 30 : 0;
    final window = _FeedWindow()
      ..rows.addAll({for (var row = first; row < first + 300; row++) row: row + 1});
    visits = 0;
    window.put(
      restoring ? 0 : 300,
      [for (var i = 0; i < 30; i++) restoring ? i + 1 : i + 301],
      300,
      restoring: restoring,
      preferredRange: restoring ? (first: 0, last: 29) : null,
    );
    if (window.rows.length != 300 || window.rows.values.toSet().length != 300) {
      throw StateError('Invalid retained identities');
    }
    results[restoring ? 'restore' : 'append'] = {
      'retainedEntriesVisitedForIdentity': visits,
      'retainedRows': window.rows.length,
      'insertedRows': 30,
    };
  }
  final protectedWindow = _FeedWindow(readerTopics: () => {31})
    ..rows.addAll({for (var row = 30; row < 330; row++) row: row + 1});
  visits = 0;
  var rejected = false;
  try {
    protectedWindow.put(0, [31, for (var id = 2; id <= 30; id++) id], 300,
        restoring: true);
  } on StateError {
    rejected = true;
  }
  if (!rejected || protectedWindow.rows.length != 300 ||
      protectedWindow.rows[30] != 31 || protectedWindow.rows[0] != null) {
    throw StateError('Protected move changed retained rows');
  }
  results['protectedMoveError'] = {
    'retainedEntriesVisitedForIdentity': visits,
    'retainedRows': protectedWindow.rows.length,
    'errorRejected': rejected,
  };
  final duplicates = _FeedWindow()..rows.addAll({0: 1, 1: 2, 3: 3});
  duplicates.put(1, [1, 2, 1], 300);
  if (duplicates.rows.keys.join(',') != '2,3' ||
      duplicates.rows.values.join(',') != '2,1') {
    throw StateError('Repeated identities changed final insertion order');
  }
  final protectedDuplicate = _FeedWindow(readerTopics: () => {1})
    ..rows.addAll({3: 1, 4: 2});
  rejected = false;
  try {
    protectedDuplicate.put(2, [1, 1], 300, restoring: true);
  } on StateError {
    rejected = true;
  }
  if (!rejected || protectedDuplicate.rows.keys.join(',') != '3,4') {
    throw StateError('Repeated protected identity must reject atomically');
  }
  results['repeatedIdentityControlsPassed'] = true;
  print(jsonEncode(results));
}
'''
with tempfile.TemporaryDirectory(prefix='topic-feed-identity-') as directory:
    path = Path(directory) / 'probe.dart'
    binary = Path(directory) / 'probe'
    path.write_text("import 'dart:collection';\nimport 'dart:convert';\n" + fragment + probe)
    subprocess.run(['dart', 'compile', 'exe', str(path), '-o', str(binary)], check=True, stdout=sys.stderr)
    result = json.loads(subprocess.check_output([str(binary)], text=True))
    print(json.dumps(dict(sourceRevision=revision or 'working tree', sourceSha256=hashlib.sha256(source.encode()).hexdigest(), results=result), indent=2))
