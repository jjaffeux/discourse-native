part of 'global_search_controller.dart';

final class _GlobalSearchExecution {
  _GlobalSearchExecution({
    required this.api,
    required this.credentials,
    required this.currentSite,
    required this.notify,
    required this.updateCapabilities,
  });

  final GlobalSearchApi api;
  final ApiCredentialReader credentials;
  final String? Function() currentSite;
  final VoidCallback notify;
  final void Function(GlobalSearchPage) updateCapabilities;
  final _inFlight = <Object, Set<_SearchAttempt>>{};
  _SearchRun? _run;
  Timer? _debounce;
  VoidCallback? _queued;
  bool _disposed = false;
  int _page = 0, _offset = 0;
  List<GlobalSearchSection> sections = const [];
  GlobalSearchPhase phase = GlobalSearchPhase.idle;
  String? error;
  bool hasMore = false, loadingMore = false;

  void _cancel() {
    _debounce?.cancel();
    _queued = null;
    for (final active in _inFlight.values) {
      for (final attempt in active) {
        if (!attempt.abort.isCompleted) attempt.abort.complete();
      }
    }
  }

  void reset() {
    _run = null;
    _cancel();
    _page = 0;
    _offset = 0;
    loadingMore = false;
    hasMore = false;
    error = null;
    sections = const [];
  }

  void failQuery(String message) {
    _cancel();
    error = message;
    phase = GlobalSearchPhase.failed;
  }

  void start(
    String site,
    SiteLease lease,
    GlobalSearchRequest Function(int page, int offset) prepare, {
    required Duration? delay,
  }) {
    final run = _run = _SearchRun(site, lease, prepare);
    phase = GlobalSearchPhase.loading;
    if (delay == null) {
      _dispatch(run);
    } else {
      _debounce = Timer(delay, () => _dispatch(run));
    }
  }

  void loadMore() {
    if (_disposed ||
        !hasMore ||
        loadingMore ||
        phase == GlobalSearchPhase.loading) {
      return;
    }
    loadingMore = true;
    error = null;
    notify();
    if (_run case final run?) _dispatch(run, append: true);
  }

  bool _current(_SearchRun run) =>
      !_disposed &&
      identical(run, _run) &&
      run.lease.isCurrent &&
      run.site == currentSite();

  bool _accepts(_SearchAttempt attempt) =>
      _current(attempt.run) && !attempt.abort.isCompleted;

  void _dispatch(_SearchRun run, {bool append = false}) {
    if (!_current(run)) return;
    final active = _inFlight.putIfAbsent(run.lease.session, () => {});
    if (active.length >= 2) {
      _queued = () => _dispatch(run, append: append);
      return;
    }
    final attempt = _SearchAttempt(
      run,
      run.prepare(append ? _page + 1 : 0, append ? _offset : 0),
      append,
    );
    active.add(attempt);
    unawaited(_execute(attempt));
  }

  Future<void> _execute(_SearchAttempt attempt) async {
    final run = attempt.run, request = attempt.request;
    try {
      final auth = await AccountRequestSession(
        run.site,
        run.lease,
      ).credentials(credentials);
      if (!_accepts(attempt)) return;
      final key = auth.apiKey;
      final page = await auth.run(
        () => api.search(
          siteUrl: run.site,
          apiKey: key,
          clientId: key == null ? null : auth.clientId,
          request: request,
          abortTrigger: attempt.abort.future,
          onProgress: request.scope == GlobalSearchScope.all && !attempt.append
              ? (progress) {
                  if (!_accepts(attempt)) return;
                  sections = progress;
                  error = _sectionError;
                  phase = GlobalSearchPhase.loading;
                  notify();
                }
              : null,
        ),
      );
      if (!_accepts(attempt)) return;
      if (attempt.append) {
        final all = <GlobalSearchScope, GlobalSearchSection>{
          for (final section in sections) section.scope: section,
        };
        for (final section in page.sections) {
          final previous =
              all[section.scope]?.results ?? const <GlobalSearchResult>[];
          final rows = {
            for (final row in previous) row.id: row,
            for (final row in section.results) row.id: row,
          };
          all[section.scope] = GlobalSearchSection(
            scope: section.scope,
            results: List.unmodifiable(rows.values),
            hasMore: section.hasMore,
            error: section.error,
          );
        }
        sections = List.unmodifiable(all.values);
      } else {
        sections = List.unmodifiable(page.sections);
      }
      _page = request.page;
      _offset = request.offset + page.consumedCount;
      hasMore = page.hasMore && (!attempt.append || page.consumedCount > 0);
      loadingMore = false;
      if (page.groupMemberOrder != null || page.userOrders != null) {
        updateCapabilities(page);
      }
      error = _sectionError;
      phase = _hasResults
          ? GlobalSearchPhase.results
          : error != null
          ? GlobalSearchPhase.failed
          : GlobalSearchPhase.empty;
      notify();
    } catch (exception) {
      if (!_accepts(attempt)) return;
      error = GlobalSearchApi.failureMessage(exception);
      phase = _hasResults
          ? GlobalSearchPhase.results
          : GlobalSearchPhase.failed;
      loadingMore = false;
      notify();
    } finally {
      final active = _inFlight[run.lease.session];
      active?.remove(attempt);
      if (active?.isEmpty == true) _inFlight.remove(run.lease.session);
      final queued = _queued;
      _queued = null;
      if (!_disposed) queued?.call();
    }
  }

  String? get _sectionError => sections
      .where((section) => section.error != null)
      .map((section) => section.error)
      .firstOrNull;

  bool get _hasResults => sections.any((section) => section.results.isNotEmpty);

  void dispose() {
    _disposed = true;
    _run = null;
    _cancel();
  }
}

final class _SearchRun {
  const _SearchRun(this.site, this.lease, this.prepare);

  final String site;
  final SiteLease lease;
  final GlobalSearchRequest Function(int page, int offset) prepare;
}

final class _SearchAttempt {
  _SearchAttempt(this.run, this.request, this.append);

  final _SearchRun run;
  final GlobalSearchRequest request;
  final bool append;
  final abort = Completer<void>();
}
