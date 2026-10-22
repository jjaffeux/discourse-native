part of 'shell_controller.dart';

final class _RetainedComposerRegistry {
  _RetainedComposerRegistry(this._drafts);

  final ComposerDraftCoordinator _drafts;
  final Set<ComposerController> _members = {};
  final Map<String, ComposerController> _selected = {};
  ComposerController? _revealTarget;
  int _revealRevision = 0;

  Iterable<ComposerController> get live => List.unmodifiable(_members);
  ComposerController? get revealTarget => _revealTarget;
  int get revealRevision => _revealRevision;

  ComposerController? selected(String? siteUrl) => _selected[siteUrl];

  Iterable<ComposerController> forSite(String siteUrl) =>
      _members.where((composer) => composer.target.siteUrl == siteUrl);

  bool owns(ComposerController? composer) => _members.contains(composer);

  void add(ComposerController composer) {
    _members.add(composer);
    _selected[composer.target.siteUrl] = composer;
  }

  bool select(ComposerController composer, {required String? siteUrl}) {
    if (!owns(composer) ||
        composer.closing ||
        composer.isDisposed ||
        composer.target.siteUrl != siteUrl) {
      return false;
    }
    final previous = selected(siteUrl);
    if (!identical(previous, composer)) {
      previous?.focus.unfocus();
      previous?.titleFocus.unfocus();
    }
    _selected[composer.target.siteUrl] = composer;
    _revealTarget = composer;
    _revealRevision++;
    return true;
  }

  void remove(ComposerController composer) {
    if (!owns(composer)) return;
    final siteUrl = composer.target.siteUrl;
    final wasSelected = identical(selected(siteUrl), composer);
    final index = wasSelected
        ? forSite(siteUrl).toList().indexOf(composer)
        : -1;
    _members.remove(composer);
    if (identical(_revealTarget, composer)) _revealTarget = null;
    if (wasSelected) {
      final remaining = forSite(siteUrl).toList();
      if (remaining.isEmpty) {
        _selected.remove(siteUrl);
      } else {
        final next = remaining[math.min(index, remaining.length - 1)];
        _selected[siteUrl] = next;
        _revealTarget = next;
        _revealRevision++;
      }
    }
    _drafts.detach(composer);
  }

  bool replaceSelected(String? siteUrl) {
    final existing = selected(siteUrl);
    if (existing == null) return true;
    if (existing.discarding || existing.closing) return false;
    if (existing.canSaveDraft &&
        (!existing.target.isPrivateMessage ||
            existing.target.draftKey !=
                ComposerDraft.newPrivateMessageDraftKey)) {
      existing.focus.unfocus();
      existing.titleFocus.unfocus();
      return true;
    }
    _retire(existing);
    return true;
  }

  bool close(ComposerController? composer) {
    if (composer == null || composer.discarding || !owns(composer)) {
      return false;
    }
    _retire(composer);
    return true;
  }

  void _retire(ComposerController composer) {
    _drafts.retire(composer);
    composer.dispose();
    remove(composer);
  }

  void closeSubmitted(ComposerController composer) {
    if (!owns(composer)) return;
    composer.dispose();
    remove(composer);
  }

  void forgetSite(String siteUrl) {
    _drafts.forgetSite(siteUrl);
    for (final composer in forSite(siteUrl).toList()) {
      composer.draftSettled();
      composer.dispose();
      remove(composer);
    }
  }

  void dispose() {
    for (final composer in _members) {
      composer.dispose();
    }
    _members.clear();
    _selected.clear();
    _revealTarget = null;
  }
}
