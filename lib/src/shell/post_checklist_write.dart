import '../data/discourse_api_contracts.dart';
import '../models/post.dart';
import '../models/post_checklist.dart';

/// One serial write queue per post. Rendering can run ahead of the server.
class PostChecklistWrite {
  PostChecklistWrite({
    required Post post,
    required this.isCurrent,
    required this.publish,
    required this.load,
    required this.save,
  }) : _confirmed = post,
       _visible = post,
       _fingerprint = PostChecklistDocument(post.cooked).fingerprint;

  final bool Function() isCurrent;
  final bool Function(Post previous, Post next) publish;
  final Future<Post> Function() load;
  final Future<PostChecklistUpdate> Function(
    Post post,
    List<Map<String, Object?>> toggles,
  )
  save;
  final String _fingerprint;
  Post _confirmed;
  Post _visible;
  final _pending = <int, bool>{};
  final _inFlight = <int, bool>{};
  bool _accepting = true;

  bool toggle(Post snapshot, PostChecklistTarget target, bool checked) {
    if (!_accepting ||
        !isCurrent() ||
        PostChecklistDocument(snapshot.cooked).fingerprint != _fingerprint) {
      return false;
    }
    final targets = PostChecklistDocument(_confirmed.cooked).targets;
    if (target.index < 0 ||
        target.index >= targets.length ||
        target.count != targets.length ||
        targets[target.index].permanent) {
      return false;
    }
    _pending[target.index] = checked;
    return _project();
  }

  bool _project() => _show(
    _confirmed.copyWith(
      cooked: PostChecklistDocument(
        _confirmed.cooked,
      ).withStates({..._inFlight, ..._pending}),
    ),
  );

  bool _show(Post next) {
    if (!isCurrent()) return false;
    final previous = _visible;
    _visible = next;
    return publish(previous, next);
  }

  void reject() {
    _accepting = false;
    _pending.clear();
    _inFlight.clear();
    _show(_confirmed);
  }

  Future<String?> run() async {
    try {
      // Topic streams often omit raw. Refresh it after projecting the click,
      // then prove that the same checklist is still on screen before saving.
      final fresh = await load();
      if (!isCurrent()) return null;
      if (!fresh.canEdit ||
          fresh.isLocalized ||
          PostChecklistDocument(fresh.cooked).fingerprint != _fingerprint) {
        _accepting = false;
        _show(fresh);
        return 'The post changed. Review its to-dos and try again.';
      }
      _confirmed = fresh;
      if (!_project()) return null;
      while (_pending.isNotEmpty && isCurrent()) {
        final targets = PostChecklistDocument(_confirmed.cooked).targets;
        for (final entry in _pending.entries.take(50).toList()) {
          _pending.remove(entry.key);
          if (targets[entry.key].checked != entry.value) {
            _inFlight[entry.key] = entry.value;
          }
        }
        if (_inFlight.isEmpty) continue;
        final response = await save(_confirmed, [
          for (final entry in _inFlight.entries)
            targets[entry.key].toggle(entry.value),
        ]);
        if (!isCurrent()) return null;
        if (response.version < _confirmed.version ||
            response.updatedAt.isBefore(_confirmed.updatedAt!)) {
          throw const WriteException(WriteFailure.conflict);
        }
        _confirmed = _confirmed.copyWith(
          raw: response.raw,
          cooked: response.cooked,
          updatedAt: response.updatedAt,
          version: response.version,
        );
        _inFlight.clear();
        if (PostChecklistDocument(response.cooked).fingerprint !=
            _fingerprint) {
          _accepting = false;
          _show(_confirmed);
          return 'The post changed. Review its to-dos before continuing.';
        }
        if (!_project()) return null;
      }
      return null;
    } on WriteException catch (error) {
      if (!isCurrent()) return null;
      _accepting = false;
      if (error.failure != WriteFailure.unreachable) {
        reject();
      }
      // A conflict needs the newer post; a lost response might already have
      // committed. Only a successful read can settle an uncertain write.
      if (error.failure == WriteFailure.conflict ||
          error.failure == WriteFailure.forbidden ||
          error.failure == WriteFailure.unreachable) {
        await _reconcile();
      }
      return error.failure == WriteFailure.unreachable
          ? "Couldn't confirm the to-do update. Refresh the post to check its saved state."
          : error.message;
    } catch (_) {
      if (!isCurrent()) return null;
      _accepting = false;
      await _reconcile();
      return "Couldn't confirm the to-do update. Refresh the post to check its saved state.";
    } finally {
      _accepting = false;
    }
  }

  Future<void> _reconcile() async {
    try {
      final fresh = await load();
      _show(fresh);
    } catch (_) {
      // Keep the optimistic view when the outcome is unknown and offline.
    }
  }
}
